import SwiftUI
import UIKit

/// Spinning vinyl disc with grooves and a reflection-free main surface,
/// colored vinyl support (including splatter/marbled), and center label.
struct VinylDiscView: View {
    let album: Album?
    let size: CGFloat
    let rotation: Double
    let vinylColor: VinylColor
    var customColorHex: String? = nil
    var discOpacityOverride: Double = 1.0
    var playerAnimation: Namespace.ID? = nil
    var isPlayerExpanded: Bool = false
    var animator: VinylAnimator? = nil
    var usesLiveGlass: Bool = true
    var labelArtworkOverride: UIImage? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var baseColor: Color {
        if let hex = customColorHex, !hex.isEmpty {
            return Color(hex: hex) ?? Color(white: 0.1)
        }
        return Color(hex: vinylColor.colorHex) ?? Color(white: 0.1)
    }

    private var hasCustomColor: Bool {
        if let hex = customColorHex, !hex.isEmpty { return true }
        return false
    }

    private var isTranslucent: Bool {
        effectiveDiscOpacity < 0.99
    }

    private var effectiveDiscOpacity: Double {
        let base = hasCustomColor ? 1.0 : vinylColor.discOpacity
        return base * discOpacityOverride
    }

    var body: some View {
        ZStack {
            if isTranslucent {
                // The optical surface does not rotate or observe display ticks.
                glassSurface
                ZStack {
                    grooveRings
                    colorEffects
                    centerLabel
                }
                .modifier(VinylRotationEffect(rotation: rotation, animator: animator))
            } else {
                ZStack {
                    discBody
                    grooveRings
                    colorEffects
                    centerLabel
                }
                .modifier(VinylRotationEffect(rotation: rotation, animator: animator))
            }
        }
        .frame(width: size, height: size)
    }

