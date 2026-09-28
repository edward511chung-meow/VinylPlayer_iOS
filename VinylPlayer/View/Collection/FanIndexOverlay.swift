import SwiftUI
import SwiftData

// MARK: - Fan Index Config

/// Tunable parameters for the diagonal fan card stack with vertical lift indexing.
/// Values derived from reference footage measurements.
struct FanIndexConfig {
    var centersShortQueues = false
    /// Horizontal offset per card (points) — cards march to the right
    var dx: CGFloat = 13
    /// Vertical offset per card (points, negative = upward along the fan)
    var dy: CGFloat = -8
    /// Scale reduction per card (compounding depth cue)
    var scaleStep: CGFloat = 0
    /// Y-axis 3D tilt in degrees (0 = flat, higher = more spine visible).
    /// Applied uniformly so the front card leans the same way as the queue.
    var tilt: Double = 0
    /// Perspective strength for the 3D tilt
    var perspective: CGFloat = 0
    /// Shared in-plane angle for every card. Keeping this separate from the
    /// fan's dx/dy means the first card has the same angle as the queued cards.
    var cardAngle: Double = 0
    /// Card width as a ratio of container width
    var cardWidthRatio: CGFloat = 0.34
    /// Card aspect ratio (height / width). Measured ≈ 1.37 for magazines
    var aspectRatio: CGFloat = 1.37
    /// Corner radius of each card
    var cornerRadius: CGFloat = 0

    // --- Vertical lift (the indexing effect) ---
    /// How far the indexed card rises, as a ratio of card height.
    /// The card STAYS in the queue — cards in front still overlap it, so this
    /// only makes it peek above the fan line.
    var liftRatio: CGFloat = 0.24
    /// Extra scale applied to the lifted card
    var liftScale: CGFloat = 1.0
    /// Shadow radius added under the lifted card
    var liftShadowRadius: CGFloat = 2
    /// How many neighbours share a partial lift (1.0 = blends between two cards)
    var liftFalloff: Double = 1.0
    // --- Queue travel (fan slides as you index forward/back) ---
    /// How much the whole fan translates to follow the indexed card.
    /// 0 = fan stays put, 1 = indexed card is pinned to a fixed screen spot.
    var followFactor: CGFloat = 1.0
    /// Where the indexed card sits horizontally, as a ratio of container width
    var followAnchorX: CGFloat = 0.06
    /// Extra leading travel introduced near the end of the collection so the
    /// final card does not finish against the screen edge or index scrubber.
    var endShiftRatio: CGFloat = 0
    /// Number of final cards across which the end shift eases in.
    var endShiftCardRange: Double = 3

    // --- Layering / depth cues ---
    /// Darkness of the left separation edge (0...1)
    var edgeShadowOpacity: Double = 0.18
    /// Width of the left separation edge in points
    var edgeShadowWidth: CGFloat = 3

    // --- Performance window ---
    /// How many cards render behind the indexed card
    var visibleBehind: Int = 60
    /// How many cards render in front of the indexed card
    var visibleAhead: Int = 40

    // --- Phase 2: dwell focus (desaturate + blur others, show metadata) ---
    /// Enable the dwell focus state
    var focusEnabled: Bool = true
    /// Where the *first* card's bottom edge sits, as a fraction of the view
    /// height measured from the top. Deliberately independent of how many cards
    /// exist, so a 3-album fan lands in exactly the same spot as a 300-album one.
    var queueBaselineY: CGFloat = 0.90
    /// Selected card's leading edge during focus, relative to the view width.
    var focusSelectedX: CGFloat = 0.28
    /// Whether entering focus horizontally recentres the selected card.
    var focusRecenterEnabled: Bool = true
    /// Transient offset used by the host to animate the selected card being
    /// pulled out of the queue. It should settle back to zero.
    var focusExtractionY: CGFloat = 0
    /// Final visual size of the matched-geometry destination.
    var focusScale: CGFloat = 1.12
    /// 0 = compact grid-like entrance layout, 1 = final fan geometry.
    var formationProgress: CGFloat = 1
    /// Grayscale amount applied to non-indexed cards (0...1)
    var focusGrayscale: Double = 1.0
    /// Blur radius applied to non-indexed cards
    var focusBlur: CGFloat = 0
    /// Opacity of non-indexed cards during focus
    var focusDimOpacity: Double = 0.30

}

