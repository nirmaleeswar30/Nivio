package com.lagradost.cloudstream3

import android.app.Activity
import android.content.Context
import com.lagradost.api.setContext
import java.lang.ref.WeakReference

/** Provides the context entry points used by Android Cloudstream extensions. */
open class AcraApplication {
    companion object {
        @JvmStatic
        var context: Context? = null
            private set

        private var activity = WeakReference<Activity>(null)

        @JvmStatic
        fun getActivity(): Activity? = activity.get()

        fun attach(application: Context, current: Activity) {
            context = application
            activity = WeakReference(current)
            setContext(WeakReference<Any>(current))
        }

        fun detach(current: Activity) {
            if (activity.get() !== current) return
            activity.clear()
            context?.let { setContext(WeakReference(it)) }
        }
    }
}
