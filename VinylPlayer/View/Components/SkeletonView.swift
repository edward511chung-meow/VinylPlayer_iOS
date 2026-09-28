import SwiftUI

// MARK: - Shimmer Animation Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var duration: Double = 1.55

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let bandWidth = max(72, w * 0.32)
                    let progress = (phase + 1) / 2

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.04),
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.26),
                            Color.white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth, height: max(80, h * 1.45))
                    .rotationEffect(.degrees(16))
                    .offset(
                        x: progress * (w + bandWidth) - bandWidth,
                        y: -max(10, h * 0.2)
                    )
                    .blendMode(.screen)
                    .mask(content)
                }
            )
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func shimmer(duration: Double = 1.55) -> some View {
        modifier(ShimmerModifier(duration: duration))
    }
}

// MARK: - Skeleton Shape

/// A single skeleton placeholder block with shimmer.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 6
    var showsShimmer = true

    @Environment(\.colorScheme) private var colorScheme

    private var baseColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.10)
    }

    var body: some View {
        let block = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseColor)
            .frame(width: width, height: height)

        if showsShimmer {
            block.shimmer()
        } else {
            block
        }
    }
}

/// A circular skeleton placeholder with shimmer.
struct SkeletonCircle: View {
    var size: CGFloat = 48

    @Environment(\.colorScheme) private var colorScheme

    private var baseColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.10)
    }

    var body: some View {
        Circle()
            .fill(baseColor)
            .frame(width: size, height: size)
            .shimmer()
    }
}

// MARK: - Skeleton Row (list-style loading placeholder)

/// A skeleton row matching a typical artwork + text list item.
struct SkeletonListRow: View {
    var artworkSize: CGFloat = 48
    var artworkRadius: CGFloat = 6
    var lineCount: Int = 2
    var isCircular: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Artwork placeholder
            if isCircular {
                SkeletonCircle(size: artworkSize)
            } else {
                SkeletonBlock(
                    width: artworkSize,
                    height: artworkSize,
                    cornerRadius: artworkRadius
                )
            }

            // Text lines
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 14, cornerRadius: 4)
                    .frame(maxWidth: .infinity)

                if lineCount >= 2 {
                    SkeletonBlock(height: 12, cornerRadius: 4)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.45)
                }

                if lineCount >= 3 {
                    SkeletonBlock(height: 10, cornerRadius: 3)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Skeleton Grid Cell (grid-style loading placeholder)

/// A skeleton cell matching VinylCoverCard layout (cover + vinyl disc + text).
struct SkeletonGridCell: View {
    var showsShimmer = true

    @Environment(\.colorScheme) private var colorScheme

    private var baseColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.13)
    }

    private var outlineColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    var body: some View {
        let cell = VStack(alignment: .leading, spacing: 8) {
            // Cover + vinyl disc area (matches VinylCoverCard)
            ZStack(alignment: .trailing) {
                // Vinyl disc placeholder (right side)
                Circle()
                    .fill(baseColor)
                    .overlay {
                        Circle()
                            .stroke(outlineColor, lineWidth: 1)
                    }
                    .frame(width: 120, height: 120)
                    .offset(x: 16)

                // Album cover placeholder (left side, on top)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(baseColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    }
                    .frame(width: 144, height: 144)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 144)
            .clipped()

            // Title
            SkeletonBlock(height: 12, cornerRadius: 4, showsShimmer: false)

            // Artist
            SkeletonBlock(height: 10, cornerRadius: 3, showsShimmer: false)
                .frame(width: 80, alignment: .leading)
        }

        if showsShimmer {
            cell.shimmer()
        } else {
            cell
        }
    }
}

// MARK: - Preview

#Preview("Skeleton Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("List Rows")
                .font(.headline)
                .padding(.horizontal)

            ForEach(0..<4, id: \.self) { _ in
                SkeletonListRow(artworkSize: 48, lineCount: 2)
            }

            Divider().padding(.horizontal)

            Text("List Rows (3 lines, 56px)")
                .font(.headline)
                .padding(.horizontal)

            ForEach(0..<3, id: \.self) { _ in
                SkeletonListRow(artworkSize: 56, lineCount: 3)
            }

            Divider().padding(.horizontal)

            Text("Grid Cells")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)],
                spacing: 16
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonGridCell()
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .preferredColorScheme(.dark)
}
