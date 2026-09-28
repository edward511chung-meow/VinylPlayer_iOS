import SwiftUI
import UIKit

// MARK: - Configuration

/// 灰飛煙滅效果配置
struct DisintegrationConfig {
    /// 粒子層數（越少 = 顆粒越大，越多 = 越細緻）
    var particleLayers: Int
    /// 動畫總時長（秒）
    var duration: Double
    /// 飄散距離（X 軸）
    var spreadX: Double
    /// 飄散距離（Y 軸）
    var spreadY: Double
    /// 截圖 scale（通常 2.0 或 3.0）
    var renderScale: CGFloat

    init(
        particleLayers: Int = 20,
        duration: Double = 1.4,
        spreadX: Double = 80,
        spreadY: Double = 40,
        renderScale: CGFloat = 3.0
    ) {
        self.particleLayers = particleLayers
        self.duration = duration
        self.spreadX = spreadX
        self.spreadY = spreadY
        self.renderScale = renderScale
    }

    /// 預設配置
    static let `default` = DisintegrationConfig()

    /// 細緻灰塵
    static let fine = DisintegrationConfig(particleLayers: 48, duration: 1.2, spreadX: 60, spreadY: 30)

    /// 大顆粒快速
    static let chunky = DisintegrationConfig(particleLayers: 12, duration: 1.0, spreadX: 100, spreadY: 50)
}

// MARK: - Public API

extension View {
    /// 灰飛煙滅效果
    /// - Parameters:
    ///   - isActive: 設為 `true` 觸發效果
    ///   - config: 效果配置（預設 `.default`）
    ///   - onComplete: 效果完成後嘅 callback
    func disintegrate(
        isActive: Binding<Bool>,
        config: DisintegrationConfig = .default,
        onComplete: (() -> Void)? = nil
    ) -> some View {
        DisintegrationContainer(
            isActive: isActive,
            config: config,
            onComplete: onComplete
        ) {
            self
        }
    }

    /// 灰飛煙滅效果（便捷版）
    func disintegrate(
        isActive: Binding<Bool>,
        particleLayers: Int = 20,
        duration: Double = 1.4,
        onComplete: (() -> Void)? = nil
    ) -> some View {
        DisintegrationContainer(
            isActive: isActive,
            config: DisintegrationConfig(particleLayers: particleLayers, duration: duration),
            onComplete: onComplete
        ) {
            self
        }
    }
}

// MARK: - Container View

struct DisintegrationContainer<Content: View>: View {
    @Binding var isActive: Bool
    let config: DisintegrationConfig
    let onComplete: (() -> Void)?
    @ViewBuilder let content: Content

    // Capture environment so ImageRenderer can inherit it
    @EnvironmentObject private var styleManager: StyleManager
    @Environment(\.self) private var environment

    @State private var snapshot: UIImage?
    @State private var isAnimating = false
    @State private var contentSize: CGSize = .zero

    var body: some View {
        ZStack {
            content
                .opacity(isAnimating ? 0 : 1)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { contentSize = geo.size }
                            .onChange(of: geo.size) { _, s in contentSize = s }
                    }
                )

            if isAnimating, let img = snapshot {
                DustAnimationView(image: img, size: contentSize, config: config) {
                    onComplete?()
                    isAnimating = false
                    isActive = false
                    snapshot = nil
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !isAnimating {
                takeSnapshot()
            }
        }
    }

    private func takeSnapshot() {
        let renderer = ImageRenderer(
            content: content
                .frame(width: contentSize.width, height: contentSize.height)
                .environmentObject(styleManager)
                .environment(\.self, environment)
        )
        renderer.scale = config.renderScale
        if let image = renderer.uiImage {
            snapshot = image
            isAnimating = true
        } else {
            isActive = false
            onComplete?()
        }
    }
}

// MARK: - Dust Animation UIViewRepresentable

struct DustAnimationView: UIViewRepresentable {
    let image: UIImage
    let size: CGSize
    let config: DisintegrationConfig
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> DustCanvasView {
        let view = DustCanvasView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: DustCanvasView, context: Context) {
        guard !context.coordinator.started else { return }
        context.coordinator.started = true
        uiView.runDustEffect(
            image: image,
            displaySize: size,
            config: config,
            onComplete: onComplete
        )
    }

    class Coordinator { var started = false }
}

// MARK: - Core Animation Engine

final class DustCanvasView: UIView, CAAnimationDelegate {

