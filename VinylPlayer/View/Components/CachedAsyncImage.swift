import SwiftUI

/// A drop-in replacement for AsyncImage that uses ImageCacheManager
/// for memory + disk caching with automatic retry.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }
        isLoading = true
        hasFailed = false

        let image = await ImageCacheManager.shared.image(for: url.absoluteString)

        if !Task.isCancelled {
            self.uiImage = image
            self.hasFailed = image == nil
        }
        isLoading = false
    }
}

// Convenience init matching AsyncImage style
extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.url = url
        self.content = { $0 }
        self.placeholder = { ProgressView() }
    }
}