// MARK: - Fan Card Stack

/// A diagonal fan of cards receding toward the upper-right. The fan itself stays
/// still; the card at `progress` lifts vertically out of the stack — clearing the
/// card in front of it so its full face is revealed. Drive `progress` from a
/// scroll indicator to get a physical index-card scrubbing feel.
struct FanCardStack<Item: Identifiable, Content: View>: View, Animatable {
    @Namespace private var selectionNamespace

    let items: [Item]
    /// 0...1 — fractional position in the collection. Supports smooth scrubbing.
    var progress: Double
    /// Whether the dwell focus state (grayscale others + metadata) is active
    var isFocused: Bool = false
    var config: FanIndexConfig = FanIndexConfig()
    @ViewBuilder let content: (Item) -> Content

    /// Let SwiftUI interpolate the fractional queue position itself. Without
    /// this, a section-index jump swaps the selected identity immediately and
    /// the incoming card appears at full lift instead of inheriting the lift
    /// continuously from its neighbour.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * config.cardWidthRatio
            let cardHeight = cardWidth * config.aspectRatio

            // Fractional index so scrubbing lifts smoothly between neighbours
            let fractionalIndex = progress * Double(max(0, items.count - 1))
            let centerIndex = Int(fractionalIndex.rounded())

            let lower = max(0, centerIndex - config.visibleAhead)
            let upper = min(items.count - 1, centerIndex + config.visibleBehind)

            // Anchor the fan by its first card rather than centring the rendered
            // bounds. Centring made the offset depend on `lower`/`upper`, so the
            // whole queue slid vertically as the collection size (and the visible
            // window) changed — which is why short collections drifted up into
            // the metadata panel. The ZStack is bottom-aligned, so y = 0 is the
            // bottom edge of the frame.
            let queueCenterOffsetY = geo.size.height * (config.queueBaselineY - 1)

            // Let the current card walk through the visible queue first. Only
            // once it reaches the last fully visible slot does the fan travel.
            // The cosine is a close projection of the width after the Y tilt.
            let leadingInset = geo.size.width * config.followAnchorX
            let projectedCardWidth = cardWidth * CGFloat(cos(config.tilt * .pi / 180))
            let availableFanRun = max(0, geo.size.width - leadingInset - projectedCardWidth)
            let visualTailIndex = config.dx > 0 ? floor(availableFanRun / config.dx) : 0
            let overflowIndex = max(0, CGFloat(fractionalIndex) - visualTailIndex)

            // followFactor 0 = fan static, 1 = overflow is fully compensated.
            let travelX = -config.dx * overflowIndex * config.followFactor
            let travelY = -config.dy * overflowIndex * config.followFactor

            // Anticipate the end of the queue rather than moving it only when
            // the final card becomes current. Smoothstep keeps both ends of the
            // compensation at zero velocity, avoiding a visible positional kick.
            let remainingCards = max(0, Double(items.count - 1) - fractionalIndex)
            let endRange = max(0.001, config.endShiftCardRange)
            let endLinearProgress = min(1, max(0, 1 - remainingCards / endRange))
            let endProgress = endLinearProgress * endLinearProgress
                * (3 - 2 * endLinearProgress)
            let endShiftX = -geo.size.width * config.endShiftRatio * CGFloat(endProgress)

            // During focus, bring the selected card back from the visual tail
            // to the reference composition's upper-left focal position.
            let selectedX = leadingInset
                + config.dx * CGFloat(fractionalIndex)
                + travelX
            let focusRecenterX = config.focusEnabled && config.focusRecenterEnabled && isFocused
                ? geo.size.width * config.focusSelectedX - selectedX
                : 0

            let queueWidth = projectedCardWidth + abs(config.dx) * CGFloat(max(0, items.count - 1))
            let centerShortQueue = config.centersShortQueues && queueWidth <= geo.size.width * 0.88
            // Reserve the full lift envelope so the queue stays still as the
            // selection changes, instead of recentering on each lifted card.
            let queueHeight = cardHeight * (1 + config.liftRatio)
                + abs(config.dy) * CGFloat(max(0, items.count - 1))
            let centeredX = (geo.size.width - queueWidth) / 2
            let centeredY = geo.size.height * (0.55 - 1) + queueHeight / 2

