import SwiftUI

/// Draws realistic organic curved wood grain lines using Canvas.
/// Uses seeded randomness so the pattern is stable across redraws.
/// Colors are parameterized via TurntableBaseStyle.
struct WoodGrainCanvas: View {
    let size: CGFloat
    var style: TurntableBaseStyle = .darkWalnut

    var body: some View {
        let lightRange = style.grainLightColorRange
        let darkRange = style.grainDarkColorRange
        let knotColor = style.grainKnotColor

        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Seeded RNG for stable pattern
            var rng = SeededRandomNumberGenerator(seed: 42)

            // Draw curved grain lines across the surface
            var y: CGFloat = 0
            while y < h {
                let isLightBand = Int.random(in: 0...2, using: &rng) == 0
                let thickness: CGFloat = isLightBand
                    ? CGFloat.random(in: 1.5...3.5, using: &rng)
                    : CGFloat.random(in: 0.5...1.2, using: &rng)

                let colorRange = isLightBand ? lightRange : darkRange
                let color = Color(
                    red: Double.random(in: colorRange.r, using: &rng),
                    green: Double.random(in: colorRange.g, using: &rng),
                    blue: Double.random(in: colorRange.b, using: &rng)
                )
                let opacity = isLightBand
                    ? Double.random(in: 0.22...0.40, using: &rng)
                    : Double.random(in: 0.15...0.30, using: &rng)

                // Build a curved path with bezier control points
                var path = Path()
                let segments = 4
                let segWidth = w / CGFloat(segments)

                // Varying vertical wave for organic feel
                let waveAmp = CGFloat.random(in: 2...8, using: &rng)
                let phaseShift = CGFloat.random(in: 0...(.pi * 2), using: &rng)

                path.move(to: CGPoint(x: 0, y: y + waveAmp * sin(phaseShift)))

                for seg in 0..<segments {
                    let x0 = CGFloat(seg) * segWidth
                    let x1 = CGFloat(seg + 1) * segWidth
                    let midX = (x0 + x1) / 2

                    let cp1Y = y + waveAmp * sin(phaseShift + CGFloat(seg) * 0.8)
                        + CGFloat.random(in: -3...3, using: &rng)
                    let cp2Y = y + waveAmp * sin(phaseShift + CGFloat(seg) * 0.8 + 0.4)
                        + CGFloat.random(in: -3...3, using: &rng)
                    let endY = y + waveAmp * sin(phaseShift + CGFloat(seg + 1) * 0.8)

                    path.addCurve(
                        to: CGPoint(x: x1, y: endY),
                        control1: CGPoint(x: midX - segWidth * 0.15, y: cp1Y),
                        control2: CGPoint(x: midX + segWidth * 0.15, y: cp2Y)
                    )
                }

                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    lineWidth: thickness
                )

                // Spacing between grain lines
                y += thickness + CGFloat.random(in: 2.0...5.0, using: &rng)
            }

            // Occasional knot (elliptical swirl)
            let knotCount = Int.random(in: 1...2, using: &rng)
            for _ in 0..<knotCount {
                let kx = CGFloat.random(in: w * 0.15...w * 0.85, using: &rng)
                let ky = CGFloat.random(in: h * 0.15...h * 0.85, using: &rng)
                let knotW = CGFloat.random(in: 12...22, using: &rng)
                let knotH = CGFloat.random(in: 6...12, using: &rng)

                // Draw concentric ellipses for knot
                for ring in 0..<3 {
                    let scale = 1.0 + CGFloat(ring) * 0.4
                    let knotPath = Path(ellipseIn: CGRect(
                        x: kx - knotW * scale / 2,
                        y: ky - knotH * scale / 2,
                        width: knotW * scale,
                        height: knotH * scale
                    ))
                    let knotOpacity = Double(3 - ring) * 0.08
                    context.stroke(
                        knotPath,
                        with: .color(knotColor.opacity(knotOpacity)),
                        lineWidth: CGFloat.random(in: 0.8...1.5, using: &rng)
                    )
                }
            }
        }
    }
}

/// Simple seeded RNG for stable random patterns across redraws.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
