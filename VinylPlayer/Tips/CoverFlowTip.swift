import SwiftUI

/// Full-screen overlay shown once to inform the user about Cover Flow mode.
struct CoverFlowTipOverlay: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var appear = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(appear ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Tip card
            VStack(spacing: 32) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 80, height: 80)

                    Image(systemName: "rotate.right")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(iconForegroundColor)
                }

                // Text
                VStack(spacing: 12) {
                    Text(L("tip.coverflow_title"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(textPrimaryColor)

                    Text(L("tip.coverflow_message"))
                        .font(.system(size: 16))
                        .foregroundColor(textSecondaryColor)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Dismiss button
                Button {
                    dismiss()
                } label: {
                    Text(L("tip.dismiss"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(buttonTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(buttonBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: 304)
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .scaleEffect(appear ? 1 : 0.85)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                appear = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            appear = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }

    // MARK: - Colors (Light / Dark)

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(white: 0.15)
            : Color.white
    }

    private var iconBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.06)
    }

    private var iconForegroundColor: Color {
        colorScheme == .dark
            ? Color.white
            : Color.black
    }

    private var textPrimaryColor: Color {
        colorScheme == .dark
            ? Color.white
            : Color.black
    }

    private var textSecondaryColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.6)
            : Color.black.opacity(0.5)
    }

    private var buttonBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white
            : Color.black
    }

    private var buttonTextColor: Color {
        colorScheme == .dark
            ? Color.black
            : Color.white
    }
}
