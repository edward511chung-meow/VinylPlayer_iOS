//
//  CoverFlow.swift
//  VinylPlayer
//
//  Created by Edward Chung on 27/6/2026.
//

import SwiftUI

struct CoverFlowConfig {
    var cardWidth: CGFloat
    var rotation: CGFloat = 58
    var offsetFactor: CGFloat = 1.4
    var activeElevation: CGFloat = 0

    /// Reflection Properties
    var reflectionGap: CGFloat = 1.6
    var reflectionFade: CGFloat = 4
    var reflectionDim: CGFloat = 0.8
}

struct CoverFlow<Content: View, BackContent: View>: View {
    @EnvironmentObject private var styleManager: StyleManager

    var config: CoverFlowConfig
    @Binding var activeIndex: Int?
    @Binding var flipTrigger: Int
    var content: Content
    var backContentBuilder: ((Int) -> BackContent)?
    var onFlipChanged: ((Bool) -> Void)?
    var onOpenAlbum: ((Int, CGRect) -> Void)?
    @State private var containerFrame: CGRect = .zero

    @State private var flippedIndex: Int?
    @State private var flipAngle: Double = 0

    // MARK: - Init with back content (flip support)

    init(config: CoverFlowConfig, activeIndex: Binding<Int?>, flipTrigger: Binding<Int>, onFlipChanged: ((Bool) -> Void)? = nil, onOpenAlbum: ((Int, CGRect) -> Void)? = nil, @ViewBuilder content: () -> Content, @ViewBuilder backContent: @escaping (Int) -> BackContent) {
        self.config = config
        self._activeIndex = activeIndex
        self._flipTrigger = flipTrigger
        self.onFlipChanged = onFlipChanged
        self.onOpenAlbum = onOpenAlbum
        self.content = content()
        self.backContentBuilder = backContent
    }

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let currentIndex = activeIndex ?? 0
            let centerOffsetY = UIScreen.main.bounds.height / 2 - geo.frame(in: .global).midY

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    Group(subviews: content) { collection in
                        ForEach(collection.indices, id: \.self) { index in
                            let subview = collection[index]
                            let zIndex = currentIndex > index ? Double(index) : Double(-index)
                            let isFlipped = flippedIndex == index

                            cardContainer(subview: subview, index: index, isFlipped: isFlipped, containerSize: containerSize)
                                .zIndex(currentIndex == index ? 1000 : zIndex)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { containerFrame = $0 }
            .scrollIndicators(.hidden)
            /// Start and end at center
            .safeAreaPadding(.horizontal, (containerSize.width - config.cardWidth) / 2)
            .scrollPosition(id: $activeIndex, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onAppear {
                // HapticManager.shared.prepare(styleManager.hapticIntensity)
            }
            .onChange(of: activeIndex) { oldValue, newValue in
                guard oldValue != newValue, newValue != nil else { return }
                resetFlip()
                HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                HapticManager.shared.prepare(styleManager.hapticIntensity)
            }
            .onChange(of: flipTrigger) { _, _ in
                guard let index = activeIndex else { return }
                toggleFlip(index: index)
            }
            // MARK: - Back content overlay (outside shader, doesn't affect ScrollView layout)
            .overlay {
                backContentOverlay(centerOffsetY: centerOffsetY)
            }
        }
    }

    // MARK: - Back Content Overlay

    @ViewBuilder
    private func backContentOverlay(centerOffsetY: CGFloat) -> some View {
        if let flippedIndex, let backContentBuilder {
            let screenBounds = UIScreen.main.bounds
            let backWidth = screenBounds.width * 0.6
            let backHeight = screenBounds.height * 0.88
            let isShowingBack = abs(flipAngle) >= 90

            ZStack {
                // Full-screen dismiss tap area (behind back content)
                Color.black.opacity(0.001)
                    .frame(width: screenBounds.width, height: screenBounds.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleFlip(index: flippedIndex)
                    }

                // Back content
                backContentBuilder(flippedIndex)
                    .frame(width: backWidth, height: backHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotation3DEffect(
                        .degrees(-180 + flipAngle),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.4
                    )
                    .shadow(
                        color: .black.opacity(isShowingBack ? 0.5 : 0),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleFlip(index: flippedIndex)
                    }
            }
            .offset(y: centerOffsetY)
            .opacity(isShowingBack ? 1 : 0)
            .allowsHitTesting(isShowingBack)
        }
    }

    // MARK: - Card Container

    @ViewBuilder
    private func cardContainer(subview: some View, index: Int, isFlipped: Bool, containerSize: CGSize) -> some View {
        let card = flipCardWrapper(subview: subview, index: index, isFlipped: isFlipped, containerSize: containerSize)
            .frame(width: config.cardWidth, height: containerSize.height)
            .visualEffect { [config] content, proxy in
                let values = retriveLayoutAdjustmentValue(proxy, config: config)

                let minGap: CGFloat = 0.8
                let distanceFromCenter = abs(values.progress)
                let centerAmount = 1 - min(1, distanceFromCenter)
                let easedAmount = centerAmount * centerAmount * (3 - 2 * centerAmount)

                let reflectionGap = minGap + (config.reflectionGap - minGap) * easedAmount

                let maxScale: CGFloat = 1.16
                let scale = 1.0 + (maxScale - 1.0) * easedAmount

                return content
                    .layerEffect(
                        ShaderLibrary.coverflowReflection(
                            .float(proxy.size.height),
                            .float(reflectionGap),
                            .float(config.reflectionFade),
                            .float(config.reflectionDim)
                        ),
                        maxSampleOffset: proxy.size
                    )
                    .scaleEffect(scale)
                    .rotation3DEffect(
                        .init(degrees: values.rotation),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: values.anchor,
                        anchorZ: values.anchorZ,
                        perspective: 1
                    )
                    .offset(x: values.offset)
            }

        if backContentBuilder != nil {
            card
                .contentShape(Rectangle())
                .onTapGesture {
                    if activeIndex == index {
                        toggleFlip(index: index)
                    } else {
                        withAnimation(.smooth) {
                            activeIndex = index
                        }
                    }
                }
        } else {
            card
        }
    }

    // MARK: - Flip Card Wrapper (front only)

    @ViewBuilder
    private func flipCardWrapper(subview: some View, index: Int, isFlipped: Bool, containerSize: CGSize) -> some View {
        if onOpenAlbum != nil {
            // The external flip host uses the same single shadow as this source.
            subview
        } else if backContentBuilder != nil {
            subview
//                .overlay(content: {
//                    Text("\(flipAngle)")
//                })
                .rotation3DEffect(
                    .degrees(isFlipped ? flipAngle : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.4
                )
                .opacity(isFlipped && abs(flipAngle) >= 90 ? 0 : 1)
                .shadow(
                    color: .black.opacity(isFlipped && abs(flipAngle) > 10 && abs(flipAngle) < 90 ? 0.5 : 0.3),
                    radius: isFlipped && abs(flipAngle) > 10 && abs(flipAngle) < 90 ? 20 : 8,
                    x: 8,
                    y: 8
                )
        } else {
            subview
        }
    }

    // MARK: - Flip Logic

    private func toggleFlip(index: Int) {
        if let onOpenAlbum {
            let side = config.cardWidth * 1.16 // The centered card's existing visual scale.
            let frame = CGRect(x: containerFrame.midX - side / 2,
                               y: containerFrame.midY - side / 2, width: side, height: side)
            onOpenAlbum(index, frame)
            return
        }
        if flippedIndex == index {
            // Unflip
            onFlipChanged?(false)
            withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.95)) {
                flipAngle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                flippedIndex = nil
            }
        } else {
            // Flip to back
            onFlipChanged?(true)
            if flippedIndex != nil {
                // Reset current flip first
                withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.95)) {
                    flipAngle = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    flippedIndex = index
                    withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.95)) {
                        flipAngle = -180
                    }
                }
            } else {
                flippedIndex = index
                flipAngle = 0
                withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.95)) {
                    flipAngle = -180
                }
            }
        }
        HapticManager.shared.selectionTick(styleManager.hapticIntensity)
    }

    private func resetFlip() {
        guard flippedIndex != nil else { return }
        onFlipChanged?(false)
        withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.95)) {
            flipAngle = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            flippedIndex = nil
        }
    }

    nonisolated
    private func retriveLayoutAdjustmentValue(
        _ proxy: GeometryProxy,
        config: CoverFlowConfig
    ) -> (rotation: CGFloat, anchor: UnitPoint, anchorZ: CGFloat, offset: CGFloat, progress: CGFloat) {
        let minX = proxy.frame(in: .scrollView(axis: .horizontal)).minX
        let progress = minX / config.cardWidth
        ///  Capping Progress between -1 to 1
        let cappedProgress = max(-1, min(1, progress))

        let rotation = -cappedProgress * config.rotation
        let offset = -progress * (config.cardWidth / config.offsetFactor)
        let anchor: UnitPoint = cappedProgress < 0 ? .leading : .trailing
        let anchorZ = abs(cappedProgress) * config.activeElevation

        return (rotation, anchor, anchorZ, offset, cappedProgress)
    }
}

// MARK: - Backward-compatible init (no flip)

extension CoverFlow where BackContent == EmptyView {
    init(config: CoverFlowConfig, activeIndex: Binding<Int?>, @ViewBuilder content: () -> Content) {
        self.config = config
        self._activeIndex = activeIndex
        self._flipTrigger = .constant(0)
        self.content = content()
        self.backContentBuilder = nil
    }
}

#Preview {
    CoverFlowTesting()
        .environmentObject(StyleManager())
        .preferredColorScheme(.dark)
}
