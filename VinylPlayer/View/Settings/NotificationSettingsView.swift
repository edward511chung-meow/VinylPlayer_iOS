import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var styleManager: StyleManager
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        ZStack {
            styleManager.theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    if notificationManager.authorizationStatus == .denied {
                        deniedBanner
                    } else if notificationManager.authorizationStatus == .notDetermined {
                        enableBanner
                    } else {
                        togglesSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(L("settings.notifications"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            notificationManager.checkAuthorizationStatus()
        }
    }

    // MARK: - Denied Banner

    private var deniedBanner: some View {
        SettingsGroupedCard {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("notification.disabled_title"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(styleManager.theme.textPrimary)
                    Text(L("notification.disabled_hint"))
                        .font(.system(size: 11))
                        .foregroundColor(styleManager.theme.textSecondary)
                }

                Spacer()

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("notification.open_settings"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(styleManager.theme.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Enable Banner

    private var enableBanner: some View {
        SettingsGroupedCard {
            Button {
                Task {
                    await notificationManager.requestAuthorization()
                    notificationManager.rescheduleAll(context: modelContext)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 18))
                        .foregroundColor(styleManager.theme.accentColor)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("notification.enable_title"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(styleManager.theme.textPrimary)
                        Text(L("notification.enable_hint"))
                            .font(.system(size: 11))
                            .foregroundColor(styleManager.theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        SettingsGroupedCard {
            notificationToggle(
                icon: "music.note",
                iconColor: styleManager.theme.accentColor,
                title: L("notification.pref_reminder"),
                subtitle: L("notification.pref_reminder_desc"),
                isOn: $notificationManager.listeningReminderEnabled
            )

            settingsDivider

            notificationToggle(
                icon: "calendar",
                iconColor: .orange,
                title: L("notification.pref_on_this_day"),
                subtitle: L("notification.pref_on_this_day_desc"),
                isOn: $notificationManager.onThisDayEnabled
            )

            settingsDivider

            notificationToggle(
                icon: "trophy",
                iconColor: .yellow,
                title: L("notification.pref_milestone"),
                subtitle: L("notification.pref_milestone_desc"),
                isOn: $notificationManager.milestoneEnabled
            )

            settingsDivider

            notificationToggle(
                icon: "archivebox",
                iconColor: .purple,
                title: L("notification.pref_neglected"),
                subtitle: L("notification.pref_neglected_desc"),
                isOn: $notificationManager.neglectedAlbumEnabled
            )

            settingsDivider

            notificationToggle(
                icon: "chart.bar",
                iconColor: .green,
                title: L("notification.pref_weekly"),
                subtitle: L("notification.pref_weekly_desc"),
                isOn: $notificationManager.weeklyReportEnabled
            )
        }
        .onChange(of: notificationManager.listeningReminderEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.onThisDayEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.neglectedAlbumEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.weeklyReportEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
    }

    // MARK: - Helpers

    private func notificationToggle(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(styleManager.theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(styleManager.theme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(styleManager.theme.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Divider()
            .background(styleManager.theme.textSecondary.opacity(0.1))
            .padding(.leading, 56)
    }
}
