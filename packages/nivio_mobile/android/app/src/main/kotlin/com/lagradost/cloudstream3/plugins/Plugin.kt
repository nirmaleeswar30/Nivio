package com.lagradost.cloudstream3.plugins

import android.app.Activity
import android.content.Context
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.utils.ExtractorApi

/** Android entry point used by extensions built against the Cloudstream app. */
open class Plugin : BasePlugin() {
    var openSettings: ((Context) -> Unit)? = null

    open fun load(activity: Activity?) = load()

    open fun load(context: Context) = load(context as? Activity)
}
