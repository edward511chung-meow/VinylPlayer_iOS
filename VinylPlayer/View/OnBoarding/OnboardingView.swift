import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var musicServiceManager: MusicServiceManager
    @EnvironmentObject private var styleManager: StyleManager
    @Binding var isPresented: Bool

    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var notificationGranted = false

    var body: some View {
        OnBoarding(
            tint: styleManager.theme.accentColor,
            items: onboardingItems,
            onComplete: completeOnboarding
        )
        .onAppear {
            notificationGranted = notificationManager.authorizationStatus == .authorized
        }
    }

    private var onboardingItems: [OnBoarding.Item] {
        [
            .init(
                id: 0,
                title: L("onboarding.welcome_title"),
                subtitle: L("onboarding.welcome_subtitle"),
                screenshot: UIImage(named: "06-full-player")
            ),
            .init(
                id: 1,
                title: L("onboarding.fan_title"),
                subtitle: L("onboarding.fan_subtitle"),
                screenshot: UIImage(named: "02-fan-indexing-active")
            ),
            .init(
                id: 2,
                title: L("onboarding.fan_title"),
                subtitle: L("onboarding.fan_subtitle"),
                screenshot: UIImage(named: "03-fan-indexing-focused")
            ),
            .init(
                id: 3,
                title: L("onboarding.coverflow_title"),
                subtitle: L("onboarding.coverflow_subtitle"),
                screenshot: UIImage(named: "01-collection-portrait"),
                turnsToNext: true,
                turnScale: 0.72,
                turnAnchor: .center
            ),
            .init(
                id: 4,
                title: L("onboarding.coverflow_title"),
                subtitle: L("onboarding.coverflow_subtitle"),
                screenshot: UIImage(named: "04-coverflow-landscape"),
                zoomScale: 1.0,
                zoomAnchor: .init(x: 0.5, y: -0.1),
                turnAnchor: .init(x: 0.5, y: -0.1)
            ),
            .init(
                id: 5,
                title: L("onboarding.coverflow_title"),
                subtitle: L("onboarding.coverflow_subtitle"),
                screenshot: UIImage(named: "05-coverflow-flipped"),
                zoomScale: 1.0,
                zoomAnchor: .init(x: 0.5, y: -0.1),
                turnAnchor: .init(x: 0.5, y: -0.1)
            ),
            .init(
                id: 6,
                title: L("onboarding.connect_title"),
                subtitle: L("onboarding.connect_subtitle"),
                screenshot: nil,
                content: AnyView(connectMusicStage)
            ),
            .init(
                id: 7,
                title: L("onboarding.notification_title"),
                subtitle: L("onboarding.notification_subtitle"),
                screenshot: nil,
                content: AnyView(notificationStage)
            )
        ]
    }

    private var connectMusicStage: some View {
        permissionStage(
            icon: "apple.logo",
            isGranted: musicServiceManager.isAuthorized(.appleMusic),
            grantedText: L("onboarding.connected"),
            actionIcon: "music.note",
            actionTitle: L("onboarding.connect_apple_music")
        ) {
            Task {
                try? await musicServiceManager.authorize(source: .appleMusic)
            }
        }
    }

    private var notificationStage: some View {
        permissionStage(
            icon: "bell.badge.fill",
            isGranted: notificationGranted,
            grantedText: L("onboarding.notification_enabled"),
            actionIcon: "bell",
            actionTitle: L("onboarding.enable_notifications")
        ) {
            Task {
                let granted = await notificationManager.requestAuthorization()
                await MainActor.run {
                    notificationGranted = granted
                }
            }
        }
    }

    private func permissionStage(
        icon: String,
        isGranted: Bool,
        grantedText: String,
        actionIcon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(styleManager.theme.accentColor.opacity(0.18))
                    .frame(width: 128, height: 128)

                Image(systemName: icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(styleManager.theme.accentColor)
            }

            if isGranted {
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.green.opacity(0.12), in: Capsule())
            } else {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.glassProminent)
                .tint(styleManager.theme.accentColor)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(
            true,
            forKey: AppConstants.StorageKeys.hasCompletedOnboarding
        )
        UserDefaults.standard.set(true, forKey: "hasShownCoverFlowTip")
        isPresented = false
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
        .environmentObject(StyleManager())
        .environmentObject(MusicServiceManager())
}
