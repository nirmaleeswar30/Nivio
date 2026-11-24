package com.nirmal.nivio

import android.content.Context
import android.content.res.AssetManager
import android.content.res.Resources
import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.AnimeLoadResponse
import com.lagradost.cloudstream3.AnimeSearchResponse
import com.lagradost.cloudstream3.Episode
import com.lagradost.cloudstream3.LoadResponse
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.MainPageRequest
import com.lagradost.cloudstream3.MovieLoadResponse
import com.lagradost.cloudstream3.MovieSearchResponse
import com.lagradost.cloudstream3.SearchResponse
import com.lagradost.cloudstream3.TvSeriesLoadResponse
import com.lagradost.cloudstream3.TvSeriesSearchResponse
import com.lagradost.cloudstream3.TvType
import com.lagradost.cloudstream3.fixUrl
import com.lagradost.cloudstream3.metaproviders.TmdbProvider
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.ExtractorLink
import com.lagradost.cloudstream3.utils.Qualities
import com.lagradost.cloudstream3.utils.extractorApis
import dalvik.system.DexClassLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.text.Normalizer
import java.util.Collections
import java.util.zip.ZipFile

/** Adapts Cloudstream's Android entry point to Nivio's single-title stream lookup. */
internal class CloudstreamExtensions(activity: AppCompatActivity, messenger: BinaryMessenger) {
    private val appContext = activity.applicationContext
    private val activityRef = WeakReference(activity)
    private val channel = MethodChannel(messenger, "com.nivio/cloudstream_extensions")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cncSupportPromptGuard = object : FragmentManager.FragmentLifecycleCallbacks() {
        override fun onFragmentCreated(fm: FragmentManager, f: Fragment, savedInstanceState: Bundle?) {
            if (f is DialogFragment && f.tag == "donation_dialog" &&
                f.javaClass.name == "com.cncverse.donation.DonationDialogFragment"
            ) {
                // CNC Verse requests this dialog during background catalog lookups.
                f.showsDialog = false
                f.dismissAllowingStateLoss()
            }
        }
    }

