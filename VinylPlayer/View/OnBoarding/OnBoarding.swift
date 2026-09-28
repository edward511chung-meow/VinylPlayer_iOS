//
//  OnBoardingView.swift
//  VinylPlayer
//
//  Created by Edward Chung on 2/8/2026.
//

import SwiftUI

struct OnBoarding: View {
    var tint: Color = .blue
    var hideBezels: Bool = false
    var items: [Item]
    var onComplete: () -> ()
    
    // View Properties
    @State private var currentIndex: Int = 0
    @State private var turnRotation: Double = 0
    @State private var turnScale: CGFloat = 1
    @State private var turnContentOpacity: Double = 1
    @State private var isTurningDevice = false
    @State private var screenshotSizes: [Int: CGSize] = [:]

    private var screenshotSize: CGSize {
        screenshotSizes[currentIndex] ?? .zero
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenshotView()
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale * turnScale,
                    anchor: isTurningDevice
                        ? items[currentIndex].turnAnchor
                        : items[currentIndex].zoomAnchor
                )
                .rotationEffect(.degrees(turnRotation))
                .opacity(turnContentOpacity)
                .padding(.top, 35)
                .padding(.horizontal, 30)
                .padding(.bottom, 220)
            
            VStack(spacing: 10) {
                TextContentView()
                
                IndicatorView()
                
                ContinueButton()
            }
            .padding(.top, 20)
            .padding(.horizontal, 15)
            .frame(height: 210)
            .background {
                VariableGlassBlur(18)
            }
            
            BackButton()
        }
        .preferredColorScheme(.dark)
    }
    
    // Screenshot View
    @ViewBuilder
    func ScreenshotView() -> some View {
        let shape = ConcentricRectangle(corners: .concentric, isUniform: true)
        
        GeometryReader {
            let size = $0.size
            
            Rectangle()
                .fill(.black)
            
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        
                        Group {
                            if let content = item.content {
                                content
                                    .frame(width: size.width, height: size.height)
                            } else if let screenshot = item.screenshot {
                                Image(uiImage: screenshot)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .onGeometryChange(for: CGSize.self) {
                                        $0.size
                                    } action: { newValue in
                                        let previousSize = screenshotSizes[index] ?? .zero
                                        let previousArea = previousSize.width * previousSize.height
                                        let newArea = newValue.width * newValue.height

                                        if newArea > previousArea {
                                            screenshotSizes[index] = newValue
                                        }
                                    }
                                    .clipShape(shape)
                            } else {
                                Rectangle()
                                    .fill(.black)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: .init(get: {
                currentIndex
            }, set: { _ in }))
        }
        .clipShape(shape)
        .overlay {
            if screenshotSize != .zero && !hideBezels {
                ZStack {
                    shape.stroke(.white, lineWidth: 4)
                    shape.stroke(.black, lineWidth: 2)
                    shape.stroke(.black, lineWidth: 4).padding(2)
                }
                .padding(-5)
            }
        }
        .frame(
            maxWidth: screenshotSize.width == 0 ? nil : screenshotSize.width,
            maxHeight: screenshotSize.height == 0 ? nil : screenshotSize.height
        )
        .containerShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Text Content View
    @ViewBuilder
    func TextContentView() -> some View {
        GeometryReader {
            let size = $0.size
            
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let isActive = currentIndex == index
                        
                        VStack(spacing: 6) {
                            Text(item.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            
                            Text(item.subtitle)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: size.width)
                        .compositingGroup()
                        // Only the current item is visible, others are blurred out
                        .blur(radius: isActive ? 0 : 30)
                        .opacity(isActive ? 1 : 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .scrollTargetBehavior(.paging)
            .scrollClipDisabled()
            .scrollPosition(id: .init(get: {
                currentIndex
            }, set: { _ in }))
        }
    }
    
    // Indicator View
    @ViewBuilder
    func IndicatorView() -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive: Bool = currentIndex == index
                
                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.4))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, 5)
    }
    
    // Bottom Continue Button
    @ViewBuilder
    func ContinueButton() -> some View {
        Button {
            moveForward()
        } label: {
            Text(currentIndex == items.count - 1 ? "Get Started" : "Continue")
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .padding(.vertical, 6)
        }
        .tint(tint)
        .buttonStyle(.glassProminent)
        .buttonSizing(.flexible)
        .padding(.horizontal, 30)
        .disabled(isTurningDevice)
//            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    
    /// Back Button
    @ViewBuilder
    func BackButton() -> some View {
        Button {
            moveBackward()
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .frame(width: 20, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 15)
        .padding(.top, 5)
        .disabled(isTurningDevice)
    }

    private func moveForward() {
        guard !isTurningDevice else { return }

        guard currentIndex < items.count - 1 else {
            onComplete()
            return
        }

        let item = items[currentIndex]
        guard item.turnsToNext else {
            withAnimation(animation) {
                currentIndex += 1
            }
            return
        }

        isTurningDevice = true
        withAnimation(orientationAnimation) {
            turnRotation = 45
            turnScale = item.turnScale
            turnContentOpacity = 0.65
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.28))

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentIndex += 1
                turnRotation = -45
                turnScale = item.turnScale / items[currentIndex].zoomScale
            }

            withAnimation(orientationAnimation) {
                turnRotation = 0
                turnScale = 1
                turnContentOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.28))
            isTurningDevice = false
        }
    }

    private func moveBackward() {
        guard !isTurningDevice, currentIndex > 0 else { return }

        let previousItem = items[currentIndex - 1]
        guard previousItem.turnsToNext else {
            withAnimation(animation) {
                currentIndex -= 1
            }
            return
        }

        isTurningDevice = true
        let currentItem = items[currentIndex]
        withAnimation(orientationAnimation) {
            turnRotation = -45
            turnScale = previousItem.turnScale / currentItem.zoomScale
            turnContentOpacity = 0.65
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.28))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentIndex -= 1
                turnRotation = 45
                turnScale = previousItem.turnScale
            }

            withAnimation(orientationAnimation) {
                turnRotation = 0
                turnScale = 1
                turnContentOpacity = 1
            }
            try? await Task.sleep(for: .seconds(0.28))
            isTurningDevice = false
        }
    }
    
    // Variable Glass Effect Blur
    @ViewBuilder
    func VariableGlassBlur(_ radius: CGFloat) -> some View {
        let tint: Color = .black.opacity(0.5)
        
        Rectangle()
            .fill(.clear)
            .glassEffect(.clear.tint(tint), in: .rect)
            .padding([.horizontal, .bottom], -radius * 2)
            // OPTIONAL:
            // Only visible for scaled screenshots
            .opacity(items[currentIndex].zoomScale != 1 ? 1 : 0)
            .ignoresSafeArea()
    }
    
    // Customize it according to your need!
    var animation: Animation {
        .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }

    var orientationAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    var deviceCornerRadius: CGFloat {
        guard let imageSize = items[currentIndex].screenshot?.size,
              imageSize.height > 0 else {
            return 47
        }

        let ratio = screenshotSize.height / imageSize.height
        let baseCornerRadius: CGFloat = imageSize.height > 1000 ? 160 : 53
        return min(baseCornerRadius * ratio, screenshotSize.width / 4)
    }
    
    struct Item: Identifiable {
        var id: Int
        var title: String
        var subtitle: String
        var screenshot: UIImage?
        var content: AnyView? = nil
        var zoomScale: CGFloat = 1
        var zoomAnchor: UnitPoint = .center
        var turnsToNext: Bool = false
        var turnScale: CGFloat = 0.72
        var turnAnchor: UnitPoint = .center
    }
}

#Preview {
    TestOnBoardingView()
}
