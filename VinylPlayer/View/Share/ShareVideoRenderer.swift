import SwiftUI
import AVFoundation

/// Renders an animated MP4 of the lyrics player card with spinning vinyl and scrolling lyrics.
final class ShareVideoRenderer {

    struct Config {
        let fps: Int = 30
        let cardWidth: CGFloat = 360
        let cardHeight: CGFloat
        let scale: CGFloat = 2.0  // render at 2x for balance of quality and speed
        let rpmAnglePerFrame: Double  // degrees per frame for vinyl rotation
        let clipDuration: TimeInterval  // total video duration in seconds

        init(style: ShareCardStyle = .lyricsPlayer, clipDuration: TimeInterval = 12.0) {
            self.cardHeight = style.cardHeight
            self.clipDuration = clipDuration
            self.rpmAnglePerFrame = (360.0 * 10.0 / 60.0) / Double(fps)
        }
    }

    enum RenderError: Error, LocalizedError {
        case noSyncedLyrics
        case writerSetupFailed
        case renderFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noSyncedLyrics: return "No synced lyrics available"
            case .writerSetupFailed: return "Failed to set up video writer"
            case .renderFailed: return "Failed to render video frames"
            case .cancelled: return "Rendering was cancelled"
            }
        }
    }

    /// Render an MP4 video of the lyrics card.
    /// - Parameters:
    ///   - data: Share card data including synced lyricLines
    ///   - customization: Current customization settings
    ///   - progress: Callback for progress updates (0.0 - 1.0)
    /// - Returns: URL to the rendered MP4 file in a temp directory
    @MainActor
    static func render(
        data: ShareCardData,
        style: ShareCardStyle = .lyricsPlayer,
        customization: ShareCustomization,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let lyricLines = data.lyricLines, lyricLines.count > 1,
              lyricLines.contains(where: { $0.startTime > 0 }) else {
            throw RenderError.noSyncedLyrics
        }

        let config = Config(style: style)
        let currentIdx = data.currentLyricIndex ?? 0

        // Determine clip time range: center around current lyric
        let currentTime = lyricLines[min(currentIdx, lyricLines.count - 1)].startTime
        let halfDuration = config.clipDuration / 2.0
        let clipStart = max(0, currentTime - halfDuration)
        let clipEnd = clipStart + config.clipDuration

        // Output file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vinyl_share_\(UUID().uuidString).mp4")

        // Video dimensions (integer pixels)
        let pixelWidth = Int(config.cardWidth * config.scale)
        let pixelHeight = Int(config.cardHeight * config.scale)

        // Set up AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,  // 8 Mbps
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw RenderError.writerSetupFailed
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw RenderError.writerSetupFailed
        }
        writer.startSession(atSourceTime: .zero)

        // Render frames
        let totalFrames = Int(config.clipDuration * Double(config.fps))
        // Use high-precision timescale (600 is common in video, divisible by 30)
        let timescale: CMTimeScale = 600
        let frameDurationValue = Int64(timescale) / Int64(config.fps)  // 20 per frame at 30fps

        for frameIndex in 0..<totalFrames {
            if Task.isCancelled {
                writer.cancelWriting()
                throw RenderError.cancelled
            }

            let frameTime = clipStart + Double(frameIndex) / Double(config.fps)
            let rotationAngle = Double(frameIndex) * config.rpmAnglePerFrame
            let lyricIdx = lyricIndexAt(time: frameTime, lyricLines: lyricLines)

            // Calculate smooth fractional lyric progress for transitions
            let lyricProgress: Double = {
                let lineStartTime = lyricLines[lyricIdx].startTime
                let timeSinceStart = frameTime - lineStartTime
                let transitionDuration = 0.3 // seconds for smooth transition
                if timeSinceStart < transitionDuration && lyricIdx > 0 {
                    let t = min(1.0, timeSinceStart / transitionDuration)
                    let eased = t * t * (3.0 - 2.0 * t) // smoothstep
                    return Double(lyricIdx - 1) + eased
                }
                return Double(lyricIdx)
            }()

            // Render SwiftUI view to UIImage
            let cardView = ShareCardView(
                data: data,
                style: style,
                customization: customization,
                vinylRotationAngle: rotationAngle,
                overrideLyricIndex: lyricIdx,
                overrideLyricProgress: lyricProgress
            )
            .frame(width: config.cardWidth, height: config.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            let renderer = ImageRenderer(content: cardView)
            renderer.scale = config.scale

            guard let uiImage = renderer.uiImage,
                  let cgImage = uiImage.cgImage else {
                throw RenderError.renderFailed
            }

            // Wait for writer input to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }

            // Create pixel buffer from CGImage
            guard let pixelBuffer = pixelBufferFromCGImage(cgImage, width: pixelWidth, height: pixelHeight) else {
                throw RenderError.renderFailed
            }

            let presentationTime = CMTime(value: Int64(frameIndex) * frameDurationValue, timescale: timescale)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            // Report progress
            progress(Double(frameIndex + 1) / Double(totalFrames))

            // Yield to prevent blocking the main thread too long
            if frameIndex % 5 == 0 {
                await Task.yield()
            }
        }

        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? RenderError.renderFailed
        }

        return outputURL
    }

    // MARK: - Helpers

    /// Find the lyric line index at a given time
    private static func lyricIndexAt(time: TimeInterval, lyricLines: [LyricLine]) -> Int {
        var idx = 0
        for (i, line) in lyricLines.enumerated() {
            if line.startTime <= time { idx = i }
            else { break }
        }
        return idx
    }

    /// Convert CGImage to CVPixelBuffer
    private static func pixelBufferFromCGImage(_ image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
