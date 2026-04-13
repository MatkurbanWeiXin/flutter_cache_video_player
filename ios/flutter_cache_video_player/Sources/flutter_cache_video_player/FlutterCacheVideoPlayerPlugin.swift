import Flutter
import UIKit
import AVFoundation

/// iOS 插件主类，基于 AVPlayer 实现原生视频播放，通过 FlutterTexture 渲染。
/// iOS plugin main class implementing native video playback with AVPlayer, rendered via FlutterTexture.
public class FlutterCacheVideoPlayerPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var registrar: FlutterPluginRegistrar?
    private var videoPlayer: NativeVideoPlayer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterCacheVideoPlayerPlugin()
        instance.registrar = registrar

        let methodChannel = FlutterMethodChannel(
            name: "flutter_cache_video_player/player",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "flutter_cache_video_player/player/events",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = eventChannel
        instance.videoPlayer = NativeVideoPlayer(textureRegistry: registrar.textures())
        eventChannel.setStreamHandler(instance.videoPlayer)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let player = videoPlayer else {
            result(FlutterError(code: "NO_PLAYER", message: "Player not initialized", details: nil))
            return
        }

        switch call.method {
        case "create":
            let textureId = player.create()
            result(textureId)
        case "open":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "url is required", details: nil))
                return
            }
            player.open(url: url)
            result(nil)
        case "play":
            player.play()
            result(nil)
        case "pause":
            player.pause()
            result(nil)
        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Int else {
                result(FlutterError(code: "INVALID_ARG", message: "position is required", details: nil))
                return
            }
            player.seek(positionMs: position)
            result(nil)
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARG", message: "volume is required", details: nil))
                return
            }
            player.setVolume(volume: Float(volume))
            result(nil)
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARG", message: "speed is required", details: nil))
                return
            }
            player.setSpeed(speed: Float(speed))
            result(nil)
        case "dispose":
            player.dispose()
            result(nil)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// AVPlayer 封装，实现 FlutterTexture 协议，通过 CVPixelBuffer 向 Flutter 提供视频帧。
/// AVPlayer wrapper implementing FlutterTexture protocol, providing video frames via CVPixelBuffer.
class NativeVideoPlayer: NSObject, FlutterTexture, FlutterStreamHandler {
    private let textureRegistry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var eventSink: FlutterEventSink?
    private var timeObserver: Any?
    private var latestPixelBuffer: CVPixelBuffer?
    private var statusObservation: NSKeyValueObservation?
    private var didPlayToEndObserver: NSObjectProtocol?

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - FlutterTexture

    /// 返回最新的 CVPixelBuffer 供 Flutter 渲染。
    /// Returns the latest CVPixelBuffer for Flutter rendering.
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }

    // MARK: - Player Control

    /// 创建播放器并注册纹理，返回纹理 ID。
    /// Creates the player and registers a texture, returns the texture ID.
    func create() -> Int64 {
        textureId = textureRegistry.register(self)
        return textureId
    }

    /// 打开媒体 URL 进行播放。
    /// Opens the media URL for playback.
    func open(url: String) {
        // Clean up previous
        cleanupPlayer()

        guard let mediaUrl = URL(string: url) else {
            sendEvent(event: "error", value: "Invalid URL: \(url)")
            return
        }

        let asset = AVURLAsset(url: mediaUrl)
        playerItem = AVPlayerItem(asset: asset)

        // Setup video output for texture rendering
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem!.add(videoOutput!)

        // Observe status
        statusObservation = playerItem!.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                let durationMs = Int(CMTimeGetSeconds(item.duration) * 1000)
                self.sendEvent(event: "duration", value: durationMs)
                self.sendEvent(event: "buffering", value: false)
            case .failed:
                self.sendEvent(event: "error", value: item.error?.localizedDescription ?? "Unknown error")
            default:
                break
            }
        }

        player = AVPlayer(playerItem: playerItem)
        player?.play()

        // Position observer (every 200ms)
        let interval = CMTime(value: 1, timescale: 5)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let ms = Int(CMTimeGetSeconds(time) * 1000)
            self?.sendEvent(event: "position", value: ms)
        }

        // Playback end observer
        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.sendEvent(event: "completed", value: nil)
        }

        // Start display link for texture updates
        startDisplayLink()

        sendEvent(event: "playing", value: true)
        sendEvent(event: "buffering", value: true)
    }

    /// 开始播放。
    /// Starts playback.
    func play() {
        player?.play()
        sendEvent(event: "playing", value: true)
    }

    /// 暂停播放。
    /// Pauses playback.
    func pause() {
        player?.pause()
        sendEvent(event: "playing", value: false)
    }

    /// 跳转到指定位置（毫秒）。
    /// Seeks to the specified position in milliseconds.
    func seek(positionMs: Int) {
        let time = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 设置音量（0.0 ~ 1.0）。
    /// Sets the volume (0.0 – 1.0).
    func setVolume(volume: Float) {
        player?.volume = volume
    }

    /// 设置播放速度。
    /// Sets the playback speed.
    func setSpeed(speed: Float) {
        player?.rate = speed
    }

    /// 释放播放器资源。
    /// Disposes the player resources.
    func dispose() {
        cleanupPlayer()
        if textureId != -1 {
            textureRegistry.unregisterTexture(textureId)
            textureId = -1
        }
    }

    // MARK: - Private

    private func cleanupPlayer() {
        stopDisplayLink()

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }

        statusObservation?.invalidate()
        statusObservation = nil

        player?.pause()
        player = nil
        playerItem = nil
        videoOutput = nil
        latestPixelBuffer = nil
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func onDisplayLink() {
        guard let output = videoOutput else { return }
        let currentTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: currentTime) {
            latestPixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil)
            textureRegistry.textureFrameAvailable(textureId)
        }
    }

    private func sendEvent(event: String, value: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": event, "value": value as Any])
        }
    }
}