    private var onComplete: (() -> Void)?
    private var pendingLayers = 0

    func runDustEffect(
        image: UIImage,
        displaySize: CGSize,
        config: DisintegrationConfig,
        onComplete: @escaping () -> Void
    ) {
        self.onComplete = onComplete

        guard displaySize.width > 0 && displaySize.height > 0 else {
            onComplete()
            return
        }

        let rect = CGRect(origin: .zero, size: displaySize)
        let dustImages = DustPixelSplitter.split(image: image, into: config.particleLayers)
        pendingLayers = dustImages.count

        guard pendingLayers > 0 else {
            onComplete()
            return
        }

        let total = Double(dustImages.count)
        let totalDuration = config.duration
        // 每層動畫時長 = 總時長嘅 40%，stagger 佔 60%
        // 確保最後一層喺 totalDuration 時完成
        let staggerSpan = totalDuration * 0.6
        let layerDuration = totalDuration * 0.4

        for (i, dustImage) in dustImages.enumerated() {
            let dustLayer = CALayer()
            dustLayer.frame = rect
            dustLayer.contents = dustImage.cgImage
            dustLayer.contentsScale = image.scale
            dustLayer.contentsGravity = .resizeAspectFill
            layer.addSublayer(dustLayer)

            let cx = Double(rect.midX)
            let cy = Double(rect.midY)

            let r1 = Double.pi / 12.0 * Double.random(in: -0.5..<0.5)
            let r2 = Double.pi / 12.0 * Double.random(in: -0.5..<0.5)
            let angle = Double.pi * 2.0 * Double.random(in: -0.5..<0.5)
            let tx = config.spreadX * cos(angle)
            let ty = config.spreadY * sin(angle)
            let ex = tx * cos(r1) - ty * sin(r1)
            let ey = ty * cos(r1) + tx * sin(r1)

            let start = CGPoint(x: cx, y: cy)
            let end = CGPoint(x: cx + ex, y: cy + ey)
            let ctrl = CGPoint(x: cx + tx, y: cy + ty)

            let path = UIBezierPath()
            path.move(to: start)
            path.addQuadCurve(to: end, controlPoint: ctrl)

            let moveAnim = CAKeyframeAnimation(keyPath: "position")
            moveAnim.path = path.cgPath
            moveAnim.calculationMode = .paced

            let rotateAnim = CABasicAnimation(keyPath: "transform.rotation")
            rotateAnim.toValue = r1 + r2

            let fadeAnim = CABasicAnimation(keyPath: "opacity")
            fadeAnim.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [moveAnim, rotateAnim, fadeAnim]
            group.duration = layerDuration
            group.beginTime = CACurrentMediaTime() + staggerSpan * Double(i) / total
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards
            group.delegate = self
            dustLayer.add(group, forKey: "dust_\(i)")
        }
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        pendingLayers -= 1
        if pendingLayers <= 0 {
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            onComplete?()
            onComplete = nil
        }
    }
}

// MARK: - Pixel Splitter

enum DustPixelSplitter {

    static func split(image: UIImage, into count: Int) -> [UIImage] {
        guard let cgImage = image.cgImage else { return [] }

        let w = cgImage.width, h = cgImage.height
        let pixelCount = w * h
        let bpr = 4 * w
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: space, bitmapInfo: info),
              let buf = ctx.data else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let src = buf.bindMemory(to: UInt32.self, capacity: pixelCount)

        var layers = Array(repeating: [UInt32](repeating: 0, count: pixelCount), count: count)

        for col in 0..<w {
            let ratio = Double(col) / Double(w)
            for row in 0..<h {
                let off = row * w + col
                let px = src[off]
                for _ in 0..<2 {
                    let t = Double.random(in: 0..<1) + 2.0 * ratio
                    let idx = min(Int(floor(Double(count) * t / 3.0)), count - 1)
                    layers[idx][off] = px
                }
            }
        }

        var result = [UIImage]()
        result.reserveCapacity(count)
        for var layer in layers {
            let img: CGImage? = layer.withUnsafeMutableBytes { ptr in
                guard let c = CGContext(data: ptr.baseAddress, width: w, height: h,
                                        bitsPerComponent: 8, bytesPerRow: bpr,
                                        space: space, bitmapInfo: info)
                else { return nil }
                return c.makeImage()
            }
            if let img {
                result.append(UIImage(cgImage: img, scale: image.scale, orientation: image.imageOrientation))
            }
        }
        return result
    }
}
