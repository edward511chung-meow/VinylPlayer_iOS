import SwiftUI

/// Animated transition: vinyl slides out of album sleeve, cover moves away,
/// vinyl is placed on a turntable platter, tonearm drops, and it starts spinning.
struct VinylSleeveTransition: View {
    let album: Album
    let onComplete: () -> Void

    @State private var phase: TransitionPhase = .sleeve
    @State private var vinylRotation: Double = 0
    @EnvironmentObject var styleManager: StyleManager

    enum TransitionPhase: Equatable {
        case sleeve          // Album cover centered, vinyl hidden behind
        case pullOut         // Vinyl slides out to the right
        case coverAway       // Cover slides off screen left
        case placeOnPlatter  // Vinyl shrinks & moves down onto turntable platter
        case needleDrop      // Tonearm swings onto record, vinyl starts spinning
        case done
    }

    var body: some View {
        ZStack {
            styleManager.theme.backgroundColor
                .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let coverSize: CGFloat = w * 0.6
                let discSize: CGFloat = coverSize * 0.92

                // Turntable platter target position
                let platterCenterX = w * 0.5
                let platterCenterY = h * 0.48
                // Same complete deck as Full Player's centered (no-lyrics) layout.
                let platterSize: CGFloat = w * 0.80
                let layout = TurntableHardwareLayout(
                    recordDiameter: platterSize,
                    baseReferenceSize: w * 0.85,
                    showsLyrics: false
                )

                ZStack {
                    // Layer 0: Turntable base (fades in during placeOnPlatter)
                    ZStack {
                        TurntableBaseView(layout: layout, baseStyle: styleManager.turntableBaseStyle,
                                          isPlaying: ledOn)
                        Circle().fill(Color.black.opacity(0.55))
                            .overlay {
                                Circle().strokeBorder(
                                    LinearGradient(colors: [.black.opacity(0.75), .white.opacity(0.25)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 5)
                            }
                            .frame(width: platterSize + 25, height: platterSize + 25)
                        TurntablePlatterView(recordDiameter: platterSize, showsTransparentRecord: album.usesTransparentVinyl)
                    }
                    .rotationEffect(.degrees(45))
                    .position(x: platterCenterX, y: platterCenterY)
                    .opacity(turntableOpacity)

                    // Layer 1: Vinyl disc
                    VinylDiscView(
                        album: album,
                        size: vinylSize(discSize: discSize, platterSize: platterSize),
                        rotation: vinylRotation + (vinylIsOnPlatter ? 45 : 0),
                        vinylColor: album.selectedEdition?.vinylColor ?? .black,
                        customColorHex: album.customVinylColorHex,
                        discOpacityOverride: album.effectiveVinylOpacity
                    )
                    .shadow(color: .black.opacity(vinylIsOnPlatter ? 0 : 0.4), radius: vinylShadow, y: 4)
                    .position(
                        x: vinylX(w: w, platterCenterX: platterCenterX, discSize: discSize),
                        y: vinylY(h: h, platterCenterY: platterCenterY)
                    )
                    .opacity(phase == .sleeve ? 0 : 1)
                    .zIndex(1)

                    // Layer 2: Album cover (sleeve)
                    AlbumCoverView(album: album, size: coverSize)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                        .position(
                            x: coverX(w: w),
                            y: h * 0.4
                        )
                        .opacity(coverOpacity)
                        .zIndex(2)

                    // Layer 3: Tonearm (appears with turntable, swings down on needleDrop)
                    ZStack {
                        TurntableTonearmView(
                            layout: layout,
                            progress: 0,
                            isLifted: .constant(!ledOn),
                            isParked: !ledOn,
                            tonearmColor: styleManager.theme.tonearmColor,
                            onSeek: { _ in }
                        )
                    }
                    // Rotate around the record center, just as Full Player does.
                    .frame(width: platterSize + 16, height: platterSize + 16)
                    .rotationEffect(.degrees(45))
                    .position(x: platterCenterX, y: platterCenterY)
                    .allowsHitTesting(false)
                    .opacity(turntableOpacity)
                    .zIndex(3)

                    let selectorScale = 0.75 * platterSize / 380
                    TurntableSelectorControls(
                        isPlaying: ledOn,
                        rpm: album.selectedEdition?.format.rpm ?? AppConstants.rpm33,
                        onTogglePlayback: {}, onToggleSpeed: {}
                    )
                    .frame(width: 168, height: 48)
                    .scaleEffect(selectorScale)
                    .position(x: 84 * selectorScale, y: platterCenterY + platterSize * 0.49)
                    .allowsHitTesting(false)
                    .opacity(turntableOpacity)
                    .zIndex(3)
                }
            }
        }
        .onAppear {
            startAnimation()
        }
    }


    // MARK: - Computed Positions

    private func vinylX(w: CGFloat, platterCenterX: CGFloat, discSize: CGFloat) -> CGFloat {
        switch phase {
        case .sleeve:
            return w / 2
        case .pullOut:
            return w / 2 + discSize * 0.45
        case .coverAway:
            return w / 2 + discSize * 0.45
        case .placeOnPlatter, .needleDrop, .done:
            return platterCenterX
        }
    }

    private func vinylY(h: CGFloat, platterCenterY: CGFloat) -> CGFloat {
        switch phase {
        case .sleeve, .pullOut, .coverAway:
            return h * 0.4
        case .placeOnPlatter, .needleDrop, .done:
            return platterCenterY
        }
    }

    private func vinylSize(discSize: CGFloat, platterSize: CGFloat) -> CGFloat {
        switch phase {
        case .sleeve, .pullOut, .coverAway:
            return discSize
        case .placeOnPlatter, .needleDrop, .done:
            return platterSize
        }
    }

    private func coverX(w: CGFloat) -> CGFloat {
        switch phase {
        case .sleeve, .pullOut:
            return w / 2
        case .coverAway, .placeOnPlatter, .needleDrop, .done:
            return -w * 0.4  // Off screen left
        }
    }

    private var coverOpacity: Double {
        switch phase {
        case .sleeve, .pullOut: return 1
        case .coverAway: return 0.8
        default: return 0
        }
    }

    private var turntableOpacity: Double {
        switch phase {
        case .sleeve, .pullOut: return 0
        case .coverAway: return 0.5
        case .placeOnPlatter, .needleDrop, .done: return 1
        }
    }

    private var vinylShadow: CGFloat {
        switch phase {
        case .sleeve, .pullOut, .coverAway: return 12
        case .placeOnPlatter, .needleDrop, .done: return 2
        }
    }

    private var ledOn: Bool {
        phase == .needleDrop || phase == .done
    }

    private var vinylIsOnPlatter: Bool {
        phase == .placeOnPlatter || phase == .needleDrop || phase == .done
    }

    // MARK: - Animation Sequence

    private func startAnimation() {
        // Phase 1: Vinyl slides out from behind cover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.5)) {
                phase = .pullOut
            }
        }

        // Phase 2: Cover slides away to the left
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                phase = .coverAway
            }
        }

        // Phase 3: Turntable appears, vinyl moves down onto platter
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                phase = .placeOnPlatter
            }
        }

        // Phase 4: Tonearm swings toward record
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            withAnimation(.interpolatingSpring(stiffness: 40, damping: 10)) {
                phase = .needleDrop
            }
        }

        // Phase 4b: Needle lands on vinyl — sound + spin after arm reaches record (~0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            VinylSoundEngine.shared.playNeedleDrop()
            startSpinning()
        }

        // Phase 5: Complete (after needle lands + brief spin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
            phase = .done
            onComplete()
        }
    }

    private func startSpinning() {
        // Gradual spin-up using a timer
        let rpm = 33.33
        let degreesPerSecond = (rpm * 360.0) / 60.0
        var speed: Double = 0
        let startDate = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / Double(UIScreen.main.maximumFramesPerSecond), repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startDate)

            // Spin up over 1 second
            speed = min(1.0, elapsed / 1.0)
            vinylRotation += degreesPerSecond * speed * (1.0 / Double(UIScreen.main.maximumFramesPerSecond))

            // Stop timer after transition completes
            if phase == .done {
                timer.invalidate()
            }
        }
    }
}