            ZStack(alignment: .bottomLeading) {
                if lower <= upper {
                    if config.focusEnabled && isFocused {
                        // Cards behind the selection are flattened separately so
                        // their alpha does not accumulate through the stack.
                        ZStack(alignment: .bottomLeading) {
                            ForEach((centerIndex + 1)..<(upper + 1), id: \.self) { index in
                                let delta = abs(Double(index) - fractionalIndex)
                                let lift = max(0, 1.0 - delta / max(0.001, config.liftFalloff))
                                card(
                                    item: items[index],
                                    index: index,
                                    lift: lift,
                                    width: cardWidth,
                                    height: cardHeight
                                )
                                .zIndex(Double(upper - index))
                            }
                        }
                        .compositingGroup()
                        .grayscale(config.focusGrayscale)
                        .blur(radius: config.focusBlur)
                        .opacity(config.focusDimOpacity)
                        .allowsHitTesting(false)
                        .zIndex(0)

                        // Keep the selected card at exactly its natural fan
                        // position and lift. It is not promoted above neighbours.
                        let selectedDelta = abs(Double(centerIndex) - fractionalIndex)
                        let selectedLift = max(
                            0,
                            1.0 - selectedDelta / max(0.001, config.liftFalloff)
                        )
                        card(
                            item: items[centerIndex],
                            index: centerIndex,
                            lift: selectedLift,
                            width: cardWidth,
                            height: cardHeight
                        )
                        .matchedGeometryEffect(
                            id: items[centerIndex].id,
                            in: selectionNamespace,
                            isSource: false
                        )
                        .zIndex(1)

                        // Earlier cards are naturally in front. Drawing their
                        // flattened translucent layer above the selection keeps
                        // the reference image's partially-obscured effect.
                        ZStack(alignment: .bottomLeading) {
                            ForEach(lower..<centerIndex, id: \.self) { index in
                                let delta = abs(Double(index) - fractionalIndex)
                                let lift = max(0, 1.0 - delta / max(0.001, config.liftFalloff))
                                card(
                                    item: items[index],
                                    index: index,
                                    lift: lift,
                                    width: cardWidth,
                                    height: cardHeight
                                )
                                .zIndex(Double(upper - index))
                            }
                        }
                        .compositingGroup()
                        .grayscale(config.focusGrayscale)
                        .blur(radius: config.focusBlur)
                        .opacity(config.focusDimOpacity)
                        .allowsHitTesting(false)
                        .zIndex(2)
                    } else {
                        ZStack(alignment: .bottomLeading) {
                            ForEach(lower...upper, id: \.self) { index in
                            let delta = abs(Double(index) - fractionalIndex)
                            let lift = max(0, 1.0 - delta / max(0.001, config.liftFalloff))

                                if index == centerIndex {
                                    card(
                                        item: items[index],
                                        index: index,
                                        lift: lift,
                                        width: cardWidth,
                                        height: cardHeight
                                    )
                                    .matchedGeometryEffect(
                                        id: items[index].id,
                                        in: selectionNamespace,
                                        isSource: true
                                    )
                                    .zIndex(Double(upper - index))
                                } else {
                                    card(
                                        item: items[index],
                                        index: index,
                                        lift: lift,
                                        width: cardWidth,
                                        height: cardHeight
                                    )
                                    .zIndex(Double(upper - index))
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .offset(
                x: centerShortQueue ? centeredX : leadingInset + travelX + focusRecenterX + endShiftX,
                y: centerShortQueue ? centeredY : travelY + queueCenterOffsetY
            )
            .animation(
                .spring(response: 0.58, dampingFraction: 0.82),
                value: config.formationProgress
            )
            .animation(
                .interactiveSpring(
                    response: 0.52,
                    dampingFraction: 0.88,
                    blendDuration: 0.22
                ),
                value: isFocused
            )
        }
    }

    // MARK: - Single Card

    private func card(
        item: Item,
        index: Int,
        lift: Double,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        // Position along the fan — this NEVER changes as progress moves
        let fanX = config.dx * CGFloat(index)
        let fanY = config.dy * CGFloat(index)
        let fanScale = max(0.6, 1.0 - config.scaleStep * CGFloat(index))
        let formation = min(1, max(0, config.formationProgress))
        let formationSlot = index % 8
        let gridX = CGFloat(formationSlot % 2) * width * 0.54
        let gridY = -CGFloat(formationSlot / 2) * height * 0.54
        let positionX = gridX + (fanX - gridX) * formation
        let positionY = gridY + (fanY - gridY) * formation
        let formationScale = 0.44 + (fanScale - 0.44) * formation

        // Vertical lift out of the fan — the indexing effect
        // Selection does not alter the card geometry: it keeps exactly the
        // same small indexing lift and angle it had before focus began.
        let liftY = -height * config.liftRatio * CGFloat(lift)
        let liftScale = 1.0 + (config.liftScale - 1.0) * CGFloat(lift)

        return content(item)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
            // Left edge shadow — creates the layered "spine" separation
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [
                        .black.opacity(config.edgeShadowOpacity),
                        .black.opacity(config.edgeShadowOpacity * 0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: config.edgeShadowWidth)
                .allowsHitTesting(false)
            }
            // Hairline top edge suggests paper thickness
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1.5)
                .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(0.14 + 0.08 * lift),
                radius: 2 + config.liftShadowRadius * CGFloat(lift),
                x: 0,
                y: 1 + 2 * CGFloat(lift)
            )
            .rotation3DEffect(
                .degrees(config.tilt),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: config.perspective
            )
            .rotationEffect(.degrees(config.cardAngle))
            .scaleEffect(formationScale * liftScale, anchor: .bottomLeading)
            .offset(x: positionX, y: positionY + liftY * formation)
    }
}

// MARK: - Metadata Panel

/// Right-aligned metadata block that fades in during the dwell focus state.
struct FanMetadataPanel: View {
    let title: String
    let subtitle: String
    let detail: String
    var transitionValue: Double = 0
    var isLeadingAligned: Bool = false
    var showsDetail: Bool = true

    var body: some View {
        VStack(alignment: isLeadingAligned ? .leading : .trailing, spacing: isLeadingAligned ? 6 : 8) {
            Text(title)
                .font(.system(size: isLeadingAligned ? 17 : 14, weight: .bold, design: .serif))
                .tracking(1.5)
                .multilineTextAlignment(isLeadingAligned ? .leading : .trailing)
                .contentTransition(.numericText(value: transitionValue))

            Text(subtitle)
                .font(.system(size: isLeadingAligned ? 12 : 11, weight: isLeadingAligned ? .medium : .regular, design: .monospaced))
                .opacity(isLeadingAligned ? 0.82 : 0.75)
                .contentTransition(.numericText(value: transitionValue))

            if showsDetail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .multilineTextAlignment(isLeadingAligned ? .leading : .trailing)
                    .lineSpacing(3)
                    .opacity(isLeadingAligned ? 0.78 : 0.7)
                    .frame(
                        maxWidth: 240,
                        alignment: isLeadingAligned ? .leading : .trailing
                    )
                    .contentTransition(.numericText(value: transitionValue))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.primary)
        .overlay(alignment: isLeadingAligned ? .leading : .trailing) {
            Rectangle()
                .fill(.primary.opacity(0.5))
                .frame(width: 1)
                .offset(x: isLeadingAligned ? -12 : 12)
        }
        .animation(.easeInOut(duration: 0.28), value: showsDetail)
    }
}

// MARK: - Interactive Demo Harness

/// Wraps `FanCardStack` with a scrub bar and live tuning sliders so the effect
/// can be dialled in before wiring it to a real scroll indicator.
struct FanIndexDemoView: View {
    let items: [DemoFanItem]

    @State private var progress: Double = 0
    @State private var config = FanIndexConfig()
    @State private var showControls = false
    @State private var isFocused = false
    @State private var dwellTask: Task<Void, Never>?

    private var activeItem: DemoFanItem? {
        guard !items.isEmpty else { return nil }
        let idx = Int((progress * Double(items.count - 1)).rounded())
        return items[min(max(0, idx), items.count - 1)]
    }

    var body: some View {
        ZStack {
            Color(white: 0.97).ignoresSafeArea()

            FanCardStack(
                items: items,
                progress: progress,
                isFocused: isFocused,
                config: config
            ) { item in
                item.color
                    .overlay {
                        VStack(spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 10, weight: .bold))
                            Text(item.subtitle)
                                .font(.system(size: 7))
                                .opacity(0.75)
                        }
                        .foregroundStyle(.white)
                        .padding(6)
                    }
            }

            // Phase 2 metadata panel
            if config.focusEnabled, isFocused, let item = activeItem {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FanMetadataPanel(
                            title: item.subtitle.uppercased(),
                            subtitle: "Artist: Unknown",
                            detail: "This iconic 2025 cover stands as a testament to visual excellence, capturing the soul of the city through a sophisticated artistic lens."
                        )
                        .padding(.trailing, 40)
                    }
                }
                .padding(.bottom, 72)
                .transition(.opacity)
            }

