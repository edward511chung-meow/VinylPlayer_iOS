import SwiftUI
import Photos

struct ShareSheetView: View {
    let data: ShareCardData
    @State private var selectedStyle: ShareCardStyle = .vinylCover
    @State private var renderedImage: UIImage?
    @State private var showActivitySheet = false
    @State private var showVideoActivitySheet = false
    @State private var savedStyles: Set<ShareCardStyle> = []
    @State private var isSaving: Bool = false
    @State private var saveBounce: Bool = false
    @State private var showToast: Bool = false
    @State private var showResaveAlert: Bool = false
    @State private var showCustomization: Bool = false
    @State private var isRenderingVideo: Bool = false
    @State private var videoProgress: Double = 0
    @State private var renderedVideoURL: URL?
    @StateObject private var customization = ShareCustomization()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var styleManager: StyleManager

    /// Whether the current style has been saved
    private var isCurrentStyleSaved: Bool {
        savedStyles.contains(selectedStyle)
    }

    /// Available styles — hide lyricsPlayer when no lyrics data
    private var availableStyles: [ShareCardStyle] {
        data.hasLyrics ? ShareCardStyle.allCases : [.vinylCover, .turntable]
    }

    var body: some View {
        ZStack {
            // Background — plain light/dark
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, showCustomization ? 4 : 16)

                // Card preview — swipeable if multiple styles
                if availableStyles.count > 1 {
                    TabView(selection: $selectedStyle) {
                        ForEach(availableStyles) { style in
                            cardPreview(style: style)
                                .tag(style)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: selectedStyle)

                    // Interactive page dots — tap or long-press drag to switch
                    StyleDotSelector(
                        styles: availableStyles,
                        selectedStyle: $selectedStyle
                    )
                    .padding(.top, 8)
                } else {
                    cardPreview(style: .vinylCover)
                    Spacer().frame(height: 16)
                }

                Spacer(minLength: 12)

                // Share destinations
                HStack(spacing: 24) {
                    // Customize
                    shareCircle(
                        icon: "slider.horizontal.3",
                        label: L("share.customize"),
                        background: AnyShapeStyle(Color.primary.opacity(0.1))
                    ) {
                        showCustomization = true
                    }

                    // Video (for lyrics cards with synced lyrics)
                    if (selectedStyle == .lyricsPlayer || selectedStyle == .rippleLyrics) && data.hasSyncedLyrics {
                        shareCircle(
                            icon: "video.fill",
                            label: L("share.video"),
                            background: AnyShapeStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                            iconColor: .white
                        ) {
                            renderVideo()
                        }
                    }

                    // Stories
                    shareCircle(
                        icon: "camera.fill",
                        label: "Stories",
                        background: AnyShapeStyle(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        ),
                        iconColor: .white
                    ) {
                        shareToInstagramStory()
                    }

                    // Save
                    saveButton

                    // More
                    shareCircle(
                        icon: "ellipsis",
                        label: L("share.more"),
                        background: AnyShapeStyle(Color.primary.opacity(0.1))
                    ) {
                        renderAndShare()
                    }
                }
                .padding(.bottom, 32)
            }
            .offset(y: showCustomization ? -80 : 0)
        }
        // Saving / rendering overlay
        .overlay {
            if isSaving || isRenderingVideo {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        if isRenderingVideo {
                            ProgressView(value: videoProgress)
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                                .tint(.white)
                        } else {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                        }

                        Text(isRenderingVideo ? L("share.rendering_video") : L("share.saving"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)

                        if isRenderingVideo {
                            Text("\(Int(videoProgress * 100))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.8))
                            .environment(\.colorScheme, .dark)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSaving)
        .animation(.easeInOut(duration: 0.2), value: isRenderingVideo)
        .animation(.easeInOut(duration: 0.25), value: showCustomization)
        // Success toast
        .overlay(alignment: .top) {
            if showToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.green)

                    Text(L("share.saved_to_photos"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                )
                .padding(.top, 50)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .sheet(isPresented: $showActivitySheet) {
            if let image = renderedImage {
                ActivityViewController(activityItems: [image])
            }
        }
        .sheet(isPresented: $showVideoActivitySheet) {
            if let url = renderedVideoURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .sheet(isPresented: $showCustomization) {
            ShareCustomizationSheet(customization: customization, hasLyrics: data.hasLyrics)
        }
        .alert(L("share.resave_title"), isPresented: $showResaveAlert) {
            Button(L("share.resave_confirm"), role: nil) {
                saveToPhotos()
            }
            Button(L("share.resave_cancel"), role: .cancel) {}
        } message: {
            Text(L("share.resave_message"))
        }
    }

    // MARK: - Card Preview

    private func cardPreview(style: ShareCardStyle) -> some View {
        let baseW: CGFloat = 360
        let baseH: CGFloat = style.cardHeight
        let cs = customization.cardScale
        let scaledW = baseW * cs
        let scaledH = baseH * cs

        return GeometryReader { geo in
            let maxW = geo.size.width - 48
            let maxH = geo.size.height - 16
            let previewScale = min(min(1, maxW / scaledW), min(1, maxH / scaledH))

            ShareCardView(data: data, style: style, customization: customization)
                .frame(width: baseW, height: baseH)
                .scaleEffect(cs, anchor: .center)
                .frame(width: scaledW, height: scaledH)
                .clipShape(RoundedRectangle(cornerRadius: 16 * cs, style: .continuous))
                .scaleEffect(previewScale, anchor: .center)
                .frame(width: scaledW * previewScale, height: scaledH * previewScale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Share Circle Button

    private func shareCircle(
        icon: String,
        label: String,
        background: AnyShapeStyle,
        iconColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(background)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor ?? .primary)
                }

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Save Button (Threads/X style)

    private var saveButton: some View {
        Button {
            if isCurrentStyleSaved {
                showResaveAlert = true
            } else {
                saveToPhotos()
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isCurrentStyleSaved
                                ? Color.green.opacity(0.3)
                                : Color.primary.opacity(0.1)
                        )
                        .frame(width: 56, height: 56)

                    if isCurrentStyleSaved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.primary)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isCurrentStyleSaved)
                .scaleEffect(saveBounce ? 1.25 : 1.0)
                .animation(.interpolatingSpring(stiffness: 400, damping: 10), value: saveBounce)

                Text(L("share.save"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .disabled(isSaving)
    }

    // MARK: - Render Card to Image

    private func renderCardImage() -> UIImage? {
        let baseW: CGFloat = 360
        let baseH: CGFloat = selectedStyle.cardHeight
        let cs = customization.cardScale

        let renderer = ImageRenderer(
            content: ShareCardView(data: data, style: selectedStyle, customization: customization)
                .frame(width: baseW, height: baseH)
                .scaleEffect(cs, anchor: .topLeading)
                .frame(width: baseW * cs, height: baseH * cs)
                .clipShape(RoundedRectangle(cornerRadius: 16 * cs, style: .continuous))
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }

    // MARK: - Share Actions

    private func renderAndShare() {
        guard let image = renderCardImage() else { return }
        renderedImage = image
        showActivitySheet = true
    }

    private func renderVideo() {
        guard !isRenderingVideo else { return }
        isRenderingVideo = true
        videoProgress = 0

        Task {
            do {
                let url = try await ShareVideoRenderer.render(
                    data: data,
                    style: selectedStyle,
                    customization: customization
                ) { progress in
                    Task { @MainActor in
                        videoProgress = progress
                    }
                }
                renderedVideoURL = url
                isRenderingVideo = false
                showVideoActivitySheet = true
            } catch {
                isRenderingVideo = false
                print("[ShareVideo] Render failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveToPhotos() {
        guard let image = renderCardImage() else { return }
        let styleBeingSaved = selectedStyle
        isSaving = true

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { isSaving = false }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: image.pngData()!, options: nil)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    isSaving = false

                    if success {
                        // Mark this style as saved
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            savedStyles.insert(styleBeingSaved)
                        }

                        // Bounce animation
                        saveBounce = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            saveBounce = false
                        }

                        // Haptic
                        UINotificationFeedbackGenerator().notificationOccurred(.success)

                        // Toast
                        withAnimation(.easeOut(duration: 0.3)) {
                            showToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeIn(duration: 0.3)) {
                                showToast = false
                            }
                        }
                    }
                }
            }
        }
    }

    /// Render a blurred album art background for IG Stories
    private func renderStoryBackground() -> Data? {
        let storyW: CGFloat = 1080
        let storyH: CGFloat = 1920
        let renderer = ImageRenderer(
            content: ZStack {
                if let img = data.coverImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: storyW / 3, height: storyH / 3)
                        .blur(radius: 50)
                        .overlay(Color.black.opacity(0.4))
                } else {
                    LinearGradient(
                        colors: [data.accentColor, data.accentColor.opacity(0.3), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: storyW / 3, height: storyH / 3)
        )
        renderer.scale = 3.0
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }

    private func shareToInstagramStory() {
        guard let image = renderCardImage(),
              let stickerData = image.pngData() else { return }

        let bundleId = Bundle.main.bundleIdentifier ?? ""

        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleId)"),
              UIApplication.shared.canOpenURL(URL(string: "instagram-stories://share")!) else {
            renderedImage = image
            showActivitySheet = true
            return
        }

        var items: [String: Any] = [
            "com.instagram.sharedSticker.stickerImage": stickerData
        ]

        // Add blurred album art as background if available
        if let bgData = renderStoryBackground() {
            items["com.instagram.sharedSticker.backgroundImage"] = bgData
        } else {
            items["com.instagram.sharedSticker.backgroundTopColor"] = "#000000"
            items["com.instagram.sharedSticker.backgroundBottomColor"] = "#000000"
        }

        let pasteboardItems: [[String: Any]] = [items]
        let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]

        UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)
        UIApplication.shared.open(url)
    }
}

// MARK: - Interactive Dot Selector (tap + long-press drag)

struct StyleDotSelector: View {
    let styles: [ShareCardStyle]
    @Binding var selectedStyle: ShareCardStyle

    @State private var isDragging = false
    @GestureState private var dragLocation: CGPoint = .zero

    private let dotSize: CGFloat = 7
    private let expandedDotSize: CGFloat = 10
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(styles.enumerated()), id: \.element.id) { _, style in
                let isSelected = selectedStyle == style

                Circle()
                    .fill(isSelected
                        ? Color.primary
                        : Color.primary.opacity(0.25))
                    .frame(
                        width: isDragging && isSelected ? expandedDotSize : dotSize,
                        height: isDragging && isSelected ? expandedDotSize : dotSize
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStyle = style
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .opacity(isDragging ? 1 : 0)
        )
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: selectedStyle)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDragging = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                .sequenced(before:
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isDragging else { return }
                            let totalWidth = CGFloat(styles.count - 1) * (dotSize + spacing)
                            let startX = -totalWidth / 2
                            let x = value.location.x - totalWidth / 2 - dotSize / 2

                            var closestIdx = 0
                            var closestDist: CGFloat = .infinity
                            for i in 0..<styles.count {
                                let dotX = startX + CGFloat(i) * (dotSize + spacing)
                                let dist = abs(x - dotX)
                                if dist < closestDist {
                                    closestDist = dist
                                    closestIdx = i
                                }
                            }

                            if styles[closestIdx] != selectedStyle {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedStyle = styles[closestIdx]
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDragging = false
                            }
                        }
                )
        )
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mock Cover Image Helper (Preview only)

private func mockShareCoverImage(color: UIColor = .systemIndigo, size: CGFloat = 360) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(0.2).cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.3).cgColor
            ] as CFArray,
            locations: [0, 0.4, 1]
        )!
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: size, y: size),
            options: []
        )

        // Vinyl circle
        let circleSize: CGFloat = size * 0.4
        let circleRect = CGRect(
            x: (size - circleSize) / 2,
            y: (size - circleSize) / 2,
            width: circleSize,
            height: circleSize
        )
        UIColor.white.withAlphaComponent(0.15).setFill()
        ctx.cgContext.fillEllipse(in: circleRect)

        let innerSize: CGFloat = circleSize * 0.25
        let innerRect = CGRect(
            x: (size - innerSize) / 2,
            y: (size - innerSize) / 2,
            width: innerSize,
            height: innerSize
        )
        UIColor.white.withAlphaComponent(0.25).setFill()
        ctx.cgContext.fillEllipse(in: innerRect)
    }
}

