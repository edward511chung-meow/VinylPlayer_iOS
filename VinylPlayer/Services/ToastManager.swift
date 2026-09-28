import SwiftUI
import Combine

// MARK: - Toast Type

enum ToastType {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success: return .green
        case .error:   return .red
        case .info:    return .primary
        }
    }

    /// Icon color that respects the app theme — info uses the provided accent color.
    func themedIconColor(accent: Color) -> Color {
        switch self {
        case .success: return .green
        case .error:   return .red
        case .info:    return accent
        }
    }
}

// MARK: - Toast Item

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    var duration: TimeInterval = 2.5

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var toasts: [ToastItem] = []

    private let maxVisible = 3

    private init() {}

    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 2.5) {
        let toast = ToastItem(type: type, message: message, duration: duration)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            toasts.append(toast)
        }

        // Trim if exceeding max
        if toasts.count > maxVisible {
            withAnimation(.easeOut(duration: 0.2)) {
                toasts.removeFirst(toasts.count - maxVisible)
            }
        }

        // Auto dismiss
        Task {
            try? await Task.sleep(for: .seconds(duration))
            dismiss(toast)
        }
    }

    func success(_ message: String, duration: TimeInterval = 2.5) {
        show(message, type: .success, duration: duration)
    }

    func error(_ message: String, duration: TimeInterval = 3.0) {
        show(message, type: .error, duration: duration)
    }

    func info(_ message: String, duration: TimeInterval = 2.5) {
        show(message, type: .info, duration: duration)
    }

    func dismiss(_ toast: ToastItem) {
        withAnimation(.easeOut(duration: 0.25)) {
            toasts.removeAll { $0.id == toast.id }
        }
    }
}
