import SwiftUI

/// Playback radii relative to the displayed record diameter. The outer value
/// matches the drawn groove edge; the inner value leaves room for the run-out.
enum TonearmPlaybackPath {
    static let outerGrooveRatio: CGFloat = 0.47
    static let innerGrooveRatio: CGFloat = 0.20
    static let parkingClearanceDegrees: Double = 6
}

/// 手動調整外觀：1.0 = 本次修改前尺寸；數值越大，部件越大。
private enum TonearmAppearance {
    /// 圓環底座整體比例（直徑、內圈、螺絲一齊縮放）。
    static let mountScale: CGFloat = 1.80
    /// 臂管粗幼比例，不會改變臂長。
    static let tubeThicknessScale: CGFloat = 1.44
    /// 唱頭整體比例（長、闊、螺絲、唱針一齊縮放）。
    static let headshellScale: CGFloat = 1.60
}

/// Reference-inspired hardware sized for the compact diamond-shaped plinth.
struct InteractiveTonearmView: View {
    let progress: Double
    let vinylCenterOffset: CGSize
    @Binding var isLifted: Bool
    let isParked: Bool
    let tonearmColor: Color
    /// Hardware and arm length share the record's layout scale.
    let recordDiameter: CGFloat
    let hardwareSize: CGFloat
    let armLength: CGFloat
    var onSeek: (Double) -> Void

    @State private var dragProgress: Double?
    @State private var dragStartProgress: Double?

    private var displayedProgress: Double { min(1, max(0, dragProgress ?? progress)) }
    private var geometry: TonearmGeometry {
        TonearmGeometry(vinylCenterOffset: vinylCenterOffset,
                        recordDiameter: recordDiameter, armLength: armLength,
                        progress: displayedProgress)
    }
    private var currentAngle: Double {
        isParked ? geometry.parkingAngle : geometry.angle
    }
    // Draw the complete assembly at one reference size, then animate one uniform
    // scale. Canvas drawing commands themselves do not interpolate layout sizes.
    private let drawingReferenceSize: CGFloat = 380
    private var drawingScale: CGFloat { hardwareSize / drawingReferenceSize }
    private var normalizedArmLength: CGFloat { armLength / drawingScale }
    private var drawingSize: CGFloat {
        max(drawingReferenceSize * 2.4, normalizedArmLength * 2 + drawingReferenceSize * 0.4)
    }

    var body: some View {
        ZStack {
            Canvas { context, canvas in
                var drawing = TonearmDrawing(context: context)
                drawing.context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                drawing.context.scaleBy(x: drawingReferenceSize / 1140, y: drawingReferenceSize / 1140)
                drawing.drawMount()
            }
            .allowsHitTesting(false)

            Canvas { context, canvas in
                var drawing = TonearmDrawing(context: context)
                drawing.context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                drawing.context.scaleBy(x: drawingReferenceSize / 1140, y: drawingReferenceSize / 1140)
                drawing.drawArm(length: normalizedArmLength * 1140 / drawingReferenceSize, tint: tonearmColor)
            }
            .contentShape(TonearmHitShape(length: normalizedArmLength, scale: drawingReferenceSize / 1140))
            .shadow(color: .black.opacity(isLifted ? 0.46 : 0.32),
                    radius: drawingReferenceSize * (isLifted ? 0.016 : 0.004),
                    x: drawingReferenceSize * (isLifted ? 0.018 : 0.004),
                    y: drawingReferenceSize * (isLifted ? 0.025 : 0.008))
            .offset(y: isLifted ? -drawingReferenceSize * 0.018 : 0)
            .rotationEffect(.degrees(currentAngle))
            .animation(.interpolatingSpring(stiffness: 120, damping: 18), value: isParked)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isLifted)
            .gesture(tonearmDrag)
        }
        .frame(width: drawingSize, height: drawingSize)
        .scaleEffect(drawingScale)
        // The parent positions the physical bearing, not the artwork's bounds.
        .frame(width: hardwareSize * 0.095, height: hardwareSize * 0.095)
    }

    private var tonearmDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                let travelWidth = max(recordDiameter * (TonearmPlaybackPath.outerGrooveRatio
                                                       - TonearmPlaybackPath.innerGrooveRatio), 1)
                let startProgress = dragStartProgress ?? displayedProgress
                dragStartProgress = startProgress
                let newProgress = startProgress - Double(value.translation.width * drawingScale / travelWidth)
                let clampedProgress = min(1, max(0, newProgress))
                dragProgress = clampedProgress
                onSeek(clampedProgress)
            }
            .onEnded { _ in
                dragProgress = nil
                dragStartProgress = nil
            }
    }
}

