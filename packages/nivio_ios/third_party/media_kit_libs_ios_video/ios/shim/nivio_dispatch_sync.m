// Linked into Mpv.framework only (not exported): replaces dispatch_sync for the
// libraries in it, to break a deadlock between libmpv and Flutter on iOS.
//
// vo_avfoundation runs some display-layer work on the main thread and waits
// for it (dispatch_sync to the main queue) while mpv's core waits for the
// video output, e.g. when the output starts or the layer is resized. On iOS,
// Flutter runs Dart on the main thread, and media_kit calls libmpv's
// synchronous API (mpv_set_property, mpv_get_property, mpv_command...) from
// Dart, which waits for mpv's core. If such a call comes in at that moment,
// the three wait on each other forever.
//
// Here a dispatch_sync to the main queue from another thread first waits for
// the main thread as usual. If the main thread has not started the block
// within 150 ms (it is then almost certainly blocked inside a libmpv call
// waiting for this thread), the block runs on the calling thread instead,
// inside an explicit Core Animation transaction. Whichever side claims the
// block first runs it; it never runs twice. Every other dispatch_sync goes
// straight to libdispatch.
//
// Compiled without ARC.

#define dispatch_sync nivio_libdispatch_dispatch_sync_declaration
#include <dispatch/dispatch.h>
#undef dispatch_sync

#import <QuartzCore/QuartzCore.h>
#include <Block.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

typedef struct {
    atomic_int claimed; // 0: nobody yet, 1: claimed (by main or the caller)
    atomic_int refs;
    dispatch_block_t block;
    dispatch_semaphore_t done;
} nivio_main_job;

static void nivio_job_release(nivio_main_job *job)
{
    if (atomic_fetch_sub(&job->refs, 1) == 1) {
        Block_release(job->block);
        dispatch_release(job->done);
        free(job);
    }
}

static void nivio_job_run_on_main(void *ctx)
{
    nivio_main_job *job = ctx;
    int expected = 0;
    if (atomic_compare_exchange_strong(&job->claimed, &expected, 1)) {
        job->block();
        dispatch_semaphore_signal(job->done);
    }
    nivio_job_release(job);
}

static void nivio_invoke_block(void *ctx)
{
    ((dispatch_block_t)ctx)();
}

void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block);

void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block)
{
    if (queue != dispatch_get_main_queue() || pthread_main_np()) {
        dispatch_sync_f(queue, (void *)block, nivio_invoke_block);
        return;
    }

    nivio_main_job *job = calloc(1, sizeof(*job));
    atomic_init(&job->claimed, 0);
    atomic_init(&job->refs, 2); // the main-queue task and this caller
    job->block = Block_copy(block);
    job->done = dispatch_semaphore_create(0);
    dispatch_async_f(dispatch_get_main_queue(), job, nivio_job_run_on_main);

    for (;;) {
        if (dispatch_semaphore_wait(job->done, dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC)) == 0)
            break; // the main thread ran it
        int expected = 0;
        if (atomic_compare_exchange_strong(&job->claimed, &expected, 1)) {
            // The main thread is stuck: run it here. Layer changes off the
            // main thread need an explicit transaction to be committed.
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            job->block();
            [CATransaction commit];
            break;
        }
        // The main thread claimed it and is running it; wait for it to finish.
    }
    nivio_job_release(job);
}
