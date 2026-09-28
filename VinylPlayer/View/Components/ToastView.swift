import SwiftUI

// MARK: - Single Toast View

struct ToastView: View {
    let toast: ToastItem
    let onDismiss: () -> Void
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.type.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toast.type.themedIconColor(accent: styleManager.theme.accentColor))

            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Capsule()
                .fill(colorScheme == .dark
                    ? Color.white.opacity(0.12)
                    : Color.black.opacity(0.06)
                )
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
        .clipShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -20 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            onDismiss()
                        }
                    }
                }
        )
    }
}

// MARK: - Stacked Toast Container

struct ToastContainerView: View {
    @ObservedObject var toastManager = ToastManager.shared

    var body: some View {
        // Newest toast on top — reversed so latest appears first
        VStack(spacing: 8) {
            ForEach(toastManager.toasts.reversed()) { toast in
                ToastView(toast: toast) {
                    toastManager.dismiss(toast)
                }
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -60).combined(with: .opacity),
                        removal: .offset(y: -40).combined(with: .opacity)
                    )
                )
            }
        }
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: toastManager.toasts)
    }
}