/// Intersection of the rigid arm's sweep and the current record groove. Playback
/// rotates the arm; layout changes scale its length with the rest of the hardware.
struct TonearmGeometry {
    let vinylCenterOffset: CGSize
    let recordDiameter: CGFloat
    let armLength: CGFloat
    let progress: Double

    var grooveRadius: CGFloat {
        let outer = recordDiameter * TonearmPlaybackPath.outerGrooveRatio
        let inner = recordDiameter * TonearmPlaybackPath.innerGrooveRatio
        let requested = outer + (inner - outer) * min(1, max(0, progress))
        // A rigid arm can only reach this annulus. Keep the solver valid if
        // the user later changes the mounting point or effective arm length.
        let distance = hypot(vinylCenterOffset.width, vinylCenterOffset.height)
        return min(distance + armLength, max(abs(distance - armLength), requested))
    }

    var parkingAngle: Double {
        let outer = TonearmGeometry(vinylCenterOffset: vinylCenterOffset,
                                    recordDiameter: recordDiameter, armLength: armLength,
                                    progress: 0)
        return outer.angle - TonearmPlaybackPath.parkingClearanceDegrees
    }

    var stylusTarget: CGPoint {
        let dx = vinylCenterOffset.width
        let dy = vinylCenterOffset.height
        let distance = hypot(dx, dy)
        guard distance > 0, armLength > 0 else {
            return CGPoint(x: 0, y: max(0, armLength))
        }
        let projection = (armLength * armLength + distance * distance
                          - grooveRadius * grooveRadius) / (2 * distance)
        // Degenerate/unreachable inputs fall back to the closest sweep point.
        let along = min(armLength, max(-armLength, projection))
        let across = sqrt(max(0, armLength * armLength - along * along))
        // Select the right-hand intersection so the arm stays over the record's
        // outer-right quadrant, in both the radial and rotated centered layout.
        return CGPoint(x: (dx * along + dy * across) / distance,
                       y: (dy * along - dx * across) / distance)
    }

    var angle: Double {
        let target = stylusTarget
        return -atan2(Double(target.x), Double(target.y)) * 180 / .pi
    }
}

/// Coordinates follow IMG_5155: 1140 px record diameter, bearing (1342, 288),
/// stylus (973, 1058). The bearing and counterweight use a compact scale to fit
/// the wooden plinth; the tube has a fixed length and follows the groove arc.
private struct TonearmDrawing {
    var context: GraphicsContext
    // Derive both transforms from the actual drawn stylus and bearing. Scaling
    // the headshell keeps this contact point at (0, length), on the solved arc.
    private static let referenceLength: CGFloat = hypot(973 - 1342, 1058 - 288)
    private static let referenceAngle = atan2(1342.0 - 973, 1058.0 - 288) * 180 / .pi
    static let bearingScale: CGFloat = 0.55
    private static let shellScale: CGFloat = 0.80 * TonearmAppearance.headshellScale

    mutating func useReferenceCoordinates() {
        context.rotate(by: .degrees(-Self.referenceAngle))
        context.translateBy(x: -1342, y: -288)
    }