// MARK: - Preview

// #Preview("Share Sheet — with lyrics") {
//     let mockData = ShareCardData(
//         albumTitle: "Kind of Blue",
//         artist: "Miles Davis",
//         trackTitle: "So What",
//         coverImage: mockShareCoverImage(color: .systemBlue),
//         accentColor: .blue,
//         year: 1959,
//         lyrics: [
//             "Instrumental passage one",
//             "The trumpet sings softly",
//             "Bass walks a steady line",
//             "Piano comps in modal space",
//             "Drums brush the snare gently"
//         ],
//         currentLyricIndex: 1,
//         baseStyle: .darkWalnut
//     )

//     Color.clear
//         .sheet(isPresented: .constant(true)) {
//             ShareSheetView(data: mockData)
//                 .environmentObject(StyleManager())
//         }
//         .preferredColorScheme(.dark)
// }

// #Preview("Share Sheet — no lyrics") {
//     let mockData = ShareCardData(
//         albumTitle: "Abbey Road",
//         artist: "The Beatles",
//         trackTitle: "Come Together",
//         coverImage: mockShareCoverImage(color: UIColor(red: 0.18, green: 0.35, blue: 0.24, alpha: 1)),
//         accentColor: Color(hex: "#2E5A3C") ?? .green,
//         year: 1969,
//         lyrics: nil,
//         currentLyricIndex: nil,
//         baseStyle: .lightOak
//     )

//     Color.clear
//         .sheet(isPresented: .constant(true)) {
//             ShareSheetView(data: mockData)
//                 .environmentObject(StyleManager())
//         }
//         .preferredColorScheme(.dark)
// }
