import SwiftUI
import SwiftData
import ScreenCorners

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var selectedTab: AppTab = .home

    @State private var playerExpanded: Bool = false
    @State private var playerCornerRadius: CGFloat = UIScreen.main.displayCornerRadius

    /// Track landscape state reactively
    @State private var isLandscape = false

    /// Cover Flow tip — shown once on first launch
    @AppStorage("hasShownCoverFlowTip") private var hasShownCoverFlowTip = false
    @State private var showCoverFlowTip = false

    /// Onboarding — shown on first launch
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: AppConstants.StorageKeys.hasCompletedOnboarding)

    /// Scene phase for save-on-background
    @Environment(\.scenePhase) private var scenePhase

    /// Standard tab bar height
    private let tabBarHeight: CGFloat = 48

    /// Mini player bottom padding (stable, excludes keyboard)
    private var miniPlayerBottomPad: CGFloat {
        tabBarHeight + windowBottomInset + 8
    }

    @Namespace var playerAnimation

    var body: some View {
        GeometryReader { geo in
            let isImmersiveCollectionOverlay = collectionVM.isAlbumDetailPresented
            let shouldHideTabBar = (isLandscape && selectedTab == .collection) || isImmersiveCollectionOverlay

            ZStack(alignment: .bottom) {
                // Main tab content
                AnimatedTabView(selection: $selectedTab, tintColor: styleManager.theme.accentColor) {
                    Tab(AppTab.home.title, systemImage: AppTab.home.symbolImage, value: .home) {
                        HomeView { selectedTab = .collection }
                            .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
                    }
                    Tab(AppTab.collection.title, systemImage: AppTab.collection.symbolImage, value: .collection) {
                        CollectionView()
                            .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
                    }

                    Tab(AppTab.search.title, systemImage: AppTab.search.symbolImage, value: .search) {
                        SearchView().toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
                    }

                    Tab(AppTab.settings.title, systemImage: AppTab.settings.symbolImage, value: .settings) {
                        SettingsView()
                            .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
                    }
                } effects: { tab in
                    switch tab {
                    case .search: [.bounce]
                    case .home: [.bounce]
                    case .collection: [.wiggle]
                    case .settings: [.rotate]
                    }
                }
                .environment(\.albumContextMenusEnabled, !playerExpanded)
                .allowsHitTesting(!playerExpanded)
                .accessibilityHidden(playerExpanded)
                .id(localizationManager.selectedLanguage)
                .toolbar(shouldHideTabBar ? .hidden : .visible, for: .tabBar)
                .onAppear {
                    collectionVM.setModelContext(modelContext)
                    collectionVM.restoreLastPlayed()
                    isLandscape = geo.size.width > geo.size.height
                    setTabBarHidden(isLandscape && selectedTab == .collection)
                    updateTabBarTint()
                    // Schedule notifications
                    NotificationManager.shared.rescheduleAll(context: modelContext)
                }
                .onChange(of: styleManager.theme) { _, _ in
                    updateTabBarTint()
                }
                .onChange(of: geo.size) { _, newSize in
                    let nowLandscape = newSize.width > newSize.height
                    isLandscape = nowLandscape
                    setTabBarHidden((nowLandscape && selectedTab == .collection) || isImmersiveCollectionOverlay)
                    if nowLandscape {
                        playerExpanded = false
                    }
                }
                .onChange(of: collectionVM.isAlbumDetailPresented) { _, active in
                    setTabBarHidden((isLandscape && selectedTab == .collection) || active)
                }
                .onChange(of: selectedTab) { _, _ in
                    setTabBarHidden(shouldHideTabBar)
                }
                .onDisappear {
                    setTabBarHidden(false)
                }

                // Import progress banner — above mini player
                if !playerExpanded && !isLandscape {
                    VStack {
//                        Spacer()
                        ImportProgressBanner()
                            .environmentObject(styleManager)
                            .padding(.top, 56)
                        
                        Spacer()
                    }
                }

            }
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(.container, edges: .bottom)
            // An overlay cannot change the TabView's proposed size or bottom
            // inset as the player grows. Keep the tab bar mounted underneath.
            .overlay(alignment: .bottom) {
                if !isLandscape && !isImmersiveCollectionOverlay {
                    TurntableView(
                        isExpanded: $playerExpanded,
                        playerAnimation: playerAnimation,
                        miniPlayerBottomInset: miniPlayerBottomPad,
                        expandedCornerRadius: playerCornerRadius
                    )
                    // Expand the overlay host to the physical screen edges.
                    // A fixed-height player alone cannot extend the overlay's
                    // bottom alignment out of the parent safe area.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .background {
                        PlayerScreenCornerReader { radius in
                            playerCornerRadius = radius
                        }
                        .allowsHitTesting(false)
                    }
                    .ignoresSafeArea(.container)
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                PlaybackStatusBanner().padding(.horizontal, 16)
                ToastContainerView()
            }.padding(.top, 8)
        }
        .overlay {
            if showCoverFlowTip {
                CoverFlowTipOverlay(isPresented: $showCoverFlowTip)
            }
        }
        .onAppear {
            if !showOnboarding && !hasShownCoverFlowTip {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !showOnboarding && !hasShownCoverFlowTip {
                        showCoverFlowTip = true
                        hasShownCoverFlowTip = true
                    }
                }
            }
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if isShowing || hasShownCoverFlowTip {
                showCoverFlowTip = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                collectionVM.saveLastPlayed()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environmentObject(styleManager)
                .environmentObject(musicServiceManager)
        }
    }

    /// Stable bottom safe-area inset from UIKit (excludes keyboard height).
    private var windowBottomInset: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return 0 }
        return window.safeAreaInsets.bottom
    }

    /// Fallback tab bar visibility control for cases where `.toolbar(.hidden, for: .tabBar)` does not immediately apply.
    private func setTabBarHidden(_ hidden: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else { return }

        findTabBarController(from: rootViewController)?.tabBar.isHidden = hidden
    }

    private func findTabBarController(from viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }

        for child in viewController.children {
            if let tabBarController = findTabBarController(from: child) {
                return tabBarController
            }
        }

        if let presentedViewController = viewController.presentedViewController {
            return findTabBarController(from: presentedViewController)
        }

        return nil
    }

    private func updateTabBarTint() {
        let uiColor = UIColor(styleManager.theme.accentColor)
        UITabBar.appearance().tintColor = uiColor
        UITabBar.appearance().unselectedItemTintColor = UIColor.secondaryLabel
        // Also apply to the current instance
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController,
              let tabBarController = findTabBarController(from: rootViewController) else { return }
        tabBarController.tabBar.tintColor = uiColor
        tabBarController.tabBar.unselectedItemTintColor = UIColor.secondaryLabel
    }

    // MARK: - Expanded Top Bar

    private func expandedTopBar(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.4))
                .frame(width: 56, height: 4)
                .padding(.top, safeTop - 32)
        }
        .frame(maxWidth: .infinity)
        .frame(height: safeTop + 64)
        .contentShape(Rectangle())
    }


    // MARK: - Actions

}

