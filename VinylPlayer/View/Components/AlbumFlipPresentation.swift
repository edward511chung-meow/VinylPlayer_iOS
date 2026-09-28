import SwiftUI
import UIKit

/// Window-space source rectangles survive presentation in a separate modal host.
struct AlbumFlipFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func albumFlipSource(_ id: String) -> some View {
        modifier(AlbumFlipSourceModifier(id: id))
    }
}

private struct AlbumFlipHiddenSourceKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var hiddenAlbumFlipSource: String? {
        get { self[AlbumFlipHiddenSourceKey.self] }
        set { self[AlbumFlipHiddenSourceKey.self] = newValue }
    }
}
private struct AlbumFlipSourceModifier: ViewModifier {
    let id: String
    @Environment(\.hiddenAlbumFlipSource) private var hiddenID
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: AlbumFlipFrames.self,
                                   value: [id: geometry.frame(in: .global)])
        }).opacity(hiddenID == id ? 0 : 1)
    }
}

private struct AlbumFlipCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var closeAlbumFlip: (() -> Void)? {
        get { self[AlbumFlipCloseKey.self] }
        set { self[AlbumFlipCloseKey.self] = newValue }
    }
}

/// Suppress only the system modal slide; the card owns its animation.
func updateAlbumFlipPresentation(_ update: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, update)
}

struct AlbumFlipPresentation<Details: View>: View {
    let album: Album
    let sourceFrame: CGRect
    let dismiss: () -> Void
    var keepsSourceFrame = false
    var sourceScale: CGFloat = 1
    var showsReflection = false
    @ViewBuilder var details: () -> Details
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var progress: CGFloat = 0
    @State private var transitioning = true

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let source = sourceFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let topInset: CGFloat = verticalSizeClass == .compact ? 16 : 32
            let expandedWidth = min(source.width * sourceScale, max(1, geometry.size.width - 32))
            let expandedHeight = min(source.height * sourceScale, max(1, geometry.size.height - 32))
            let expandedSource = CGRect(x: source.midX - expandedWidth / 2,
                                        y: max(16, source.midY - expandedHeight / 2),
                                        width: expandedWidth, height: expandedHeight)
            let destination = keepsSourceFrame ? expandedSource : CGRect(x: 16, y: topInset,
                                     width: max(1, geometry.size.width - 32),
                                     height: max(1, geometry.size.height - topInset - 16))
            ZStack {
                Color.black.opacity(0.32 * progress).ignoresSafeArea()
                    .allowsHitTesting(false)
                if geometry.size.width > 32, geometry.size.height > 32,
                   sourceFrame.width > 0, sourceFrame.height > 0,
                   sourceFrame.origin.x.isFinite, sourceFrame.origin.y.isFinite {
                AlbumFlipSurface(progress: progress, source: source, destination: destination,
                                 reduceMotion: reduceMotion, showsReflection: showsReflection) {
                    AlbumCoverView(album: album, size: max(1, source.width))
                } back: {
                    details().environment(\.closeAlbumFlip, close)
                }
                .allowsHitTesting(!transitioning && progress == 1)
                }
            }
            .overlay {
                // Explicit outside-only hit region: covers safe areas and reflections,
                // but leaves the detail's buttons and scrolling untouched.
                GeometryReader { hitGeometry in
                    let hitOrigin = hitGeometry.frame(in: .global).origin
                    let card = destination.offsetBy(dx: origin.x - hitOrigin.x,
                                                    dy: origin.y - hitOrigin.y)
                    Color.clear
                        .contentShape(AlbumFlipOutsideRegion(card: card), eoFill: true)
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
            .accessibilityAction(.escape, close)
            .task {
                // A separate display pass establishes the source pose before the spring.
                try? await Task.sleep(for: .milliseconds(32))
                guard !Task.isCancelled else { return }
                animate(to: 1) { transitioning = false }
            }
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
    }

    private func animate(to value: CGFloat, completion: @escaping () -> Void) {
        var transaction = Transaction(animation: reduceMotion ? nil : .interpolatingSpring(duration: 0.45, bounce: 0.1))
        transaction.disablesAnimations = false
        withTransaction(transaction) {
            withAnimation(transaction.animation, completionCriteria: .removed) {
                progress = value
            } completion: { completion() }
        }
    }

    private func close() {
        guard !transitioning else { return }
        transitioning = true
        animate(to: 0) { updateAlbumFlipPresentation(dismiss) }
    }
}

/// Both faces and the frame share one interpolated progress; switch faces edge-on.
struct AlbumFlipSurface<Front: View, Back: View>: View, Animatable {
    var progress: CGFloat
    let source: CGRect
    let destination: CGRect
    let reduceMotion: Bool
    var showsReflection = false
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let p = min(1, max(0, progress))
        let width = max(1, source.width + (destination.width - source.width) * p)
        let height = max(1, source.height + (destination.height - source.height) * p)
        let angle = reduceMotion ? 0 : Double(p) * 180
        AlbumFlipHostingSurface(front: front(), back: back(), sourceSize: source.size,
                                destinationSize: destination.size, progress: p,
                                angle: angle, reduceMotion: reduceMotion, showsReflection: showsReflection)
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(showsReflection ? 0 : 0.16 * p), radius: 24 * p, y: 12 * p)
        .position(x: source.midX + (destination.midX - source.midX) * p,
                  y: source.midY + (destination.midY - source.midY) * p)
    }
}

