import AVFoundation
import Cocoa
import FlutterMacOS

/// macOS 插件主类，基于 AVPlayer 实现原生视频播放，通过 FlutterTexture 渲染。
/// macOS plugin main class implementing native video playback with AVPlayer, rendered via FlutterTexture.
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
            binaryMessenger: registrar.messenger
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "flutter_cache_video_player/player/events",
            binaryMessenger: registrar.messenger
        )
        instance.eventChannel = eventChannel
        instance.videoPlayer = NativeVideoPlayer(
            textureRegistry: registrar.textures
        )
        eventChannel.setStreamHandler(instance.videoPlayer)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let player = videoPlayer else {
            result(
                FlutterError(
                    code: "NO_PLAYER",
                    message: "Player not initialized",
                    details: nil
                )
            )
            return
        }

        switch call.method {
        case "create":
            let textureId = player.create()
            result(textureId)
        case "open":
            guard let args = call.arguments as? [String: Any],
                let url = args["url"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "url is required",
                        details: nil
                    )
                )
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
                let position = args["position"] as? Int
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "position is required",
                        details: nil
                    )
                )
                return
            }
            player.seek(positionMs: position)
            result(nil)
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                let volume = args["volume"] as? Double
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "volume is required",
                        details: nil
                    )
                )
                return
            }
            player.setVolume(volume: Float(volume))
            result(nil)
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                let speed = args["speed"] as? Double
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "speed is required",
                        details: nil
                    )
                )
                return
            }
            player.setSpeed(speed: Float(speed))
            result(nil)
        case "dispose":
            player.dispose()
            result(nil)
        case "takeSnapshot":
            player.takeSnapshot(result: result)
        case "extractCovers":
            guard let args = call.arguments as? [String: Any],
                let url = args["url"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "url is required",
                        details: nil
                    )
                )
                return
            }
            let count = (args["count"] as? Int) ?? 5
            let candidates = (args["candidates"] as? Int) ?? (count * 3)
            let minBrightness = (args["minBrightness"] as? Double) ?? 0.08
            let outputDir =
                (args["outputDir"] as? String) ?? NSTemporaryDirectory()
            NativeVideoPlayer.extractCovers(
                url: url,
                count: count,
                candidates: candidates,
                minBrightness: minBrightness,
                outputDir: outputDir,
                result: result
            )
        case "getPlatformVersion":
            result(
                "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// AVPlayer 封装（macOS），实现 FlutterTexture 协议，通过 CVPixelBuffer 向 Flutter 提供视频帧。
/// AVPlayer wrapper (macOS) implementing FlutterTexture protocol, providing video frames via CVPixelBuffer.
class NativeVideoPlayer: NSObject, FlutterTexture, FlutterStreamHandler {
    private let textureRegistry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var displayLink: CVDisplayLink?
    private var eventSink: FlutterEventSink?
    private var timeObserver: Any?
    private var latestPixelBuffer: CVPixelBuffer?
    private var statusObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var timer: Timer?
    private var currentUrl: String?
    /// 已发起的瞬时错误重试次数。超过 `maxTransientRetries` 后才把错误
    /// 真正抛给 Flutter 侧。
    /// Number of transient-failure retries already attempted. Beyond
    /// `maxTransientRetries` the error is finally surfaced to Flutter.
    private var transientRetryCount = 0
    private let maxTransientRetries = 4
    /// 调用方期望的播放状态。`open()` 重置；`play()`/`pause()` 更新；
    /// 用于在 `.failed` 静默重试后恢复同一播放意图。
    /// Tracks the caller-intended play state so the silent retry path can
    /// resume playback after recreating AVPlayer.
    private var wantsToPlay = false

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
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
        cleanupPlayer()
        currentUrl = url
        transientRetryCount = 0
        wantsToPlay = false
        openInternal(url: url)
    }

    private func openInternal(url: String) {
        guard let mediaUrl = URL(string: url) else {
            sendEvent(event: "error", value: "Invalid URL: \(url)")
            return
        }

        // 显式传入 AVURLAsset 选项，强化对本地代理 HTTP 流的兼容性，避免
        // AVPlayer 在首字节抵达前过早判定为 Cannot Open（OSStatus -12848）。
        // Pass explicit AVURLAsset options to harden compatibility with the
        // local caching proxy, so AVPlayer doesn't bail with OSStatus -12848
        // ("Cannot Open") before the first bytes arrive.
        let assetOptions: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
            "AVURLAssetHTTPHeaderFieldsKey": [String: String](),
        ]
        let asset = AVURLAsset(url: mediaUrl, options: assetOptions)
        playerItem = AVPlayerItem(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(
            pixelBufferAttributes: outputSettings
        )
        playerItem!.add(videoOutput!)

        statusObservation = playerItem!.observe(\.status, options: [.new]) {
            [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                let durationMs = Int(CMTimeGetSeconds(item.duration) * 1000)
                self.sendEvent(event: "duration", value: durationMs)
                self.sendEvent(event: "buffering", value: false)
            case .failed:
                let nsError = item.error as NSError?
                let underlying =
                    nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
                let code = underlying?.code ?? nsError?.code ?? 0
                let domain = underlying?.domain ?? nsError?.domain ?? ""
                if self.shouldRetryTransientFailure(code: code, domain: domain) {
                    self.transientRetryCount += 1
                    if let url = self.currentUrl {
                        // 退避延迟：让本地代理累积更多字节后再重开 AVPlayer。
                        // 第 1 次 200ms、第 2 次 600ms、第 3 次 1200ms…
                        // Backoff: give the local proxy time to accumulate
                        // bytes before AVPlayer reopens. 200 / 600 / 1200 ms.
                        let delayMs = min(200 * (1 << (self.transientRetryCount - 1)), 1500)
                        self.cleanupPlayerKeepingTexture()
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + .milliseconds(delayMs)
                        ) { [weak self] in
                            guard let self = self,
                                self.currentUrl == url
                            else { return }
                            self.openInternal(url: url)
                            // 恢复调用方原本的播放意图（Dart 在 .failed 之前
                            // 已经调用过 play()，但那一次作用在已被废弃的旧
                            // AVPlayer 上）。
                            // Restore caller-intended playback: Dart's earlier
                            // play() call landed on the now-discarded AVPlayer
                            // instance, so re-issue it on the new one.
                            if self.wantsToPlay {
                                self.player?.play()
                                self.sendEvent(event: "playing", value: true)
                            }
                        }
                        return
                    }
                }
                let desc =
                    nsError?.localizedDescription ?? "Unknown error"
                let detail = underlying?.localizedDescription ?? ""
                let msg = detail.isEmpty ? desc : "\(desc) (\(detail))"
                self.sendEvent(event: "error", value: msg)
            default:
                break
            }
        }

        // 上报视频原始尺寸（已包含显示方向修正），供 Flutter 侧计算宽高比。
        // Report display-oriented video size so portrait videos aren't
        // stretched to the default aspect ratio on the Flutter side.
        let reportSize: (CGSize) -> Void = { [weak self] size in
            guard size.width > 0, size.height > 0 else { return }
            self?.sendEvent(
                event: "videoSize",
                value: [
                    "width": Int(size.width),
                    "height": Int(size.height),
                ]
            )
        }
        if playerItem!.presentationSize.width > 0,
            playerItem!.presentationSize.height > 0
        {
            reportSize(playerItem!.presentationSize)
        }
        presentationSizeObservation = playerItem!.observe(
            \.presentationSize,
            options: [.new, .initial]
        ) { item, _ in
            reportSize(item.presentationSize)
        }

        player = AVPlayer(playerItem: playerItem)

        let interval = CMTime(value: 1, timescale: 5)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let ms = Int(CMTimeGetSeconds(time) * 1000)
            self?.sendEvent(event: "position", value: ms)
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            // 先把播放状态翻回 false，确保下一次 replay 调用 play() 时
            // playingSignal 能产生真实的 false→true 变化，触发 Flutter
            // 侧 effect 把 playState 从 stopped 切回 playing（修复重试
            // 按钮停留在重播图标的问题）。
            // Flip playing back to false before reporting completion so the
            // next play() produces a real false→true transition on the
            // playing signal. Without this, replay leaves playState stuck
            // at "stopped" because the signal value never changes.
            self?.wantsToPlay = false
            self?.sendEvent(event: "playing", value: false)
            self?.sendEvent(event: "completed", value: nil)
        }

        // Use Timer for frame updates on macOS (simpler than CVDisplayLink)
        startFrameTimer()

        sendEvent(event: "playing", value: false)
        sendEvent(event: "buffering", value: true)
    }

    /// 开始播放。 / Starts playback.
    func play() {
        wantsToPlay = true
        player?.play()
        sendEvent(event: "playing", value: true)
    }

    /// 暂停播放。 / Pauses playback.
    func pause() {
        wantsToPlay = false
        player?.pause()
        sendEvent(event: "playing", value: false)
    }

    /// 跳转到指定位置（毫秒）。 / Seeks to the specified position in milliseconds.
    func seek(positionMs: Int) {
        let time = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 设置音量（0.0 ~ 1.0）。 / Sets the volume (0.0 – 1.0).
    func setVolume(volume: Float) {
        player?.volume = volume
    }

    /// 设置播放速度。 / Sets the playback speed.
    func setSpeed(speed: Float) {
        player?.rate = speed
    }
    /// 释放播放器资源。
    /// Disposes the player resources.
    func dispose() {
        cleanupPlayer()
        currentUrl = nil
        transientRetryCount = 0
        wantsToPlay = false
        if textureId != -1 {
            textureRegistry.unregisterTexture(textureId)
            textureId = -1
        }
    }

    // MARK: - Private

    private func cleanupPlayer() {
        cleanupPlayerKeepingTexture()
    }

    /// 与 cleanupPlayer 等价，但保留纹理注册以便重试时复用。
    /// Same as cleanupPlayer; texture registration is preserved either way
    /// (only `dispose()` unregisters), but kept as a separate name to make
    /// retry-flow intent explicit at call sites.
    private func cleanupPlayerKeepingTexture() {
        stopFrameTimer()

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
        presentationSizeObservation?.invalidate()
        presentationSizeObservation = nil

        player?.pause()
        player = nil
        playerItem = nil
        videoOutput = nil
        latestPixelBuffer = nil
    }

    private func startFrameTimer() {
        stopFrameTimer()
        // ~60 FPS timer for pulling pixel buffers
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            self?.onFrame()
        }
    }

    private func stopFrameTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onFrame() {
        guard let output = videoOutput else { return }
        let currentTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: currentTime) {
            latestPixelBuffer = output.copyPixelBuffer(
                forItemTime: currentTime,
                itemTimeForDisplay: nil
            )
            textureRegistry.textureFrameAvailable(textureId)
        }
    }

    private func sendEvent(event: String, value: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": event, "value": value as Any])
        }
    }

    /// 判断 AVPlayer 失败是否属于可重试的"首字节竞态"类错误。
    /// 实战中 -12848 / NSURLError 重置等错误的 code 包装层级不固定
    /// （outer / underlying / userInfo 内嵌套），故采用"重试次数上限 +
    /// 退避延迟"的统一策略，由 `transientRetryCount` 控制不会无限循环。
    ///
    /// Whether an AVPlayer failure should trigger the silent retry path.
    /// In practice -12848 and NSURLError resets nest their code in
    /// inconsistent layers (outer vs. underlying vs. nested userInfo), so
    /// instead of brittle code matching we cap retries via
    /// `transientRetryCount` and rely on backoff to let the proxy catch up.
    private func shouldRetryTransientFailure(code: Int, domain: String) -> Bool {
        return transientRetryCount < maxTransientRetries
    }

    // MARK: - Snapshot / Covers

    /// 对当前画面截图并返回 PNG Data（通过 result 回调）。
    /// Snapshot the current frame and return PNG Data via the result callback.
    func takeSnapshot(result: @escaping FlutterResult) {
        guard let buffer = latestPixelBuffer else {
            result(
                FlutterError(
                    code: "NO_FRAME",
                    message: "No frame available",
                    details: nil
                )
            )
            return
        }
        if let data = Self.pngData(from: buffer) {
            result(FlutterStandardTypedData(bytes: data))
        } else {
            result(
                FlutterError(
                    code: "ENCODE_FAIL",
                    message: "Failed to encode PNG",
                    details: nil
                )
            )
        }
    }

    /// 从视频 URL 中抽取若干非黑的候选封面帧。
    /// Extract non-black cover candidates from a media URL.
    static func extractCovers(
        url: String,
        count: Int,
        candidates: Int,
        minBrightness: Double,
        outputDir: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let mediaURL = URL(string: url) else {
                DispatchQueue.main.async { result([]) }
                return
            }
            let asset = AVURLAsset(url: mediaURL)
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                DispatchQueue.main.async { result([]) }
                return
            }

            let fm = FileManager.default
            try? fm.createDirectory(
                atPath: outputDir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            )
            generator.requestedTimeToleranceAfter = CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            )
            generator.maximumSize = CGSize(width: 1280, height: 720)

            let lower = durationSeconds * 0.05
            let upper = durationSeconds * 0.95
            let span = max(upper - lower, 0.1)
            let n = max(candidates, count)
            var times: [NSValue] = []
            for i in 0..<n {
                let t = lower + span * (Double(i) + 0.5) / Double(n)
                times.append(
                    NSValue(time: CMTime(seconds: t, preferredTimescale: 600))
                )
            }

            var frames: [[String: Any]] = []
            let group = DispatchGroup()
            let sync = DispatchQueue(label: "flutter_cache_video_player.covers")
            for _ in times {
                group.enter()
            }

            generator.generateCGImagesAsynchronously(forTimes: times) {
                requestedTime,
                cgImage,
                _,
                status,
                _ in
                defer { group.leave() }
                guard status == .succeeded, let cg = cgImage else { return }
                let brightness = Self.averageBrightness(cgImage: cg)
                if brightness < minBrightness { return }
                let ms = Int(CMTimeGetSeconds(requestedTime) * 1000)
                let name = "cover-\(abs(url.hashValue))-\(ms).png"
                let outPath = (outputDir as NSString).appendingPathComponent(
                    name
                )
                if Self.writePNG(cgImage: cg, to: outPath) {
                    sync.sync {
                        frames.append([
                            "path": outPath,
                            "positionMs": ms,
                            "brightness": brightness,
                        ])
                    }
                }
            }

            group.notify(queue: .main) {
                let sorted = frames.sorted { a, b -> Bool in
                    let ab = (a["brightness"] as? Double) ?? 0
                    let bb = (b["brightness"] as? Double) ?? 0
                    return ab > bb
                }
                let trimmed = Array(sorted.prefix(count))
                result(trimmed)
            }
        }
    }

    // MARK: - Image helpers

    private static func pngData(from buffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    private static func writePNG(cgImage: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func averageBrightness(cgImage: CGImage) -> Double {
        let w = 64
        let h = 64
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let ctx = CGContext(
                data: &data,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else { return 0 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total: Double = 0
        let pixelCount = w * h
        for i in 0..<pixelCount {
            let r = Double(data[i * 4]) / 255.0
            let g = Double(data[i * 4 + 1]) / 255.0
            let b = Double(data[i * 4 + 2]) / 255.0
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return total / Double(pixelCount)
    }
}