    func path(_ points: [CGPoint], close: Bool = true) -> Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
            if close { p.closeSubpath() }
        }
    }

    func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        path(points.map { CGPoint(x: $0.0, y: $0.1) })
    }

    func fill(_ path: Path, shades: [Double], from: CGPoint, to: CGPoint) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: shades.map { Color(white: $0) }), startPoint: from, endPoint: to))
    }

    func line(_ points: [(CGFloat, CGFloat)], white: Double, width: CGFloat) {
        context.stroke(path(points.map { CGPoint(x: $0.0, y: $0.1) }, close: false),
                       with: .color(Color(white: white)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func screw(x: CGFloat, y: CGFloat, radius: CGFloat, slotted: Bool = true) {
        let bounds = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: bounds.offsetBy(dx: 1.5, dy: 2)), with: .color(.black))
        fill(Path(ellipseIn: bounds), shades: [0.79, 0.50, 0.24],
             from: CGPoint(x: x - radius, y: y - radius), to: CGPoint(x: x + radius, y: y + radius))
        context.stroke(Path(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5)),
                       with: .color(.white.opacity(0.23)), lineWidth: 1)
        if slotted {
            line([(x - radius * 0.48, y + radius * 0.36),
                  (x + radius * 0.48, y - radius * 0.36)], white: 0.23, width: 1.8)
        }
    }

    func drawMount() {
        var mount = self
        mount.context.scaleBy(x: TonearmAppearance.mountScale, y: TonearmAppearance.mountScale)
        mount.drawMountDetails()
    }

    private func drawMountDetails() {
        // Low-profile bearing screwed directly into the wood. The large donor
        // deck's recessed plate and remote cueing linkage do not fit this plinth.
        let flange = Path(ellipseIn: CGRect(x: -62, y: -62, width: 124, height: 124))
        context.fill(flange.offsetBy(dx: 2, dy: 4), with: .color(.black.opacity(0.28)))
        fill(flange, shades: [0.30, 0.15, 0.055, 0.13],
             from: CGPoint(x: -50, y: -52), to: CGPoint(x: 54, y: 58))
        context.stroke(flange, with: .color(.white.opacity(0.12)), lineWidth: 1.2)
        let inset = Path(ellipseIn: CGRect(x: -53, y: -53, width: 106, height: 106))
        fill(inset, shades: [0.105, 0.04, 0.075],
             from: CGPoint(x: -35, y: -42), to: CGPoint(x: 40, y: 44))
        context.stroke(inset, with: .color(.black.opacity(0.65)), lineWidth: 2)
        screw(x: -39, y: -35, radius: 4)
        screw(x: 38, y: 36, radius: 4)


    }

    func drawArm(length: CGFloat, tint: Color) {
        let tubeScale = TonearmAppearance.tubeThicknessScale
        var hardware = self
        hardware.context.scaleBy(x: Self.bearingScale, y: Self.bearingScale)
        hardware.useReferenceCoordinates()
        hardware.drawCounterweight()

        // A straight round tube, with the short bend immediately above the shell.
        // Transverse reflections stay continuous along the tube, like the photo.
        let shoulder = length - 167 * Self.shellScale
        var tube = Path()
        tube.move(to: CGPoint(x: 7 * Self.bearingScale, y: 91 * Self.bearingScale))
        tube.addCurve(to: CGPoint(x: -9 * Self.shellScale, y: shoulder),
                      control1: CGPoint(x: 5, y: min(200, shoulder * 0.45)),
                      control2: CGPoint(x: -6, y: shoulder - 90))
        tube.addCurve(to: CGPoint(x: -5 * Self.shellScale, y: length - 119 * Self.shellScale),
                      control1: CGPoint(x: -12 * Self.shellScale, y: shoulder + 27 * Self.shellScale),
                      control2: CGPoint(x: -10 * Self.shellScale, y: length - 131 * Self.shellScale))
        context.stroke(tube, with: .color(Color(white: 0.025)),
                       style: StrokeStyle(lineWidth: 40 * tubeScale, lineCap: .round))
        context.stroke(tube, with: .linearGradient(
            Gradient(stops: [.init(color: Color(white: 0.035), location: 0),
                             .init(color: Color(white: 0.34), location: 0.25),
                             .init(color: Color(white: 0.22), location: 0.42),
                             .init(color: Color(white: 0.075), location: 0.66),
                             .init(color: Color(white: 0.015), location: 1)]),
            startPoint: CGPoint(x: -26 * tubeScale, y: 0), endPoint: CGPoint(x: 28 * tubeScale, y: 0)),
                       style: StrokeStyle(lineWidth: 33 * tubeScale, lineCap: .round))
        context.stroke(tube, with: .color(tint.opacity(0.025)),
                       style: StrokeStyle(lineWidth: 26 * tubeScale, lineCap: .round))
        context.stroke(tube.offsetBy(dx: -10 * tubeScale, dy: 0), with: .color(.white.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 2 * tubeScale, lineCap: .round))
        hardware.drawBearing()

        var shell = self
        shell.context.translateBy(x: 0, y: length - Self.referenceLength * Self.shellScale)
        shell.context.scaleBy(x: Self.shellScale, y: Self.shellScale)
        shell.useReferenceCoordinates()
        shell.drawHeadshell()
    }

    func drawCounterweight() {
        // Cylinder ends are elliptical, rather than a capsule with rounded sides.
        let stem = polygon([(1348, 161), (1386, 176), (1358, 254), (1323, 240)])
        fill(stem, shades: [0.035, 0.30, 0.07, 0.025],
             from: CGPoint(x: 1335, y: 205), to: CGPoint(x: 1373, y: 220))
        let cylinder = Path { p in
            p.move(to: CGPoint(x: 1377, y: 43))
            p.addCurve(to: CGPoint(x: 1464, y: 70), control1: CGPoint(x: 1402, y: 39), control2: CGPoint(x: 1449, y: 54))
            p.addLine(to: CGPoint(x: 1425, y: 185))
            p.addQuadCurve(to: CGPoint(x: 1323, y: 152), control: CGPoint(x: 1365, y: 181))
            p.closeSubpath()
        }
        fill(cylinder, shades: [0.045, 0.43, 0.29, 0.08, 0.025, 0.18],
             from: CGPoint(x: 1349, y: 103), to: CGPoint(x: 1445, y: 135))
        line([(1380, 47), (1344, 145)], white: 0.43, width: 2)
        let dial = Path { p in
            p.move(to: CGPoint(x: 1325, y: 150))
            p.addCurve(to: CGPoint(x: 1426, y: 184), control1: CGPoint(x: 1356, y: 149), control2: CGPoint(x: 1405, y: 164))
            p.addLine(to: CGPoint(x: 1417, y: 211))
            p.addQuadCurve(to: CGPoint(x: 1317, y: 177), control: CGPoint(x: 1350, y: 185))
            p.closeSubpath()
        }
        fill(dial, shades: [0.26, 0.045, 0.12],
             from: CGPoint(x: 1345, y: 151), to: CGPoint(x: 1360, y: 201))
        line([(1327, 158), (1360, 164), (1394, 175), (1420, 189)], white: 0.37, width: 2)
        for i in 0..<11 {
            let x = 1329 + CGFloat(i) * 8
            let y = 170 + CGFloat(i) * 2.9
            line([(x, y), (x - 2, y + (i % 3 == 0 ? 7 : 4))], white: i % 3 == 0 ? 0.66 : 0.42, width: 1.5)
        }
        for (label, x, y) in [("0", 1348.0, 180.0), ("1", 1375.0, 189.0), ("2", 1400.0, 198.0)] {
            context.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(Color(white: 0.61)),
                         at: CGPoint(x: x, y: y))
        }
    }

    func drawBearing() {
        // Open gimbal and its diagonal rectangular bridge, not a domed cap.
        let collar = polygon([(1280, 301), (1353, 327), (1332, 404), (1263, 381)])
        fill(collar, shades: [0.04, 0.30, 0.13, 0.035],
             from: CGPoint(x: 1282, y: 347), to: CGPoint(x: 1330, y: 365))
        line([(1281, 384), (1320, 398)], white: 0.035, width: 3)
        let gimbal = polygon([(1250, 233), (1293, 213), (1380, 250), (1391, 325),
                              (1369, 354), (1335, 357), (1322, 338), (1356, 320),
                              (1354, 273), (1290, 247), (1252, 267)])
        fill(gimbal, shades: [0.46, 0.18, 0.035, 0.14],
             from: CGPoint(x: 1262, y: 216), to: CGPoint(x: 1368, y: 351))
        let bridge = Path { p in
            p.move(to: CGPoint(x: 1193, y: 236))
            p.addLine(to: CGPoint(x: 1227, y: 217))
            p.addQuadCurve(to: CGPoint(x: 1240, y: 218), control: CGPoint(x: 1233, y: 215))
            p.addLine(to: CGPoint(x: 1352, y: 268))
            p.addQuadCurve(to: CGPoint(x: 1364, y: 291), control: CGPoint(x: 1372, y: 278))
            p.addQuadCurve(to: CGPoint(x: 1340, y: 306), control: CGPoint(x: 1357, y: 308))
            p.addLine(to: CGPoint(x: 1212, y: 253))
            p.addLine(to: CGPoint(x: 1183, y: 264))
            p.closeSubpath()
        }
        fill(bridge, shades: [0.46, 0.19, 0.055, 0.13],
             from: CGPoint(x: 1246, y: 225), to: CGPoint(x: 1232, y: 263))
        line([(1195, 238), (1229, 219), (1345, 271)], white: 0.39, width: 2)
        screw(x: 1342, y: 286, radius: 12)
    }

    func drawHeadshell() {
        // Small burgundy lead visible behind the black shell.
        var wire = Path()
        wire.move(to: CGPoint(x: 1055, y: 948))
        wire.addCurve(to: CGPoint(x: 1056, y: 975), control1: CGPoint(x: 1080, y: 951), control2: CGPoint(x: 1071, y: 967))
        context.stroke(wire, with: .color(Color(red: 0.40, green: 0.15, blue: 0.19)), lineWidth: 5)
        context.stroke(wire.offsetBy(dx: 1, dy: -1), with: .color(Color(red: 0.75, green: 0.43, blue: 0.45)), lineWidth: 1.5)
        let cartridge = polygon([(963, 1000), (1025, 1024), (1036, 1056),
                                 (1018, 1074), (958, 1053), (946, 1035)])
        fill(cartridge, shades: [0.18, 0.03, 0.07],
             from: CGPoint(x: 967, y: 1007), to: CGPoint(x: 1007, y: 1069))
        let shell = Path { p in
            p.move(to: CGPoint(x: 1013, y: 921))
            p.addQuadCurve(to: CGPoint(x: 1036, y: 911), control: CGPoint(x: 1023, y: 912))
            p.addLine(to: CGPoint(x: 1059, y: 941))
            p.addQuadCurve(to: CGPoint(x: 1062, y: 966), control: CGPoint(x: 1066, y: 952))
            p.addLine(to: CGPoint(x: 1028, y: 1047))
            p.addQuadCurve(to: CGPoint(x: 1014, y: 1057), control: CGPoint(x: 1024, y: 1059))
            p.addLine(to: CGPoint(x: 969, y: 1037))
            p.addQuadCurve(to: CGPoint(x: 961, y: 1020), control: CGPoint(x: 957, y: 1030))
            p.closeSubpath()
        }
        fill(shell, shades: [0.14, 0.055, 0.025, 0.075],
             from: CGPoint(x: 980, y: 966), to: CGPoint(x: 1045, y: 996))
        context.stroke(shell, with: .color(Color(white: 0.22)), lineWidth: 1.8)
        line([(1012, 923), (998, 945), (975, 992)], white: 0.47, width: 2)
        // Short bent silver finger lift on the left edge, as in the reference.
        line([(967, 1005), (953, 1015), (944, 1030), (969, 1059)], white: 0.18, width: 11)
        line([(965, 1005), (951, 1016), (944, 1029), (970, 1059)], white: 0.74, width: 7)
        line([(960, 1008), (948, 1019), (946, 1028)], white: 0.94, width: 2)
        screw(x: 981, y: 1003, radius: 10, slotted: false)
        screw(x: 1012, y: 1040, radius: 9, slotted: false)
        line([(977, 1000), (984, 1003)], white: 0.80, width: 2)
        line([(1009, 1037), (1015, 1040)], white: 0.77, width: 2)
        line([(982, 1051), (973, 1058)], white: 0.73, width: 3)
        context.fill(Path(ellipseIn: CGRect(x: 970.5, y: 1055.5, width: 5, height: 5)), with: .color(Color(white: 0.13)))
    }
}

/// Limit hit testing to the hardware; the large drawing canvas must not cover
/// record gestures or the player's surrounding controls.
private struct TonearmHitShape: Shape {
    let length: CGFloat
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = rect.midX
        let y = rect.midY
        let bearingScale = scale * TonearmDrawing.bearingScale
        p.addEllipse(in: CGRect(x: x - 90 * bearingScale, y: y - 270 * bearingScale,
                               width: 180 * bearingScale, height: 380 * bearingScale))
        let width = max(44, 95 * scale)
        p.addRoundedRect(in: CGRect(x: x - width / 2, y: y,
                                    width: width, height: length + 24 * scale),
                         cornerSize: CGSize(width: width / 2, height: width / 2))
        return p
    }
}
