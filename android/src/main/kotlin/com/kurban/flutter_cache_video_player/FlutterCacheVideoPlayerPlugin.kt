package com.kurban.flutter_cache_video_player

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

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
    }
}
