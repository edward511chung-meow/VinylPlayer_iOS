import SwiftUI

// Section Protocol
protocol AnimatedTabSectionProtocol: CaseIterable, Hashable {
    var title: String { get }
    var symbolImage: String { get }
}

struct AnimatedTabView<Selection: AnimatedTabSectionProtocol, Content: TabContent<Selection>>: View {
    @Binding var selection: Selection
    var tintColor: Color = .blue
    @TabContentBuilder<Selection> var content: () -> Content
    var effects: (Selection) -> [any DiscreteSymbolEffect & SymbolEffect]

    // View Properties
    @State private var imageViews: [Selection: UIImageView] = [:]

    var body: some View {
        TabView(selection: $selection) {
            content()
        }
        .tint(tintColor)
        .toolbarBackground(tintColor, for: .tabBar)
        .tabViewStyle(.tabBarOnly)
        .background(ExtractImageViewsFromTabView {
            imageViews = $0
        })
        .compositingGroup()
        // Animate the image view when the tab changes
        .onChange(of: selection) { oldValue, newValue in
            let symbolEffects = effects(newValue)
            guard let imageView = imageViews[newValue] else { return }

            for effect in symbolEffects {
                imageView.addSymbolEffect(effect, options: .nonRepeating)
            }
        }
    }
}

fileprivate struct ExtractImageViewsFromTabView<Value: AnimatedTabSectionProtocol>: UIViewRepresentable {
    var result: ([Value: UIImageView]) -> ()

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            if let compositingGroup = view.superview?.superview {
                guard let tabHostingController = compositingGroup.subviews.last else { return }
                guard let tabController = tabHostingController.subviews.first?.next as? UITabBarController else { return }
                extractImageViews(tabController.tabBar)
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {
    }

    private func extractImageViews(_ tabBar: UITabBar) {
        let imageViews = tabBar.subviews(type: UIImageView.self)
            // Filtering out non symbol images
            .filter({ $0.image?.isSymbolImage ?? false })
            // Filtering out active tinted images for iOS 26 only
            .filter({ isiOS26 ? ($0.tintColor == tabBar.tintColor) : true })

        var dict: [Value: UIImageView] = [:]

        for tab in Value.allCases {
            if let imageView = imageViews.first(where: {
                // Finding the associated image using the symbol name
                $0.description.contains(tab.symbolImage)
            }) {
                dict[tab] = imageView
            }
        }

        result(dict)
    }

    private var isiOS26: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }
}

// Extracting all subviews with the given type
fileprivate extension UIView {
    func subviews<T: UIView>(type: T.Type) -> [T] {
        subviews.compactMap { $0 as? T } +
        subviews.flatMap { $0.subviews(type: type) }
    }
}
