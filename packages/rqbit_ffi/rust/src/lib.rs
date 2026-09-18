//! Thin C-ABI wrapper around `librqbit`.
//!
//! Exposes just enough to Dart FFI to *boot* rqbit's HTTP API on
//! `127.0.0.1:<port>`; everything after that (adding magnets, listing files,
//! streaming, stats) is driven from Dart over plain HTTP against that API.
//!
//! C surface:
//!   int32_t rqbit_start(uint16_t port, const char* output_dir);  // 0 = ok
//!   void    rqbit_stop(void);
//!   const char* rqbit_last_error(void);  // NUL-terminated, valid until next call

use std::ffi::{c_char, CStr, CString};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Mutex;
use std::thread::JoinHandle;

use librqbit::api::Api;
use librqbit::http_api::{HttpApi, HttpApiOptions};
use librqbit::{Session, SessionOptions};
use librqbit_dualstack_sockets::TcpListener;
use tokio_util::sync::CancellationToken;

struct Engine {
    cancel: CancellationToken,
    thread: JoinHandle<()>,
}

static ENGINE: Mutex<Option<Engine>> = Mutex::new(None);
static LAST_ERROR: Mutex<Option<CString>> = Mutex::new(None);

fn set_error(msg: impl Into<String>) {
    let msg = msg.into();
    eprintln!("[rqbit_ffi] error: {msg}");
    if let Ok(mut g) = LAST_ERROR.lock() {
        *g = CString::new(msg).ok();
    }
}

/// Start the rqbit HTTP API bound to `127.0.0.1:<port>`, storing downloaded
/// data under `output_dir`. Blocks until the listener is bound (or setup fails).
/// Returns 0 on success; a negative code on error (see `rqbit_last_error`).
///
/// # Safety
/// `output_dir` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub extern "C" fn rqbit_start(port: u16, output_dir: *const c_char) -> i32 {
    if output_dir.is_null() {
        set_error("output_dir is null");
        return -10;
    }
    let dir = match unsafe { CStr::from_ptr(output_dir) }.to_str() {
        Ok(s) => s.to_owned(),
        Err(_) => {
            set_error("output_dir is not valid UTF-8");
            return -11;
        }
    };

    let mut guard = match ENGINE.lock() {
        Ok(g) => g,
        Err(_) => {
            set_error("engine lock poisoned");
            return -12;
        }
    };
    if guard.is_some() {
        set_error("engine already running");
        return -13;
    }

    let cancel = CancellationToken::new();
    let cancel_thread = cancel.clone();
    let (tx, rx) = std::sync::mpsc::channel::<Result<(), String>>();

    let thread = std::thread::Builder::new()
        .name("rqbit-engine".into())
        .spawn(move || {
            let rt = match tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(e) => {
                    let _ = tx.send(Err(format!("tokio runtime: {e}")));
                    return;
                }
            };
            rt.block_on(async move {
                let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port);
                let sopts = SessionOptions {
                    persistence: None,
                    cancellation_token: Some(cancel_thread.clone()),
                    dht: Some(librqbit::DhtSessionConfig {
                        persistence: Some(librqbit::dht::DhtPersistenceConfig {
                            config_filename: Some(PathBuf::from(&dir).join("dht.json")),
                            ..Default::default()
                        }),
                        ..Default::default()
                    }),
                    ..Default::default()
                };
                let session = match Session::new_with_opts(PathBuf::from(dir), sopts).await {
                    Ok(s) => s,
                    Err(e) => {
                        let _ = tx.send(Err(format!("session init: {e:#}")));
                        return;
                    }
                };
                // 3rd arg (line_broadcast) exists because the `tracing-subscriber-utils`
                // feature is enabled (required by the http-api handlers).
                let api = Api::new(session.clone(), None, None);
                let http_opts = HttpApiOptions {
                    read_only: false,   // required so POST /torrents works
                    allow_create: true, // enables POST /torrents/create (local seeding)
                    ..Default::default()
                };
                let http_api = HttpApi::new(api, Some(http_opts));
                let listener = match TcpListener::bind_tcp(addr, Default::default()) {
                    Ok(l) => l,
                    Err(e) => {
                        let _ = tx.send(Err(format!("bind {addr}: {e:#}")));
                        return;
                    }
                };
                // Listener is bound -> the API is reachable; signal readiness.
                let _ = tx.send(Ok(()));

                let serve = http_api.make_http_api_and_run(listener, None);
                tokio::select! {
                    _ = cancel_thread.cancelled() => {}
                    r = serve => {
                        if let Err(e) = r {
                            eprintln!("[rqbit_ffi] http api stopped: {e:#}");
                        }
                    }
                }
            });
        });

    let thread = match thread {
        Ok(t) => t,
        Err(e) => {
            set_error(format!("spawn engine thread: {e}"));
            return -14;
        }
    };

    match rx.recv() {
        Ok(Ok(())) => {
            *guard = Some(Engine { cancel, thread });
            0
        }
        Ok(Err(msg)) => {
            set_error(msg);
            let _ = thread.join();
            -1
        }
        Err(_) => {
            set_error("engine thread ended before signalling readiness");
            -2
        }
    }
}

/// Stop the engine and free resources. Safe to call when not running.
#[no_mangle]
pub extern "C" fn rqbit_stop() {
    let engine = ENGINE.lock().ok().and_then(|mut g| g.take());
    if let Some(engine) = engine {
        engine.cancel.cancel();
        let _ = engine.thread.join();
    }
}

/// Returns the last error message as a NUL-terminated C string, or NULL if
/// there was none. The pointer is valid until the next wrapper call.
#[no_mangle]
pub extern "C" fn rqbit_last_error() -> *const c_char {
    match LAST_ERROR.lock() {
        Ok(g) => match g.as_ref() {
            Some(s) => s.as_ptr(),
            None => std::ptr::null(),
        },
        Err(_) => std::ptr::null(),
    }
}