enum AppTab: AnimatedTabSectionProtocol {
    case search
    case home
    case collection
    case settings

    var symbolImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .home: return "house"
        case .collection: return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .search: return L("search.title")
        case .home: return L("tab.home")
        case .collection: return L("tab.collection")
        case .settings: return L("tab.settings")
        }
    }
}

// MARK: - Preview Data

private func contentPreviewCoverData(
    title: String,
    color: UIColor,
    index: Int,
    size: CGFloat = 420
) -> Data? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let highlight = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(0.35).cgColor,
                color.cgColor,
                UIColor.black.withAlphaComponent(0.30).cgColor
            ] as CFArray,
            locations: [0, 0.55, 1]
        )!
        context.cgContext.drawLinearGradient(
            highlight,
            start: .zero,
            end: CGPoint(x: size, y: size),
            options: []
        )

        let number = String(format: "%02d", index + 1)
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size * 0.24, weight: .black),
            .foregroundColor: UIColor.white.withAlphaComponent(0.22)
        ]
        number.draw(
            at: CGPoint(x: size * 0.07, y: size * 0.08),
            withAttributes: numberAttributes
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.075, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]
        title.draw(
            in: CGRect(x: size * 0.08, y: size * 0.69, width: size * 0.84, height: size * 0.2),
            withAttributes: titleAttributes
        )
    }
    return image.jpegData(compressionQuality: 0.88)
}

