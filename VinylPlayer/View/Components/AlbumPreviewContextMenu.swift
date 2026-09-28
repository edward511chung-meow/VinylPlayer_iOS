import SwiftUI
import UIKit
import SwiftData
import ObjectiveC

private struct AlbumContextMenusEnabledKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var albumContextMenusEnabled: Bool {
        get { self[AlbumContextMenusEnabledKey.self] }
        set { self[AlbumContextMenusEnabledKey.self] = newValue }
    }
}

/// Adds a native context interaction without moving the SwiftUI source into a
/// separate hosting controller (which would disrupt its gestures and hero IDs).
struct AlbumPreviewContextMenu: UIViewRepresentable {
    let album: Album?
    var track: Track? = nil
    var enabled = true
    var usesWindowHost = false
    var receivesTouches = false
    var onTap: (() -> Void)? = nil
    var onPan: ((CGFloat, Bool) -> Void)? = nil
    let menu: () -> UIMenu
    let onOpen: (Album) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.albumContextMenusEnabled) private var menusEnabled

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ view: Anchor, context: Context) {
        view.modelContext = modelContext
        view.album = album
        view.track = track
        view.enabled = enabled && menusEnabled
        view.usesWindowHost = usesWindowHost
        view.menu = menu
        view.onOpen = onOpen
        view.onTap = onTap
        view.onPan = onPan
        view.receivesTouches = receivesTouches
        view.isUserInteractionEnabled = receivesTouches && view.enabled
        view.register()
    }
    static func dismantleUIView(_ view: Anchor, coordinator: ()) { view.unregister() }

    final class Anchor: UIView {
        var modelContext: ModelContext?
        var album: Album?
        var track: Track?
        var enabled = true
        var usesWindowHost = false
        var receivesTouches = false
        var onTap: (() -> Void)?
        var onPan: ((CGFloat, Bool) -> Void)?
        var menu: (() -> UIMenu)?
        var onOpen: ((Album) -> Void)?
        weak var router: Router?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            tap.require(toFail: pan)
            addGestureRecognizer(tap)
            addGestureRecognizer(pan)
        }
        @objc private func tapped() { onTap?() }
        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            let value = recognizer.translation(in: self)
            let ended = recognizer.state == .ended || recognizer.state == .cancelled
            let horizontal = abs(value.x) > abs(value.y) * 1.4
            onPan?(horizontal && recognizer.state != .cancelled ? value.x : 0, ended)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); register() }
        func register() {
            guard window != nil, var host = superview else { unregister(); return }
            // Background representables are not hit-test targets. Register on
            // the enclosing controller's view, which receives descendant
            // touches, and route only points inside a live source rectangle.
            while !(host.next is UIViewController), let parent = host.superview, !(parent is UIWindow) {
                host = parent
            }
            // Overlay controls can be rendered outside the nearest hosting
            // controller's hit-test branch. A window interaction receives their
            // touches too; routing still restricts it to the source bounds.
            if usesWindowHost, let window { host = window }
            if receivesTouches { host = self }
            let next = Router.forView(host)
            guard router !== next else { return }
            unregister()
            router = next
            next.anchors.append(WeakAnchor(value: self))
        }
        func unregister() {
            router?.anchors.removeAll { $0.value == nil || $0.value === self }
            router = nil
        }
    }
    struct WeakAnchor { weak var value: Anchor? }

    final class Router: NSObject, UIContextMenuInteractionDelegate {
        private static var association: UInt8 = 0
        var anchors: [WeakAnchor] = []
        static func forView(_ host: UIView) -> Router {
            if let existing = objc_getAssociatedObject(host, &association) as? Router { return existing }
            let router = Router()
            host.addInteraction(UIContextMenuInteraction(delegate: router))
            objc_setAssociatedObject(host, &association, router, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return router
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let host = interaction.view, let window = host.window else { return nil }
            let point = host.convert(location, to: window)
            guard let hit = window.hitTest(point, with: nil), hit.isDescendant(of: host) else { return nil }
            anchors.removeAll { $0.value == nil }
            guard let anchor = anchors.reversed().compactMap(\.value).first(where: {
                $0.enabled && $0.window === window && !$0.isHidden &&
                $0.bounds.contains(host.convert(location, to: $0))
            }), let album = anchor.album, let open = anchor.onOpen else { return nil }
            // Snapshot the album and callbacks at presentation time: playback
            // may advance to another album while this menu remains visible.
            guard let modelContext = anchor.modelContext else { return nil }
            let preview = AlbumContextPreview(album: album, track: anchor.track)
                .environment(\.modelContext, modelContext)
            let menu = anchor.menu?() ?? UIMenu()
            let configuration = CommittableConfiguration(identifier: nil, previewProvider: {
                let controller = UIHostingController(rootView: preview)
                controller.view.backgroundColor = .clear
                controller.preferredContentSize = controller.sizeThatFits(in: CGSize(width: 340, height: 500))
                return controller
            }, actionProvider: { _ in menu })
            configuration.source = anchor
            configuration.commit = { open(album) }
            return configuration
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            sourcePreview(interaction, configuration: configuration)
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            sourcePreview(interaction, configuration: configuration)
        }
        private func sourcePreview(_ interaction: UIContextMenuInteraction,
                                   configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            guard let host = interaction.view,
                  let source = (configuration as? CommittableConfiguration)?.source,
                  source.window != nil else { return nil }
            let rect = source.convert(source.bounds, to: host)
            guard let snapshot = host.resizableSnapshotView(from: rect, afterScreenUpdates: false,
                                                           withCapInsets: .zero) else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedPreview(view: snapshot, parameters: parameters,
                                     target: UIPreviewTarget(container: host,
                                                             center: CGPoint(x: rect.midX, y: rect.midY)))
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: any UIContextMenuInteractionCommitAnimating) {
            guard let configuration = configuration as? CommittableConfiguration,
                  let commit = configuration.commit else { return }
            configuration.commit = nil
            animator.preferredCommitStyle = .dismiss
            // Begin the destination transition alongside the menu dismissal.
            // Waiting for completion serializes both animations and makes a
            // preview tap feel unresponsive before the detail view even starts.
            animator.addAnimations(commit)
        }
    }
    final class CommittableConfiguration: UIContextMenuConfiguration {
        weak var source: Anchor?
        var commit: (() -> Void)?
    }
}

func albumContextAction(_ title: String, symbol: String,
                        destructive: Bool = false, action: @escaping () -> Void) -> UIAction {
    let image = UIImage(systemName: symbol)?.withTintColor(.black, renderingMode: .alwaysOriginal)
    return UIAction(title: title, image: image, attributes: destructive ? .destructive : []) { _ in action() }
}