    private var glassSurface: some View {
        ZStack {
            if usesLiveGlass && !reduceTransparency {
                Circle()
                    .fill(.clear)
                    .glassEffect(.clear.tint(baseColor.opacity(0.30 + effectiveDiscOpacity * 0.45)), in: Circle())
            } else {
                // ImageRenderer cannot capture a live backdrop. Keep a static
                // tinted surface for exported cards and Reduce Transparency.
                Circle()
                    .fill(baseColor.opacity(reduceTransparency ? 1 : 0.35 + effectiveDiscOpacity * 0.45))
            }
            Circle()
                .fill(RadialGradient(
                    colors: [baseColor.opacity(0.06), baseColor.opacity(effectiveDiscOpacity * 0.22),
                             baseColor.opacity(0.40)],
                    center: .center, startRadius: size * 0.13, endRadius: size * 0.5))
            Circle()
                .strokeBorder(AngularGradient(
                    colors: [.white.opacity(0.65), baseColor.opacity(0.35), .black.opacity(0.22),
                             .white.opacity(0.40), baseColor.opacity(0.40), .white.opacity(0.65)],
                    center: .center), lineWidth: max(1, size * 0.006))
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // MARK: - Disc Body

    private var discBody: some View {
        ZStack {
            // Outer edge bevel
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            baseColor.opacity(0.95 * effectiveDiscOpacity),
                            baseColor.opacity(effectiveDiscOpacity),
                            baseColor.opacity(0.7 * effectiveDiscOpacity)
                        ],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)

            // Rim highlight — stronger for translucent to show the edge
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(isTranslucent ? 0.25 : 0.08),
                            Color.clear,
                            Color.white.opacity(isTranslucent ? 0.18 : 0.05),
                            Color.clear,
                            Color.white.opacity(isTranslucent ? 0.25 : 0.08)
                        ],
                        center: .center
                    ),
                    lineWidth: isTranslucent ? 2.0 : 1.5
                )
                .frame(width: size - 1, height: size - 1)

            Circle()
                .stroke(Color.black.opacity(isTranslucent ? 0.12 : 0.48), lineWidth: size * 0.012)
                .frame(width: size - size * 0.012, height: size - size * 0.012)
                .overlay {
                    Circle()
                        .trim(from: 0.56, to: 0.82)
                        .stroke(Color.white.opacity(isTranslucent ? 0.20 : 0.13), lineWidth: size * 0.004)
                        .frame(width: size - size * 0.018, height: size - size * 0.018)
                }
        }
    }

    // MARK: - Grooves

    private var grooveRings: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let innerRadius = canvasSize.width * 0.14  // Label edge
            let outerRadius = canvasSize.width * 0.47  // Near disc edge
            let grooveCount = AppConstants.vinylGrooveCount

            for i in 0..<grooveCount {
                let t = Double(i) / Double(grooveCount)
                let radius = innerRadius + t * (outerRadius - innerRadius)

                // Alternate groove visibility — stronger on translucent vinyl
                let boost: Double = isTranslucent ? 2.5 : 1.5
                let opacity: Double = {
                    if i % 5 == 0 { return 0.10 * boost }       // Wider groove marks
                    if i % 2 == 0 { return 0.055 * boost }
                    return 0.035 * boost
                }()

                let path = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 0.6)
            }

            // Lead-in groove (outer) — slightly wider
            let leadIn = Path(ellipseIn: CGRect(
                x: center.x - outerRadius - 2,
                y: center.y - outerRadius - 2,
                width: (outerRadius + 2) * 2,
                height: (outerRadius + 2) * 2
            ))
            context.stroke(leadIn, with: .color(.white.opacity(0.10)), lineWidth: 1.2)

            // Run-out groove (inner) — near label
            let runOut = Path(ellipseIn: CGRect(
                x: center.x - innerRadius + 2,
                y: center.y - innerRadius + 2,
                width: (innerRadius - 2) * 2,
                height: (innerRadius - 2) * 2
            ))
            context.stroke(runOut, with: .color(.white.opacity(0.10)), lineWidth: 1.2)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // MARK: - Color Effects (splatter, marbled)

    @ViewBuilder
    private var colorEffects: some View {
        if hasCustomColor {
            EmptyView()
        } else { colorEffectsForEdition }
    }

    @ViewBuilder
    private var colorEffectsForEdition: some View {
        switch vinylColor {
        case .splatter:
            // Random splatter dots
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let colors: [Color] = [.red, .blue, .yellow, .green, .white]

                // Use fixed seed positions for consistency
                let positions: [(Double, Double, Double, Int)] = [
                    (0.2, 0.3, 8, 0), (0.7, 0.25, 6, 1), (0.35, 0.7, 10, 2),
                    (0.65, 0.6, 7, 3), (0.5, 0.2, 5, 4), (0.3, 0.5, 9, 0),
                    (0.8, 0.45, 6, 1), (0.15, 0.65, 8, 2), (0.55, 0.8, 7, 3),
                    (0.4, 0.15, 5, 4), (0.75, 0.7, 8, 0), (0.2, 0.8, 6, 1),
                    (0.6, 0.35, 9, 2), (0.45, 0.55, 7, 3), (0.85, 0.3, 5, 4),
                ]

                for (px, py, radius, colorIdx) in positions {
                    let x = canvasSize.width * px
                    let y = canvasSize.height * py
                    let dist = hypot(x - center.x, y - center.y)

                    // Only draw within the vinyl disc area (outside label, inside edge)
                    if dist > canvasSize.width * 0.14 && dist < canvasSize.width * 0.46 {
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(colors[colorIdx].opacity(0.6)))
                    }
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)

        case .marbled:
            // Swirl pattern
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                for i in 0..<12 {
                    let angle = Double(i) * 30 + 15
                    let rad = angle * .pi / 180
                    var path = Path()
                    // Wavy line from center outward
                    for j in stride(from: 20.0, to: canvasSize.width * 0.46, by: 2) {
                        let wobble = sin(j * 0.08 + Double(i)) * 12
                        let x = center.x + cos(rad) * j + cos(rad + .pi/2) * wobble
                        let y = center.y + sin(rad) * j + sin(rad + .pi/2) * wobble
                        if j == 20 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.08)), lineWidth: 2)
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)

        default:
            EmptyView()
        }
    }

    // MARK: - Center Label

    @ViewBuilder
    private var centerLabel: some View {
        let label = ZStack {
            // Label disc
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (album?.color ?? .gray).opacity(0.9),
                            (album?.color ?? .gray).opacity(0.7),
                            (album?.color ?? .gray).opacity(0.5)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.12
                    )
                )
                .frame(width: size * 0.26, height: size * 0.26)

            // Label texture rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    .frame(
                        width: size * (0.08 + CGFloat(i) * 0.04),
                        height: size * (0.08 + CGFloat(i) * 0.04)
                    )
            }

            // Album art or text in center
            if let image = labelArtworkOverride {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size * 0.22, height: size * 0.22)
                    .clipShape(Circle())
            } else if let album {
                if let imageData = album.customCoverImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size * 0.22, height: size * 0.22)
                        .clipShape(Circle())

                } else if let urlString = album.displayArtworkURL,
                          let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size * 0.22, height: size * 0.22)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: size * 0.22, height: size * 0.22)
                    }
                    .frame(width: size * 0.22, height: size * 0.22)
                } else {
                    centerLabelText(album: album)
                }
            }

            // Spindle hole
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.022, height: size * 0.022)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )

            // Label edge ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .scaleEffect(1.6)

        if let animation = playerAnimation {
            label.matchedGeometryEffect(id: "Album", in: animation, isSource: isPlayerExpanded)
        } else {
            label
        }
    }

    // MARK: - Center Label Text Fallback

    private func centerLabelText(album: Album) -> some View {
        VStack(spacing: 2) {
            Text(album.title)
                .font(.system(size: max(7, size * 0.028), weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text(album.artist)
                .font(.system(size: max(5, size * 0.02)))
                .lineLimit(1)
            
            if let edition = album.selectedEdition {
                Text(edition.label)
                    .font(.system(size: max(4, size * 0.016)))
                    .opacity(0.7)
                    .lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .frame(width: size * 0.2)
    }

}

/// Keep expensive static artwork out of the display-link observation boundary.
/// Counter-rotating reflections use the same clock so their lighting stays fixed.
private struct VinylRotationEffect: ViewModifier {
    let rotation: Double
    let animator: VinylAnimator?
    var direction: Double = 1

    func body(content: Content) -> some View {
        if let animator {
            content.modifier(DisplayLinkedRotation(animator: animator, direction: direction))
        } else {
            content.rotationEffect(.degrees(rotation))
        }
    }
}

private struct DisplayLinkedRotation: ViewModifier {
    @ObservedObject var animator: VinylAnimator
    let direction: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(animator.rotation * direction))
            .animation(nil, value: animator.rotation)
    }
}

#Preview("Liquid Glass — Tinted Vinyl") {
    ScrollView {
        VStack(spacing: 28) {
            ForEach(["#D62C62", "#268BD9", "#793DC4"], id: \.self) { hex in
                ZStack {
                    TurntablePlatterView(recordDiameter: 250, showsTransparentRecord: true)
                    VinylDiscView(album: nil, size: 250, rotation: 0, vinylColor: .clear,
                                  customColorHex: hex, discOpacityOverride: 0.45)
                }
            }
        }
        .padding(32)
    }
    .background(Color(red: 0.65, green: 0.51, blue: 0.34))
}