private struct ContentPreviewAlbumCountSlider: View {
    let container: ModelContainer
    @State private var albumCount = 24.0

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                Slider(value: $albumCount, in: 1...60, step: 1)
                    .frame(width: 150)
                Text("\(Int(albumCount))")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .frame(width: 24, alignment: .trailing)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.top, 58)

            Spacer()
        }
        .onChange(of: albumCount) { _, newValue in
            updateAlbumCount(to: Int(newValue))
        }
    }

    private func updateAlbumCount(to requestedCount: Int) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Album>(
            sortBy: [SortDescriptor(\.addedDate, order: .reverse)]
        )
        guard var currentAlbums = try? context.fetch(descriptor) else { return }

        if requestedCount < currentAlbums.count {
            for album in currentAlbums.suffix(currentAlbums.count - requestedCount) {
                context.delete(album)
            }
        } else if requestedCount > currentAlbums.count {
            for index in currentAlbums.count..<requestedCount {
                let title = "Preview Album \(index + 1)"
                let artist = "Preview Artist \(index % 8 + 1)"
                let hue = CGFloat(index % 24) / 24
                let tracks = (1...8).map { trackNumber in
                    Track(
                        title: "Track \(trackNumber)",
                        artist: artist,
                        albumTitle: title,
                        duration: 180 + Double(trackNumber * 9),
                        trackNumber: trackNumber,
                        side: trackNumber <= 4 ? .a : .b
                    )
                }
                let album = Album(
                    title: title,
                    artist: artist,
                    releaseYear: 1960 + index % 66,
                    genre: "Preview",
                    colorHex: "#4A5A8A",
                    tracks: tracks,
                    customCoverImageData: contentPreviewCoverData(
                        title: title,
                        color: UIColor(hue: hue, saturation: 0.72, brightness: 0.88, alpha: 1),
                        index: index
                    ),
                    addedDate: Calendar.current.date(byAdding: .month, value: -index, to: Date())
                )
                context.insert(album)
            }
        }

        try? context.save()
        currentAlbums.removeAll()
    }
}

#Preview("Content — Fan Index Data") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self, configurations: configuration)
    let calendar = Calendar(identifier: .gregorian)

    let titles = [
        "Neon Skyline", "Blue Hour", "Paper Moons", "After Midnight",
        "Velvet Static", "Northern Lights", "Golden Echo", "City Bloom",
        "Slow Motion", "Parallel Lines", "Signal Fires", "Glass Houses",
        "Night Drive", "Soft Focus", "Electric Garden", "Sunday Cinema",
        "Silver Lining", "Open Water", "Analog Heart", "Last Light",
        "Dream Sequence", "Coastal Radio", "Modern Love", "Quiet Noise"
    ]
    let artists = [
        "Luna Echo", "The Satellites", "Mira Lane", "Northbound",
        "Circuit Theory", "June Arcade"
    ]
    let genres = ["Alternative", "Electronic", "Jazz", "Pop", "Rock", "Soul"]
    let colors: [UIColor] = [
        .systemIndigo, .systemBlue, .systemTeal, .systemGreen,
        .systemOrange, .systemPink, .systemPurple, .systemRed
    ]

    var previewAlbums: [Album] = []
    for index in titles.indices {
        let artist = artists[index % artists.count]
        let year = 1958 + (index * 3) % 67
        let addedDate = calendar.date(
            byAdding: .month,
            value: -index,
            to: Date()
        )
        let tracks = (0..<8 + index % 5).map { trackIndex in
            Track(
                title: "Track \(trackIndex + 1)",
                artist: artist,
                albumTitle: titles[index],
                duration: 180 + Double(trackIndex * 11),
                trackNumber: trackIndex + 1,
                side: trackIndex < 5 ? .a : .b
            )
        }
        let album = Album(
            title: titles[index],
            artist: artist,
            releaseYear: year,
            genre: genres[index % genres.count],
            colorHex: "#4A5A8A",
            tracks: tracks,
            customCoverImageData: contentPreviewCoverData(
                title: titles[index],
                color: colors[index % colors.count],
                index: index
            ),
            addedDate: addedDate
        )
        album.tags = [genres[index % genres.count], index.isMultiple(of: 2) ? "Favorite" : "New"]
        album.isPinned = index < 2
        container.mainContext.insert(album)
        previewAlbums.append(album)
    }

    let collectionVM = CollectionViewModel()
    if let album = previewAlbums.first {
        collectionVM.currentAlbum = album
        collectionVM.currentTrack = album.sortedTracks.first
        collectionVM.isPlaying = false
    }

    UserDefaults.standard.set(
        true,
        forKey: AppConstants.StorageKeys.hasCompletedOnboarding
    )
    UserDefaults.standard.set(true, forKey: "hasShownCoverFlowTip")

    return ZStack {
        ContentView()

//        ContentPreviewAlbumCountSlider(container: container)
//            .zIndex(1_000)
    }
    .modelContainer(container)
    .environmentObject(collectionVM)
    .environmentObject(StyleManager())
    .environmentObject(MusicServiceManager())
}

/// Read the attached display, independent of the player's position during drag.
private struct PlayerScreenCornerReader: UIViewRepresentable {
    var onRadius: (CGFloat) -> Void
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.onRadius = onRadius
        view.setNeedsLayout()
    }
    final class Probe: UIView {
        var onRadius: ((CGFloat) -> Void)?
        private var lastRadius: CGFloat?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let screen = window?.screen else { return }
            let radius = screen.displayCornerRadius
            guard radius.isFinite, radius >= 0, lastRadius != radius else { return }
            lastRadius = radius
            DispatchQueue.main.async { [weak self] in self?.onRadius?(radius) }
        }
    }
}