            VStack {
                Spacer()
                if showControls {
                    controlPanel
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                scrubBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation { showControls.toggle() }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(20)
        }
    }

    // MARK: Scrub Bar

    private var scrubBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.08)).frame(height: 6)
                Capsule().fill(.black.opacity(0.35))
                    .frame(width: max(6, geo.size.width * progress), height: 6)
                Circle().fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .offset(x: max(0, geo.size.width * progress - 11))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        progress = min(1, max(0, value.location.x / geo.size.width))
                        // Cancel focus while actively scrubbing
                        isFocused = false
                        scheduleDwell()
                    }
                    .onEnded { _ in scheduleDwell() }
            )
        }
        .frame(height: 22)
    }

    /// After the user stops scrubbing for 1.5s, enter the focus state.
    private func scheduleDwell() {
        dwellTask?.cancel()
        guard config.focusEnabled else { return }
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isFocused = true }
        }
    }

    // MARK: Live Tuning Controls

    private var controlPanel: some View {
        VStack(spacing: 5) {
            tuner("dx", $config.dx, 4...36)
            tuner("dy", $config.dy, -20...0)
            tuner("liftRatio", $config.liftRatio, 0...0.8)
            tuner("baselineY", $config.queueBaselineY, 0.5...1.0)
            tuner("focusX", $config.focusSelectedX, 0...0.7)
            tuner("follow", $config.followFactor, 0...1)
            tuner("anchorX", $config.followAnchorX, 0...0.5)
            tuner("tilt", Binding(
                get: { CGFloat(config.tilt) },
                set: { config.tilt = Double($0) }
            ), 0...60)
            tuner("perspective", $config.perspective, 0...0.6)
            tuner("cardAngle", Binding(
                get: { CGFloat(config.cardAngle) },
                set: { config.cardAngle = Double($0) }
            ), -8...8)
            tuner("scaleStep", $config.scaleStep, 0...0.01)
            tuner("cardWidth", $config.cardWidthRatio, 0.15...0.6)
            tuner("aspect", $config.aspectRatio, 0.9...1.7)

            Toggle(isOn: $config.focusEnabled) {
                Text("focus phase")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func tuner(_ label: String, _ value: Binding<CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 46, alignment: .trailing)
        }
    }
}

// MARK: - Demo Item

struct DemoFanItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let color: Color
}

// MARK: - Preview

#Preview("Fan Index — Interactive") {
    let palette: [Color] = [
        .init(red: 0.11, green: 0.13, blue: 0.18),
        .init(red: 0.85, green: 0.31, blue: 0.24),
        .init(red: 0.95, green: 0.87, blue: 0.72),
        .init(red: 0.22, green: 0.45, blue: 0.62),
        .init(red: 0.36, green: 0.55, blue: 0.38),
        .init(red: 0.92, green: 0.66, blue: 0.25),
        .init(red: 0.58, green: 0.34, blue: 0.55),
        .init(red: 0.78, green: 0.78, blue: 0.80),
        .init(red: 0.15, green: 0.32, blue: 0.42),
        .init(red: 0.67, green: 0.24, blue: 0.31)
    ]

    let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                  "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    let items = (0..<52).map { i in
        DemoFanItem(
            title: "ISSUE \(i + 1)",
            subtitle: "\(months[i % 12]) \(i % 28 + 1), 2025",
            color: palette[i % palette.count]
        )
    }

    return FanIndexDemoView(items: items)
}