/// Keep perspective out of SwiftUI's layout/safe-area graph. A face passes through
/// an edge-on (singular) projection; descendants must retain normal coordinates.
private struct AlbumFlipHostingSurface<Front: View, Back: View>: UIViewControllerRepresentable {
    let front: Front
    let back: Back
    let sourceSize: CGSize
    let destinationSize: CGSize
    let progress: CGFloat
    let angle: Double
    let reduceMotion: Bool
    let showsReflection: Bool
    @Environment(\.self) private var environment

    func makeUIViewController(context: Context) -> AlbumFlipHostingController {
        AlbumFlipHostingController()
    }

    func updateUIViewController(_ controller: AlbumFlipHostingController, context: Context) {
        controller.front.rootView = AnyView(front.environment(\.self, environment))
        controller.back.rootView = AnyView(back.environment(\.self, environment))
        controller.sourceSize = sourceSize
        controller.destinationSize = destinationSize
        controller.progress = progress
        controller.angle = angle
        controller.reduceMotion = reduceMotion
        controller.showsReflection = showsReflection
        controller.view.setNeedsLayout()
    }
}

private final class AlbumFlipHostingController: UIViewController {
    let front = UIHostingController(rootView: AnyView(EmptyView()))
    let back = UIHostingController(rootView: AnyView(EmptyView()))
    var sourceSize = CGSize(width: 1, height: 1)
    var destinationSize = CGSize(width: 1, height: 1)
    var progress: CGFloat = 0
    var angle: Double = 0
    var reduceMotion = false
    var showsReflection = false
    private let stage = AlbumReflectionStage()
    private let fade = CAGradientLayer()
    private let frontShadow = CALayer()
    private let backShadow = CALayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // Flat projected shadows stay behind the composited card and reflection.
        for shadow in [frontShadow, backShadow] {
            shadow.shadowColor = UIColor.black.cgColor
            shadow.zPosition = -1
            view.layer.addSublayer(shadow)
        }
        view.addSubview(stage)
        for host in [front, back] {
            addChild(host)
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            stage.addSubview(host.view)
            host.didMove(toParent: self)
        }
        back.view.backgroundColor = .systemBackground
        back.view.layer.cornerRadius = 24
        back.view.layer.cornerCurve = .continuous
        back.view.clipsToBounds = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = max(1, view.bounds.width)
        let height = max(1, view.bounds.height)
        // Perspective makes the nearer edge taller. Reflect below its projected
        // bottom, otherwise the mirrored copy crosses over the real card.
        let radians = (progress < 0.5 ? angle : (reduceMotion ? 0 : angle - 180)) * .pi / 180
        let perspectiveW = abs(sin(radians)) * width / (4 * max(width, height))
        let projectedBottom = height / 2 + (height / 2) / (1 - perspectiveW)
        let stageHeight = projectedBottom * 2 + 2
        stage.frame = CGRect(x: 0, y: 0, width: width, height: stageHeight)
        let replicator = stage.layer as! CAReplicatorLayer
        replicator.instanceCount = showsReflection ? 2 : 1
        replicator.instanceAlphaOffset = -0.55
        var mirror = CATransform3DMakeTranslation(0, 0, 0)
        mirror = CATransform3DScale(mirror, 1, -1, 1)
        replicator.instanceTransform = mirror
        if showsReflection {
            let overscan = max(width, height)
            let maskHeight = stageHeight + overscan
            fade.frame = CGRect(x: -overscan, y: -overscan,
                                width: width + overscan * 2, height: maskHeight)
            fade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
            fade.locations = [0, NSNumber(value: (overscan + projectedBottom) / maskHeight),
                              NSNumber(value: (overscan + projectedBottom + height * 0.9) / maskHeight)]
            stage.layer.mask = fade
        } else {
            stage.layer.mask = nil
        }
        for (host, size, degrees, visible) in [
            (front, sourceSize, angle, progress < 0.5),
            (back, destinationSize, reduceMotion ? 0 : angle - 180, progress >= 0.5)
        ] {
            let size = CGSize(width: max(1, size.width), height: max(1, size.height))
            host.view.bounds = CGRect(origin: .zero, size: size)
            host.view.center = CGPoint(x: width / 2, y: height / 2)
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / (max(width, height) * 2)
            let rotation = CATransform3DRotate(perspective, degrees * .pi / 180, 0, 1, 0)
            host.view.layer.transform = CATransform3DScale(rotation, width / size.width, height / size.height, 1)
            let shadow = host === front ? frontShadow : backShadow
            shadow.frame = view.bounds
            // Do not rotate an independent shadow layer in 3D: half of that
            // plane can cross in front of the card's composited reflection stage.
            // Project its outline into 2D instead, so z-order never changes.
            let outline = UIBezierPath(roundedRect: host.view.bounds,
                                       cornerRadius: host === front ? sourceSize.width * 0.05 : 24).cgPath
            shadow.shadowPath = projectedShadowPath(outline, size: size,
                                                     center: host.view.center,
                                                     transform: host.view.layer.transform)
            shadow.shadowOpacity = 0.6
            // Cover Flow scales its 224pt source card by 1.16 before handing off.
            shadow.shadowRadius = 24 * 1.16
            shadow.shadowOffset = CGSize(width: 0, height: 12 * 1.16)
            shadow.isHidden = !showsReflection || !visible
            host.view.isHidden = !visible
            host.view.accessibilityElementsHidden = !visible || progress < 1
        }
        CATransaction.commit()
    }

    private func projectedShadowPath(_ path: CGPath, size: CGSize,
                                     center: CGPoint, transform t: CATransform3D) -> CGPath {
        func project(_ point: CGPoint) -> CGPoint {
            let x = point.x - size.width / 2
            let y = point.y - size.height / 2
            let w = x * t.m14 + y * t.m24 + t.m44
            return CGPoint(x: center.x + (x * t.m11 + y * t.m21 + t.m41) / w,
                           y: center.y + (x * t.m12 + y * t.m22 + t.m42) / w)
        }
        let result = CGMutablePath()
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint: result.move(to: project(element.points[0]))
            case .addLineToPoint: result.addLine(to: project(element.points[0]))
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: project(element.points[1]), control: project(element.points[0]))
            case .addCurveToPoint:
                result.addCurve(to: project(element.points[2]), control1: project(element.points[0]),
                                control2: project(element.points[1]))
            case .closeSubpath: result.closeSubpath()
            @unknown default: break
            }
        }
        return result
    }

}

/// Mirrors the existing rendered layers, including list scrolling, without a second list.
private final class AlbumReflectionStage: UIView {
    override class var layerClass: AnyClass { CAReplicatorLayer.self }
}

/// Even-odd filling removes the rounded detail card from the full-screen hit area.
private struct AlbumFlipOutsideRegion: Shape {
    let card: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: card, cornerSize: CGSize(width: 24, height: 24))
        return path
    }
}
