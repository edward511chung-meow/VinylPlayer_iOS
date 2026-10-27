import SwiftUI

/// Shared by the scroll content and the outer flip host. No second scroll gesture:
/// the native scroll view remains responsible for dragging, momentum and reversal.
nonisolated enum AlbumPanelExpansion {
    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / 160))
    }
    static func titleOpacity(for offset: CGFloat) -> CGFloat {
        min(1, max(0, (offset - 64) / 160))
    }
    static func frame(panel: CGRect, full: CGRect, progress: CGFloat) -> CGRect {
        let p = min(1, max(0, progress))
        return CGRect(x: panel.minX + (full.minX - panel.minX) * p,
                      y: panel.minY + (full.minY - panel.minY) * p,
                      width: panel.width + (full.width - panel.width) * p,
                      height: panel.height + (full.height - panel.height) * p)
    }
}
private struct AlbumPanelScrollKey: EnvironmentKey {
    static let defaultValue: ((CGFloat) -> Void)? = nil
}
private struct AlbumPanelTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var albumPanelScroll: ((CGFloat) -> Void)? {
        get { self[AlbumPanelScrollKey.self] }
        set { self[AlbumPanelScrollKey.self] = newValue }
    }
    var albumPanelTopInset: CGFloat {
        get { self[AlbumPanelTopInsetKey.self] }
        set { self[AlbumPanelTopInsetKey.self] = newValue }
    }
}
