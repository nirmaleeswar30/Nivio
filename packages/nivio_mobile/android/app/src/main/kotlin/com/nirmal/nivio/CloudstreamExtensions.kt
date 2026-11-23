package com.nirmal.nivio

import android.app.Activity
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.AnimeLoadResponse
import com.lagradost.cloudstream3.AnimeSearchResponse
import com.lagradost.cloudstream3.Episode
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.MovieLoadResponse
import com.lagradost.cloudstream3.MovieSearchResponse
import com.lagradost.cloudstream3.TvSeriesLoadResponse
import com.lagradost.cloudstream3.TvSeriesSearchResponse
import com.lagradost.cloudstream3.TvType
import com.lagradost.cloudstream3.metaproviders.TmdbProvider
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.utils.ExtractorLink
import com.lagradost.cloudstream3.utils.extractorApis
import dalvik.system.DexClassLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.text.Normalizer
import java.util.Collections
import java.util.zip.ZipFile

/** Adapts Cloudstream's Android entry point to Nivio's single-title stream lookup. */
internal class CloudstreamExtensions(activity: Activity, messenger: BinaryMessenger) {
    private val appContext = activity.applicationContext
    private val activityRef = WeakReference(activity)
    private val channel = MethodChannel(messenger, "com.nivio/cloudstream_extensions")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        AcraApplication.attach(appContext, activity)
        channel.setMethodCallHandler { call, result ->
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
            scope.launch {
                try {
                    val streams = withTimeoutOrNull(26_000) {
                        resolve(File(path), request)
                    } ?: throw IllegalStateException("Cloudstream provider timed out")
                    withContext(Dispatchers.Main) { result.success(streams) }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: LinkageError) {
                    withContext(Dispatchers.Main) {
                        result.error("unsupported_extension", "This Cloudstream extension needs an unavailable API", null)
                    }
                } catch (error: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("cloudstream_error", error.message ?: "Cloudstream lookup failed", null)
                    }
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        scope.cancel()
        activityRef.get()?.let(AcraApplication::detach)
    }

    private data class Lookup(val tmdbId: String?, val type: String, val title: String,
        val year: Int?, val season: Int?, val episode: Int?, val absoluteEpisode: Int?) {
        val movie get() = type == "movie"
    }

    private suspend fun resolve(file: File, request: Lookup): List<Map<String, Any>> {
        val root = File(appContext.filesDir, "extensions").canonicalFile
        val pkg = file.canonicalFile
        require(pkg.parentFile == root && pkg.extension == "cs3" && pkg.isFile) { "Invalid Cloudstream package" }
        return loading.withLock {
            val providers = loaded[pkg.path] ?: load(pkg).also { loaded[pkg.path] = it }
            providers.flatMap { provider -> resolveProvider(provider, request) }.take(100)
        }
    }

    private fun load(file: File): List<MainAPI> {
        check(file.setReadOnly() || !file.canWrite()) { "Could not make the extension read-only" }
        val entryClass = ZipFile(file).use { zip ->
            val manifest = zip.getEntry("manifest.json") ?: error("Package has no manifest.json")
            check(manifest.size in 1..65536) { "Invalid package manifest" }
            val json = zip.getInputStream(manifest).bufferedReader().use { JSONObject(it.readText()) }
            json.getString("pluginClassName")
        }
        val loader = DexClassLoader(file.path, appContext.codeCacheDir.path, null, appContext.classLoader)
        val plugin = loader.loadClass(entryClass).asSubclass(BasePlugin::class.java).getDeclaredConstructor().newInstance()
        plugin.filename = file.path
        val knownProviders = APIHolder.allProviders.toSet()
        val knownExtractors = extractorApis.toSet()
        try {
            if (plugin is Plugin) plugin.load(activityRef.get() ?: appContext) else plugin.load()
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

    private suspend fun resolveProvider(api: MainAPI, request: Lookup): List<Map<String, Any>> {
        val tmdbId = request.tmdbId?.toIntOrNull()
        val tmdbResponse = if (api is TmdbProvider && tmdbId != null) {
            val type = if (request.movie) "movie" else "tv"
            tryLoad(api, JSONObject().put("id", tmdbId).put("type", type).toString())
                ?: tryLoad(api, "https://www.themoviedb.org/$type/$tmdbId")
        } else null
        val response = tmdbResponse ?: run {
            val results = api.search(request.title, 1)?.items.orEmpty().distinctBy { it.url }.mapNotNull { match ->
                if (normalize(match.name) != normalize(request.title)) return@mapNotNull null
                if ((match.type in movieTypes) != request.movie) return@mapNotNull null
                val year = when (match) {
                    is MovieSearchResponse -> match.year
                    is TvSeriesSearchResponse -> match.year
                    is AnimeSearchResponse -> match.year
                    else -> null
                }
                if (year != null && request.year != null && year != request.year) return@mapNotNull null
                match to (year != null && year == request.year)
            }
            val best = results.filter { it.second }.ifEmpty { results }.singleOrNull()?.first ?: return emptyList()
            api.load(best.url)
        }
        val data = when (response) {
            is MovieLoadResponse -> response.dataUrl.takeIf { request.movie }
            is TvSeriesLoadResponse -> matchEpisode(response.episodes, request)?.data
            is AnimeLoadResponse -> matchEpisode(response.episodes.values.flatten(), request)?.data
            else -> null
        } ?: return emptyList()
        val links = Collections.synchronizedList(mutableListOf<ExtractorLink>())
        val subtitles = Collections.synchronizedList(mutableListOf<Map<String, Any>>())
        api.loadLinks(data, false, { subtitle ->
            if (subtitles.size < 50) subtitles.add(mapOf("url" to subtitle.url, "lang" to subtitle.lang,
                "headers" to subtitle.headers.orEmpty()))
        }, { link -> if (links.size < 100) links.add(link) })
        val tracks = synchronized(subtitles) { subtitles.toList() }
        return synchronized(links) {
            links.filter { it.url.isNotBlank() }.map { link ->
                mapOf("title" to link.name, "name" to link.source, "url" to link.url,
                    "quality" to if (link.quality > 0) "${link.quality}p" else "Unknown quality",
                    "type" to link.type.name.lowercase(), "headers" to link.headers +
                        (if (link.referer.isBlank()) emptyMap() else mapOf("Referer" to link.referer)),
                    "subtitles" to tracks)
            }
        }
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
        private val loading = Mutex()
        private val loaded = mutableMapOf<String, List<MainAPI>>()
        private val movieTypes = setOf(TvType.Movie, TvType.AnimeMovie, TvType.Documentary, TvType.Torrent)
    }
}
