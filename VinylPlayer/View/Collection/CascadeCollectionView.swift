import SwiftUI
import SwiftData

// MARK: - Cascade Config

struct CascadeConfig {
    var maxTilt: CGFloat = 65
    var offsetFactor: CGFloat = 1.15
    var perspective: CGFloat = 0.4
    var cardWidthRatio: CGFloat = 0.78
}

// MARK: - 3D Cascade Collection View

struct CascadeCollectionView: View {
    @Query private var albums: [Album]
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var collectionVM: CollectionViewModel
    @State private var activeIndex: Int? = 0

    private let config = CascadeConfig()

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let currentIndex = activeIndex ?? 0
            let cardSize = containerSize.width * config.cardWidthRatio

            ZStack {
                styleManager.theme.backgroundColor
                    .ignoresSafeArea()

                if albums.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                                cascadeCard(album: album, size: cardSize)
                                    .frame(width: cardSize, height: cardSize)
                                    .frame(width: containerSize.width, height: cardSize)
                                    .visualEffect { [config] content, proxy in
                                        let v = cascadeLayoutValues(proxy, cardSize: cardSize, config: config)

                                        return content
                                            .rotation3DEffect(
                                                .degrees(v.tilt),
                                                axis: (x: 1, y: 0, z: 0),
                                                anchor: .bottom,
                                                perspective: config.perspective
                                            )
                                            .scaleEffect(v.scale, anchor: .bottom)
                                            .offset(y: v.offset)
                                            .opacity(v.progress > 0 ? max(0, 1 - v.progress * 1.5) : 1)
                                    }
                                    .zIndex(
                                        currentIndex == index
                                            ? 1000
                                            : (currentIndex > index ? Double(index) : Double(-index))
                                    )
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaPadding(
                        .top,
                        (containerSize.height - cardSize) / 2 + containerSize.height * 0.15
                    )
                    .safeAreaPadding(
                        .bottom,
                        max(20, (containerSize.height - cardSize) / 2 - containerSize.height * 0.15)
                    )
                    .scrollPosition(id: $activeIndex, anchor: .center)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollClipDisabled()
                    .onAppear {
                        // Start a few cards in so cascade is immediately visible
                        if albums.count > 3 {
                            activeIndex = min(3, albums.count - 1)
                        }
                    }
                    .onChange(of: activeIndex) { oldValue, newValue in
                        guard oldValue != newValue, newValue != nil else { return }
                        HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                    }
                }
            }
        }
        .navigationTitle(L("collection.title"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Layout Calculation (reference-style cascade)

    nonisolated
    private func cascadeLayoutValues(
        _ proxy: GeometryProxy,
        cardSize: CGFloat,
        config: CascadeConfig
    ) -> (tilt: CGFloat, scale: CGFloat, offset: CGFloat, progress: CGFloat) {
        let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
        let progress = minY / cardSize

        // Cards above center (progress < 0): tilt progressively over ~3 cards
        let tiltNorm = progress < 0 ? min(-progress / 3.0, 1.0) : 0
        let tilt = tiltNorm * config.maxTilt

        // Slight scale reduction for depth
        let scale: CGFloat = progress < 0 ? 1.0 - min(-progress, 4) * 0.015 : 1.0

        // Overlap offset — tight packing
        let offset = -progress * (cardSize / config.offsetFactor)

        return (tilt, scale, offset, progress)
    }

    // MARK: - Cascade Card

    private func cascadeCard(album: Album, size: CGFloat) -> some View {
        let baseColor = Color(hex: album.colorHex) ?? .gray

        return ZStack(alignment: .bottomLeading) {
            AlbumCoverView(album: album, size: size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Gradient overlay for text readability
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Top inner shadow — creates visible "thickness" edge in cascade
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.45), .black.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)

            // Album info
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(14)
        }
        // Edge highlight border
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.2),
                            .white.opacity(0.05),
                            baseColor.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Soft shadow for depth
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.4))

            Text(L("collection.empty"))
                .font(.system(size: 15))
                .foregroundColor(styleManager.theme.textSecondary)
        }
    }
}

// MARK: - Mock Cover Image Helper

private func mockCoverImageData(colorHex: String, size: CGFloat = 260) -> Data? {
    let color = UIColor(Color(hex: colorHex) ?? .gray)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    let image = renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Add subtle gradient overlay for visual interest
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(0.15).cgColor,
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.2).cgColor
            ] as CFArray,
            locations: [0, 0.5, 1]
        )!
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size, y: size),
            options: []
        )

        // Draw a vinyl icon in the center
        let iconSize: CGFloat = size * 0.35
        let iconRect = CGRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        UIColor.white.withAlphaComponent(0.2).setFill()
        ctx.cgContext.fillEllipse(in: iconRect)

        let innerSize: CGFloat = iconSize * 0.3
        let innerRect = CGRect(
            x: (size - innerSize) / 2,
            y: (size - innerSize) / 2,
            width: innerSize,
            height: innerSize
        )
        UIColor.white.withAlphaComponent(0.3).setFill()
        ctx.cgContext.fillEllipse(in: innerRect)
    }
    return image.jpegData(compressionQuality: 0.9)
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Album.self, configurations: config)

    let mockAlbums: [(String, String, Int, String)] = [
        ("Abbey Road", "The Beatles", 1969, "#2E5A3C"),
        ("OK Computer", "Radiohead", 1997, "#4A6B8A"),
        ("Random Access Memories", "Daft Punk", 2013, "#1A1A1A"),
        ("Kind of Blue", "Miles Davis", 1959, "#3B5998"),
        ("Rumours", "Fleetwood Mac", 1977, "#8B6914"),
        ("Dark Side of the Moon", "Pink Floyd", 1973, "#1C2331"),
        ("Thriller", "Michael Jackson", 1982, "#B22222"),
        ("Back to Black", "Amy Winehouse", 2006, "#2C2C2C"),
        ("Blue Train", "John Coltrane", 1957, "#1E3A5F"),
        ("Blonde on Blonde", "Bob Dylan", 1966, "#8B7355"),
    ]

    for item in mockAlbums {
        let album = Album(
            title: item.0,
            artist: item.1,
            releaseYear: item.2,
            colorHex: item.3,
            customCoverImageData: mockCoverImageData(colorHex: item.3)
        )
        container.mainContext.insert(album)
    }

    return NavigationStack {
        CascadeCollectionView()
    }
    .modelContainer(container)
    .environmentObject(StyleManager())
    .environmentObject(CollectionViewModel())
    .preferredColorScheme(.dark)
}