    init {
        AcraApplication.attach(appContext, activity)
        activity.supportFragmentManager.registerFragmentLifecycleCallbacks(cncSupportPromptGuard, false)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "prepare") {
                val paths = call.argument<List<String>>("paths").orEmpty()
                scope.launch {
                    try {
                        val files = paths.mapNotNull { path -> extensionFile(path)?.let { path to it } }
                        val registered = registration.withLock {
                            registerMissing(files.map { it.second }, allowFailures = true)
                            files.mapNotNull { (path, file) -> path.takeIf { file.path in loaded } }
                        }
                        withContext(Dispatchers.Main) { result.success(registered) }
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                        withContext(Dispatchers.Main) {
                            result.error("cloudstream_error", "Could not register Cloudstream extensions", null)
                        }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method != "resolve") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val type = call.argument<String>("type")
            val title = call.argument<String>("title")
            if (path == null || type == null || title.isNullOrBlank()) {
                result.error("invalid_request", "Missing package or title", null)
                return@setMethodCallHandler
            }
            val request = Lookup(call.argument("id"), type, title, call.argument<String>("year")?.toIntOrNull(),
                call.argument("season"), call.argument("episode"), call.argument("absoluteEpisode"))
            val providerName = call.argument<String>("provider")
            val excludedProviders = call.argument<List<String>>("excludeProviders").orEmpty().toSet()
            scope.launch {
                try {
                    val streams = resolve(path, request, providerName, excludedProviders)
                    withContext(Dispatchers.Main) { result.success(streams) }
                } catch (error: Throwable) {
                    if (!isProviderFailure(error)) throw error
                    withContext(Dispatchers.Main) {
                        if (error is LinkageError || error is NotImplementedError) {
                            result.error("unsupported_extension", "This Cloudstream extension needs an unavailable API", null)
                        } else {
                            result.error("cloudstream_error", error.message ?: "Cloudstream lookup failed", null)
                        }
                    }
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        scope.cancel()
        activityRef.get()?.let { activity ->
            activity.supportFragmentManager.unregisterFragmentLifecycleCallbacks(cncSupportPromptGuard)
            AcraApplication.detach(activity)
        }
    }

    private data class Lookup(val tmdbId: String?, val type: String, val title: String,
        val year: Int?, val season: Int?, val episode: Int?, val absoluteEpisode: Int?) {
        val movie get() = type == "movie"
    }

    private fun extensionFile(path: String): File? {
        val root = File(appContext.filesDir, "extensions").canonicalFile
        val file = File(path).canonicalFile
        return file.takeIf { it.parentFile == root && it.extension == "cs3" && it.isFile }
    }

    private suspend fun registerMissing(files: List<File>, allowFailures: Boolean) {
        val missing = files.distinct().filter { it.path !in loaded }
        if (missing.isEmpty()) return

        // Cloudstream stores extractors in a mutable list. Wait until active
        // readers are done before adding entries, with admission held closed.
        var reserved = 0
        try {
            repeat(MAX_CONCURRENT_LOOKUPS) {
                lookupSlots.acquire()
                reserved++
            }
            for (file in missing) {
                try {
                    loaded[file.path] = load(file)
                } catch (error: Throwable) {
                    if (!allowFailures || !isProviderFailure(error)) throw error
                    Log.w(TAG, "Extension registration failed (${error.javaClass.simpleName})")
                }
            }
        } finally {
            repeat(reserved) { lookupSlots.release() }
        }
    }

    private suspend fun resolve(
        path: String,
        request: Lookup,
        providerName: String?,
        excludedProviders: Set<String>,
    ): List<Map<String, Any>> {
        val file = requireNotNull(extensionFile(path)) { "Invalid Cloudstream package" }
        val providers = registration.withLock {
            registerMissing(listOf(file), allowFailures = false)
            val registered = loaded.getValue(file.path).filter { provider ->
                (providerName == null || provider.name == providerName) &&
                    provider.name !in excludedProviders
            }
            lookupSlots.acquire()
            registered
        }
        try {
            val streams = mutableListOf<Map<String, Any>>()
            val completed = withTimeoutOrNull(LOOKUP_TIMEOUT_MS) {
                var failure: Throwable? = null
                for (provider in providers) {
                    Log.d(TAG, "${provider.name}: lookup started")
                    try {
                        val resolved = resolveProvider(provider, request)
                        Log.d(TAG, "${provider.name}: ${resolved.size} usable links")
                        streams += resolved.take(MAX_LINKS - streams.size)
                        if (streams.size == MAX_LINKS) break
                    } catch (error: Throwable) {
                        if (!isProviderFailure(error)) throw error
                        Log.d(TAG, "${provider.name}: lookup failed (${error.javaClass.simpleName})")
                        if (failure == null) failure = error
                    }
                }
                if (streams.isEmpty()) failure?.let { throw it }
                true
            }
            if (completed == null) {
                Log.d(TAG, "${providers.joinToString { it.name }}: lookup deadline reached")
            }
            check(completed != null || streams.isNotEmpty()) { "Cloudstream provider timed out" }
            return streams
        } finally {
            lookupSlots.release()
        }
    }

    private fun load(file: File): List<MainAPI> {
        check(file.setReadOnly() || !file.canWrite()) { "Could not make the extension read-only" }
        val manifest = ZipFile(file).use { zip ->
            val manifest = zip.getEntry("manifest.json") ?: error("Package has no manifest.json")
            check(manifest.size in 1..65536) { "Invalid package manifest" }
            zip.getInputStream(manifest).bufferedReader().use { JSONObject(it.readText()) }
        }
        val loader = DexClassLoader(file.path, appContext.codeCacheDir.path, null, appContext.classLoader)
        val plugin = loader.loadClass(manifest.getString("pluginClassName"))
            .asSubclass(BasePlugin::class.java).getDeclaredConstructor().newInstance()
        plugin.filename = file.path
        val knownProviders = APIHolder.allProviders.toSet()
        val knownExtractors = extractorApis.toSet()
        try {
            if (plugin is Plugin) {
                val host: Context = checkNotNull(activityRef.get()) { "Cloudstream activity is unavailable" }
                if (manifest.optBoolean("requiresResources")) {
                    plugin.resources = loadResources(file, host.resources)
                }
                plugin.load(host)
            } else {
                plugin.load()
            }
            val providers = APIHolder.allProviders.filter { it !in knownProviders }
            check(providers.isNotEmpty()) { "This extension did not register any playback providers" }
            providers.forEach(MainAPI::init)
            return providers
        } catch (error: Throwable) {
            APIHolder.allProviders.filter { it !in knownProviders }.forEach(APIHolder::removePluginMapping)
            APIHolder.allProviders.removeAll { it !in knownProviders }
            extractorApis.removeAll { it !in knownExtractors }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun loadResources(file: File, base: Resources): Resources {
        // Cloudstream packages contain compiled resources without an installed
        // Android package. Load them into an asset manager private to the .cs3.
        val assets = AssetManager::class.java.getDeclaredConstructor().newInstance()
        val addAssetPath = AssetManager::class.java.getMethod("addAssetPath", String::class.java)
        check(addAssetPath.invoke(assets, file.path) as Int != 0) { "Invalid extension resources" }
        return Resources(assets, base.displayMetrics, base.configuration)
    }

    private suspend fun resolveProvider(api: MainAPI, request: Lookup): List<Map<String, Any>> {
        val tmdbId = request.tmdbId?.toIntOrNull()
        val tmdbResponse = if (api is TmdbProvider && tmdbId != null) {
            val type = if (request.movie) "movie" else "tv"
            tryLoad(api, JSONObject().put("id", tmdbId).put("type", type).toString())
                ?: tryLoad(api, "https://www.themoviedb.org/$type/$tmdbId")
        } else null
        val response = tmdbResponse ?: run {
            val candidates = try {
                api.search(request.title, 1)?.items.orEmpty().distinctBy { it.url }
            } catch (error: NotImplementedError) {
                if (!api.hasMainPage) throw error
                return@run loadFromCatalog(api, request)
            }
            val results = candidates.mapNotNull { candidate ->
                val match = matchTitle(candidate.name, candidate.releaseYear, request) ?: return@mapNotNull null
                candidate to match
            }
            val typed = results.filter { (candidate, _) -> (candidate.type in movieTypes) == request.movie }
            // Some extensions use generic anime cards for their movie search
            // and supply the actual media type only in load().
            val provisional = typed.isEmpty() && request.movie && api.supportedTypes.any(movieTypes::contains)
            val matching = if (provisional) {
                results.filter { (candidate, _) ->
                    candidate is AnimeSearchResponse && candidate.type == TvType.Anime
                }
            } else typed
            val best = matching.filter { it.second }.ifEmpty { matching }.singleOrNull()?.first
            if (best == null) {
                Log.d(TAG, "${api.name}: no unique title match in ${candidates.size} search results")
                return emptyList()
            }
            val loaded = api.load(best.url)
            if (provisional && (loaded == null ||
                    loaded.type !in movieTypes || matchTitle(loaded.name, loaded.year, request) == null)) {
                Log.d(TAG, "${api.name}: movie did not match the loaded provider result")
                return emptyList()
            }
            loaded
        }
        val data = when (response) {
            is MovieLoadResponse -> response.dataUrl.takeIf { request.movie }
            is TvSeriesLoadResponse -> playbackData(response.type, response.episodes, request)
            is AnimeLoadResponse -> playbackData(response.type, response.episodes.values.flatten(), request)
            else -> null
        }
        if (data == null) {
            Log.d(TAG, "${api.name}: no playback data for the requested item")
            return emptyList()
        }
        val links = Collections.synchronizedList(mutableListOf<ExtractorLink>())
        val subtitles = Collections.synchronizedList(mutableListOf<Map<String, Any>>())
        val completed = try {
            withTimeoutOrNull(LINK_TIMEOUT_MS) {
                api.loadLinks(data, false, { subtitle ->
                    synchronized(subtitles) {
                        if (subtitles.size < 50) subtitles.add(mapOf(
                            "url" to subtitle.url, "lang" to subtitle.lang,
                            "headers" to subtitle.headers.orEmpty(),
                        ))
                    }
                }, { link ->
                    synchronized(links) { if (links.size < MAX_LINKS) links.add(link) }
                })
            }
        } catch (error: Throwable) {
            if (!isProviderFailure(error) || links.isEmpty()) throw error
            Log.d(TAG, "${api.name}: returning partial links after ${error.javaClass.simpleName}")
            false
        }
        if (completed == null) Log.d(TAG, "${api.name}: link extraction timed out")
        check(completed != null || links.isNotEmpty()) { "Cloudstream link lookup timed out" }
        val tracks = synchronized(subtitles) { subtitles.toList() }
        return synchronized(links) {
            links.filter { it.url.isNotBlank() }.map { link ->
                mapOf("title" to link.name, "name" to link.source, "url" to link.url,
                    "quality" to if (link.quality > 0 && link.quality != Qualities.Unknown.value)
                        "${link.quality}p" else "Unknown quality",
                    "type" to link.type.name.lowercase(), "headers" to link.headers +
                        (if (link.referer.isBlank()) emptyMap() else mapOf("Referer" to link.referer)),
                    "subtitles" to tracks)
            }
        }
    }

    private val SearchResponse.releaseYear: Int?
        get() = when (this) {
            is MovieSearchResponse -> year
            is TvSeriesSearchResponse -> year
            is AnimeSearchResponse -> year
            else -> null
        }

    private suspend fun loadFromCatalog(api: MainAPI, request: Lookup): LoadResponse? {
        Log.d(TAG, "${api.name}: looking up title in its catalog")
        val matches = Collections.synchronizedList(mutableListOf<Pair<LoadResponse, Boolean>>())
        withTimeoutOrNull(CATALOG_LOOKUP_TIMEOUT_MS) {
            val cards = api.mainPage.withIndex().flatMap { (index, page) ->
                if (index > 0 && api.sequentialMainPage) delay(api.sequentialMainPageDelay)
                api.getMainPage(1, MainPageRequest(page.name, page.data, page.horizontalImages))
                    ?.items.orEmpty().flatMap { it.list }
            }.filter { it.url.isNotBlank() }.distinctBy { it.url }
            val namedMatches = cards.filter { matchTitle(it.name, it.releaseYear, request) != null }
            // Some catalog cards contain just a poster and the provider's playback ID.
            val untitled = cards.filter { it.name.isBlank() }
            for (batch in (namedMatches + untitled).chunked(CATALOG_DETAIL_CONCURRENCY)) {
                coroutineScope {
                    batch.map { card ->
                        async {
                            val response = loadCatalogCard(api, card.url) ?: return@async
                            if ((response.type in movieTypes) != request.movie) return@async
                            val match = matchTitle(response.name, response.year, request) ?: return@async
                            matches.add(response to match)
                        }
                    }.awaitAll()
                }
                if (matches.any { it.second }) break
            }
        }
        return matches.filter { it.second }.ifEmpty { matches }.singleOrNull()?.first
    }

    private suspend fun loadCatalogCard(api: MainAPI, url: String): LoadResponse? =
        catalogDetailSlots.withPermit {
            try {
                api.load(api.fixUrl(url))
            } catch (error: Throwable) {
                if (!isProviderFailure(error)) throw error
                null
            }
        }

    private fun playbackData(type: TvType, episodes: List<Episode>, request: Lookup): String? =
        if (request.movie && type in movieTypes) episodes.map { it.data }.distinct().singleOrNull()
        else matchEpisode(episodes, request)?.data

    /** A null rank means the title or known year conflicts with the request. */
    private fun matchTitle(title: String, year: Int?, request: Lookup): Boolean? {
        val trimmed = title.trim()
        val suffix = titleYear.find(trimmed)
        val suffixYear = suffix?.groupValues?.get(1)?.toInt()
        val normalized = normalize(request.title)
        val exact = normalize(title) == normalized
        val knownYear = year ?: suffixYear.takeUnless { exact }
        if (knownYear != null && request.year != null && knownYear != request.year) return null
        if (!exact && (suffix == null || knownYear != suffixYear || request.year != suffixYear ||
                normalize(trimmed.substring(0, suffix.range.first)) != normalized)) return null
        return knownYear != null && knownYear == request.year
    }

    private fun matchEpisode(episodes: List<Episode>, request: Lookup): Episode? {
        return episodes.firstOrNull { it.episode == request.episode && it.season == request.season }
            ?: episodes.firstOrNull { it.episode == request.episode && it.season == null }
            ?: request.absoluteEpisode?.let { number -> episodes.firstOrNull { it.episode == number } }
    }

    private suspend fun tryLoad(api: MainAPI, url: String) = try {
        api.load(url)
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }

    private fun normalize(title: String) = Normalizer.normalize(title.lowercase(), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()

    companion object {
        private const val TAG = "NivioCloudstream"
        private const val MAX_CONCURRENT_LOOKUPS = 10
        private const val LOOKUP_TIMEOUT_MS = 120_000L
        private const val LINK_TIMEOUT_MS = 60_000L
        private const val CATALOG_LOOKUP_TIMEOUT_MS = 10_000L
        private const val CATALOG_DETAIL_CONCURRENCY = 4
        private const val MAX_LINKS = 100
        private val registration = Mutex()
        private val lookupSlots = Semaphore(MAX_CONCURRENT_LOOKUPS)
        private val catalogDetailSlots = Semaphore(CATALOG_DETAIL_CONCURRENCY)
        private val loaded = mutableMapOf<String, List<MainAPI>>()
        private val movieTypes = setOf(TvType.Movie, TvType.AnimeMovie, TvType.Documentary, TvType.Torrent)
        private val titleYear = Regex("""\s+\(((?:18|19|20)\d{2})\)$""")

        private fun isProviderFailure(error: Throwable) =
            error is LinkageError || error is NotImplementedError ||
                (error is Exception && error !is CancellationException)
    }
}
