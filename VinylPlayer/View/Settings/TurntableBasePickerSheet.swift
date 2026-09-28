import SwiftUI

struct TurntableBasePickerSheet: View {
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Live preview
                        livePreview
                            .padding(.top, 8)

                        // Style grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(TurntableBaseStyle.allCases) { style in
                                styleCard(style)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L("settings.turntable_base"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Live Preview

    private var livePreview: some View {
        // Preview the selected base material with the player's platter and disc.
        let diameter: CGFloat = 380
        let layout = TurntableHardwareLayout(
            recordDiameter: diameter,
            baseReferenceSize: diameter * 0.85 / 1.14,
            showsLyrics: true
        )
        let scale: CGFloat = 0.40
        let bounds = layout.baseSideLength * sqrt(2.0)
        // Include the platter's 16pt rim inside 80% of the base side length.
        let previewRecordDiameter = layout.baseSideLength * 0.80 - 16

        return ZStack {
            TurntableBaseView(
                layout: layout,
                baseStyle: styleManager.turntableBaseStyle,
                isPlaying: false
            )
            TurntablePlatterView(recordDiameter: previewRecordDiameter)
            VinylDiscView(album: nil, size: previewRecordDiameter, rotation: 0, vinylColor: .black)

        }
        .frame(width: bounds, height: bounds)
        .scaleEffect(scale)
        .frame(width: bounds * scale, height: bounds * scale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.spring(duration: 0.4), value: styleManager.turntableBaseStyle)
    }

    // MARK: - Style Card

    private func styleCard(_ style: TurntableBaseStyle) -> some View {
        let isSelected = styleManager.turntableBaseStyle == style
        let cardSize: CGFloat = 56
        let cornerRadius: CGFloat = 8

        return Button {
            withAnimation(.spring(duration: 0.3)) {
                styleManager.turntableBaseStyle = style
            }
        } label: {
            VStack(spacing: 8) {
                // Mini base preview
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: style.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: cardSize, height: cardSize)

                    if style.showsWoodGrain {
                        WoodGrainCanvas(size: cardSize, style: style)
                            .frame(width: cardSize, height: cardSize)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isSelected ? styleManager.theme.accentColor : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                        .frame(width: cardSize, height: cardSize)
                }

                Text(style.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? styleManager.theme.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
