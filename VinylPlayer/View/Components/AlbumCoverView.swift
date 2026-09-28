import SwiftUI
import SwiftData

/// Displays album artwork — either a custom uploaded image, remote URL, or
/// a generated gradient placeholder with the album's accent color.
struct AlbumCoverView: View {
    @Bindable var album: Album
    let size: CGFloat
    var height: CGFloat? = nil
    var cornerRadius: CGFloat? = nil
    var showsPlaceholderMetadata = true
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let imageData = album.customCoverImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let urlString = album.displayArtworkURL,
                      let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                        .frame(width: size, height: size)
                }
                .task(id: urlString) {
                    await downloadAndSave(urlString: urlString)
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: height ?? size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.05))
        // Force view refresh when artwork data changes (e.g. after download)
        .id(album.customCoverImageData != nil)
    }

    /// Fetch artwork from URL and persist to SwiftData so it's available offline.
    private func downloadAndSave(urlString: String) async {
        // Skip if already has local data
        guard album.customCoverImageData == nil else { return }

        if let image = await ImageCacheManager.shared.image(for: urlString),
           let data = image.jpegData(compressionQuality: 0.85) {
            await MainActor.run {
                album.customCoverImageData = data
                try? modelContext.save()
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            // Gradient background using album color
            LinearGradient(
                colors: [album.color, album.color.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle light overlay
            LinearGradient(
                colors: [Color.white.opacity(0.15), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            VStack(spacing: size * 0.03) {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.18))
                    .foregroundColor(.white.opacity(0.85))

                if showsPlaceholderMetadata {
                    Text(album.title)
                        .font(.system(size: max(9, size * 0.08), weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Text(album.artist)
                        .font(.system(size: max(7, size * 0.06)))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    AlbumCoverView(album: Album(title: "test", artist: "test"), size: 220)
}
