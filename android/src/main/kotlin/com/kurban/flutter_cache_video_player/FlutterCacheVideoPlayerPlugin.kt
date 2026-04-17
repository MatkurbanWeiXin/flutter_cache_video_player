package com.kurban.flutter_cache_video_player

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.abs

/// 插件主类，注册 MethodChannel 和 EventChannel，管理 ExoPlayer 生命周期。
/// Main plugin class registering MethodChannel and EventChannel, managing ExoPlayer lifecycle.
class FlutterCacheVideoPlayerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var exoPlayer: ExoPlayer? = null
    private var surface: Surface? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerExecutor = Executors.newSingleThreadExecutor()
    private var currentUrl: String? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    private val positionRunnable = object : Runnable {
        override fun run() {
            exoPlayer?.let { player ->
                val state = player.playbackState
                if (state == Player.STATE_READY || state == Player.STATE_BUFFERING) {
                    sendEvent("position", player.currentPosition)
                }
            }
            mainHandler.postDelayed(this, 200)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        textureRegistry = binding.textureRegistry

        methodChannel = MethodChannel(binding.binaryMessenger, "flutter_cache_video_player/player")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flutter_cache_video_player/player/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        releasePlayer()
        flutterPluginBinding = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "create" -> handleCreate(result)
            "open" -> handleOpen(call, result)
            "play" -> handlePlay(result)
            "pause" -> handlePause(result)
            "seek" -> handleSeek(call, result)
            "setVolume" -> handleSetVolume(call, result)
            "setSpeed" -> handleSetSpeed(call, result)
            "dispose" -> handleDispose(result)
            "takeSnapshot" -> handleTakeSnapshot(result)
            "extractCovers" -> handleExtractCovers(call, result)
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    /// 创建 ExoPlayer 实例和 SurfaceTexture，返回纹理 ID。
    /// Creates an ExoPlayer instance and SurfaceTexture, returns texture ID.
    private fun handleCreate(result: Result) {
        val binding = flutterPluginBinding ?: run {
            result.error("NO_ENGINE", "Flutter engine not attached", null)
            return
        }

        // Create texture entry
        textureEntry = textureRegistry?.createSurfaceTexture()
        val surfaceTexture: SurfaceTexture = textureEntry!!.surfaceTexture()
        surface = Surface(surfaceTexture)

        // Create ExoPlayer
        val player = ExoPlayer.Builder(binding.applicationContext).build()
        player.setVideoSurface(surface)
        player.addListener(playerListener)
        exoPlayer = player

        // Start position reporting
        mainHandler.post(positionRunnable)

        result.success(textureEntry!!.id())
    }

    /// 打开媒体 URL。
    /// Opens the media URL.
    private fun handleOpen(call: MethodCall, result: Result) {
        val url = call.argument<String>("url") ?: run {
            result.error("INVALID_ARG", "url is required", null)
            return
        }
        currentUrl = url
        exoPlayer?.let { player ->
            val mediaItem = MediaItem.fromUri(url)
            player.setMediaItem(mediaItem)
            player.prepare()
            player.playWhenReady = true
        }
        result.success(null)
    }

    /// 开始播放。
    /// Starts playback.
    private fun handlePlay(result: Result) {
        exoPlayer?.play()
        result.success(null)
    }

    /// 暂停播放。
    /// Pauses playback.
    private fun handlePause(result: Result) {
        exoPlayer?.pause()
        result.success(null)
    }

    /// 跳转到指定位置（毫秒）。
    /// Seeks to the specified position in milliseconds.
    private fun handleSeek(call: MethodCall, result: Result) {
        val position = call.argument<Number>("position")?.toLong() ?: 0L
        exoPlayer?.seekTo(position)
        result.success(null)
    }

    /// 设置音量（0.0 ~ 1.0）。
    /// Sets the volume (0.0 – 1.0).
    private fun handleSetVolume(call: MethodCall, result: Result) {
        val volume = call.argument<Double>("volume") ?: 1.0
        exoPlayer?.volume = volume.toFloat()
        result.success(null)
    }

    /// 设置播放速度。
    /// Sets the playback speed.
    private fun handleSetSpeed(call: MethodCall, result: Result) {
        val speed = call.argument<Double>("speed") ?: 1.0
        exoPlayer?.setPlaybackSpeed(speed.toFloat())
        result.success(null)
    }

    /// 释放播放器资源。
    /// Disposes the player resources.
    private fun handleDispose(result: Result) {
        releasePlayer()
        result.success(null)
    }

    private fun releasePlayer() {
        mainHandler.removeCallbacks(positionRunnable)
        exoPlayer?.removeListener(playerListener)
        exoPlayer?.release()
        exoPlayer = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
    }

    private fun sendEvent(event: String, value: Any?) {
        mainHandler.post {
            val data = HashMap<String, Any?>()
            data["event"] = event
            data["value"] = value
            eventSink?.success(data)
        }
    }

    /// ExoPlayer 事件监听器，将状态变更转发给 Dart EventChannel。
    /// ExoPlayer event listener forwarding state changes to the Dart EventChannel.
    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            sendEvent("playing", isPlaying)
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_BUFFERING -> sendEvent("buffering", true)
                Player.STATE_READY -> {
                    sendEvent("buffering", false)
                    exoPlayer?.let { player ->
                        sendEvent("duration", player.duration)
                    }
                }
                Player.STATE_ENDED -> sendEvent("completed", null)
                Player.STATE_IDLE -> { /* no-op */ }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            sendEvent("error", error.message ?: "Unknown playback error")
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            // 以显示方向像素数上报，兼容 pixelWidthHeightRatio 非 1 的轨道。
            // Report display-oriented pixel dimensions so non-1 pixel aspect
            // ratios (e.g. anamorphic tracks) are handled correctly.
            val rawW = videoSize.width
            val rawH = videoSize.height
            if (rawW <= 0 || rawH <= 0) return
            val par = if (videoSize.pixelWidthHeightRatio > 0f) videoSize.pixelWidthHeightRatio else 1f
            val displayW = (rawW * par).toInt().coerceAtLeast(1)
            val size = HashMap<String, Any>()
            size["width"] = displayW
            size["height"] = rawH
            sendEvent("videoSize", size)
        }
    }

    // region Snapshot / Covers

    /// 对当前播放位置抽取一帧，返回 PNG 字节。
    /// Snapshot the current playback position and return PNG bytes.
    private fun handleTakeSnapshot(result: Result) {
        val url = currentUrl
        val positionUs = (exoPlayer?.currentPosition ?: 0L) * 1000L
        val appContext = flutterPluginBinding?.applicationContext
        if (url == null) {
            result.error("NO_MEDIA", "No media loaded", null)
            return
        }
        workerExecutor.execute {
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext)
                val bmp = retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST)
                if (bmp == null) {
                    mainHandler.post {
                        result.error("NO_FRAME", "Failed to extract frame", null)
                    }
                    return@execute
                }
                val baos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                bmp.recycle()
                val bytes = baos.toByteArray()
                mainHandler.post { result.success(bytes) }
            } catch (t: Throwable) {
                mainHandler.post {
                    result.error("SNAPSHOT_FAIL", t.message ?: "snapshot failed", null)
                }
            } finally {
                try { retriever.release() } catch (_: Throwable) {}
            }
        }
    }

    /// 抽取视频候选封面帧列表。
    /// Extract cover candidate frames from a media URL.
    private fun handleExtractCovers(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        val count = call.argument<Int>("count") ?: 5
        val candidates = call.argument<Int>("candidates") ?: (count * 3)
        val minBrightness = call.argument<Double>("minBrightness") ?: 0.08
        val outputDir = call.argument<String>("outputDir") ?: ""
        val appContext = flutterPluginBinding?.applicationContext
        if (url == null) {
            result.success(emptyList<Any>())
            return
        }
        workerExecutor.execute {
            val frames = ArrayList<Map<String, Any>>()
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext)
                val durMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                if (durMs <= 0) {
                    mainHandler.post { result.success(emptyList<Any>()) }
                    return@execute
                }
                val dir = File(outputDir.ifEmpty { appContext?.cacheDir?.absolutePath ?: "/tmp" })
                if (!dir.exists()) dir.mkdirs()

                val lower = (durMs * 0.05).toLong()
                val upper = (durMs * 0.95).toLong()
                val span = (upper - lower).coerceAtLeast(1L)
                val n = maxOf(candidates, count)
                for (i in 0 until n) {
                    val t = lower + (span * (i + 0.5) / n).toLong()
                    val bmp = retriever.getFrameAtTime(t * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                        ?: continue
                    val brightness = averageBrightness(bmp)
                    if (brightness < minBrightness) {
                        bmp.recycle()
                        continue
                    }
                    val outFile = File(dir, "cover-${abs(url.hashCode())}-$t.png")
                    try {
                        FileOutputStream(outFile).use { fos ->
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
                        }
                        frames.add(
                            mapOf(
                                "path" to outFile.absolutePath,
                                "positionMs" to t,
                                "brightness" to brightness
                            )
                        )
                    } catch (_: Throwable) {
                        // skip
                    } finally {
                        bmp.recycle()
                    }
                }
                frames.sortByDescending { (it["brightness"] as? Double) ?: 0.0 }
                val trimmed = frames.take(count)
                mainHandler.post { result.success(trimmed) }
            } catch (t: Throwable) {
                mainHandler.post { result.success(emptyList<Any>()) }
            } finally {
                try { retriever.release() } catch (_: Throwable) {}
            }
        }
    }

    private fun setDataSourceForUrl(
        retriever: MediaMetadataRetriever,
        url: String,
        appContext: android.content.Context?
    ) {
        val uri = Uri.parse(url)
        when (uri.scheme?.lowercase()) {
            "file" -> retriever.setDataSource(uri.path ?: url)
            "http", "https" -> retriever.setDataSource(url, HashMap())
            "content" -> {
                if (appContext != null) retriever.setDataSource(appContext, uri)
                else retriever.setDataSource(url, HashMap())
            }
            else -> retriever.setDataSource(url)
        }
    }

    private fun averageBrightness(bmp: Bitmap): Double {
        val w = 64
        val h = 64
        val scaled = Bitmap.createScaledBitmap(bmp, w, h, false)
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        var total = 0.0
        for (p in pixels) {
            val r = ((p shr 16) and 0xff) / 255.0
            val g = ((p shr 8) and 0xff) / 255.0
            val b = (p and 0xff) / 255.0
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        if (scaled != bmp) scaled.recycle()
        return total / pixels.size
    }

    // endregion
}
