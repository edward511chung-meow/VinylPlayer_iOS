import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var musicServiceManager: MusicServiceManager

    @State private var showBackup = false
    @State private var showSleepTimer = false
    @State private var showAuthError: String?
    @State private var isConnecting: MusicSource?

    // Personalization pickers
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var appIconManager = AppIconManager.shared
    @State private var showAppearancePicker = false
    @State private var showThemePicker = false
    @State private var showHapticPicker = false
    @State private var showLyricsStylePicker = false
    @State private var showLanguagePicker = false
    @State private var showTurntableBasePicker = false
    @State private var showAppIconPicker = false
    @State private var showLyricsManagement = false

    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Appearance
                        appearanceSection

                        // Player
                        playerSection

                        // General
                        generalSection

                        // Notifications
                        notificationsSection

                        // Music Sources
                        musicSourcesGroup

                        // About
                        aboutGroup
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .safeAreaPadding(.bottom, 56)
            }
            .navigationTitle(L("settings.title"))
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showBackup) { LibraryBackupView() }
        .sheet(isPresented: $showSleepTimer) { SleepTimerView() }
        .onAppear { notificationManager.checkAuthorizationStatus() }
        .sheet(isPresented: $showAppearancePicker) {
            AppearancePickerSheet()
                .environmentObject(styleManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerSheet()
                .environmentObject(styleManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAppIconPicker) {
            AppIconPickerSheet(appIconManager: appIconManager)
                .environmentObject(styleManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHapticPicker) {
            HapticPickerSheet()
                .environmentObject(styleManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLyricsStylePicker) {
            LyricsStylePickerSheet()
                .environmentObject(styleManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTurntableBasePicker) {
            TurntableBasePickerSheet()
                .environmentObject(styleManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(localizationManager: localizationManager)
                .environmentObject(styleManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLyricsManagement) {
            LyricsManagementView()
                .environmentObject(styleManager)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.appearance_section"))

            SettingsGroupedCard {
                SettingsNavigationRow(
                    icon: styleManager.appearanceMode.iconName,
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.appearance"),
                    value: styleManager.appearanceMode.displayName
                ) { showAppearancePicker = true }

                cardDivider

                SettingsNavigationRow(
                    icon: "paintpalette",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.visual_style"),
                    value: styleManager.theme.displayName
                ) { showThemePicker = true }

                cardDivider

                SettingsNavigationRow(
                    icon: "app.badge",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.app_icon"),
                    value: appIconManager.currentIcon.displayName
                ) { showAppIconPicker = true }
            }
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.player_section"))

            SettingsGroupedCard {
                SettingsNavigationRow(icon: "moon.zzz", iconColor: styleManager.theme.accentColor, title: L("sleep.title"), value: musicServiceManager.sleepPlan.isActive ? L("sleep.active") : "") { showSleepTimer = true }
                cardDivider
                SettingsNavigationRow(
                    icon: "waveform",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.haptic"),
                    value: styleManager.hapticIntensity.displayName
                ) { showHapticPicker = true }

                cardDivider

                SettingsNavigationRow(
                    icon: styleManager.lyricsDisplayMode.iconName,
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.lyrics_style"),
                    value: styleManager.lyricsDisplayMode.displayName
                ) { showLyricsStylePicker = true }

                cardDivider

                SettingsNavigationRow(
                    icon: "text.quote",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.lyrics_management"),
                    value: ""
                ) { showLyricsManagement = true }

                cardDivider

                SettingsNavigationRow(
                    icon: "square.on.square",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.turntable_base"),
                    value: styleManager.turntableBaseStyle.displayName
                ) { showTurntableBasePicker = true }
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.general_section"))

            SettingsGroupedCard {
                SettingsNavigationRow(icon: "externaldrive", iconColor: styleManager.theme.accentColor, title: L("backup.title"), value: "") { showBackup = true }
                cardDivider
                SettingsNavigationRow(
                    icon: "globe",
                    iconColor: styleManager.theme.accentColor,
                    title: L("settings.language"),
                    value: currentLanguageDisplayName
                ) { showLanguagePicker = true }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.notifications"))

            if notificationManager.authorizationStatus == .denied {
                notificationDeniedBanner
            } else if notificationManager.authorizationStatus == .notDetermined {
                notificationEnableBanner
            } else {
                notificationToggles
            }
        }
    }

    private var notificationDeniedBanner: some View {
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

    private var notificationEnableBanner: some View {
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

    private var notificationToggles: some View {
        SettingsGroupedCard {
            notificationToggle(icon: "music.note", iconColor: styleManager.theme.accentColor,
                title: L("notification.pref_reminder"), subtitle: L("notification.pref_reminder_desc"),
                isOn: $notificationManager.listeningReminderEnabled)
            cardDivider
            notificationToggle(icon: "calendar", iconColor: .orange,
                title: L("notification.pref_on_this_day"), subtitle: L("notification.pref_on_this_day_desc"),
                isOn: $notificationManager.onThisDayEnabled)
            cardDivider
            notificationToggle(icon: "trophy", iconColor: .yellow,
                title: L("notification.pref_milestone"), subtitle: L("notification.pref_milestone_desc"),
                isOn: $notificationManager.milestoneEnabled)
            cardDivider
            notificationToggle(icon: "archivebox", iconColor: .purple,
                title: L("notification.pref_neglected"), subtitle: L("notification.pref_neglected_desc"),
                isOn: $notificationManager.neglectedAlbumEnabled)
            cardDivider
            notificationToggle(icon: "chart.bar", iconColor: .green,
                title: L("notification.pref_weekly"), subtitle: L("notification.pref_weekly_desc"),
                isOn: $notificationManager.weeklyReportEnabled)
        }
        .onChange(of: notificationManager.listeningReminderEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.onThisDayEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.neglectedAlbumEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
        .onChange(of: notificationManager.weeklyReportEnabled) { _, _ in notificationManager.rescheduleAll(context: modelContext) }
    }

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

    private var currentLanguageDisplayName: String {
        let code = localizationManager.selectedLanguage
        return LocalizationManager.AppLanguage(rawValue: code)?.displayName ?? "System"
    }

    private var notificationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .denied: return L("settings.notifications_off")
        case .notDetermined: return L("settings.notifications_not_set")
        default: return L("settings.notifications_on")
        }
    }

    private var notificationStatusColor: Color {
        switch notificationManager.authorizationStatus {
        case .denied: return .red
        case .notDetermined: return styleManager.theme.textSecondary
        default: return .green
        }
    }

    // MARK: - Music Sources Group

    private var musicSourcesGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.music_sources"))

            SettingsGroupedCard {
                musicSourceRow(
                    source: .appleMusic,
                    icon: "apple.logo",
                    iconColor: .pink,
                    subtitle: L("settings.apple_music_subtitle")
                )

                cardDivider

                musicSourceRow(
                    source: .spotify,
                    icon: "waveform",
                    iconColor: .green,
                    subtitle: L("settings.spotify_subtitle")
                )

                cardDivider

                // Discogs (always connected)
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.discogs"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(styleManager.theme.textPrimary)
                        Text(L("settings.discogs_subtitle"))
                            .font(.system(size: 11))
                            .foregroundColor(styleManager.theme.textSecondary)
                    }

                    Spacer()

                    Text(L("settings.connected"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if let error = showAuthError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func musicSourceRow(
        source: MusicSource,
        icon: String,
        iconColor: Color,
        subtitle: String
    ) -> some View {
        let status = musicServiceManager.authStatuses[source] ?? .notDetermined
        let isConnected = status.isAuthorized
        let isLoading = isConnecting == source

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(styleManager.theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(styleManager.theme.textSecondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isConnected {
                Button {
                    musicServiceManager.deauthorize(source: source)
                } label: {
                    Text(L("settings.connected"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Button {
                    connectService(source)
                } label: {
                    Text(L("settings.connect"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func connectService(_ source: MusicSource) {
        isConnecting = source
        showAuthError = nil

        Task {
            do {
                try await musicServiceManager.authorize(source: source)
                isConnecting = nil
            } catch {
                showAuthError = error.localizedDescription
                isConnecting = nil
            }
        }
    }

    // MARK: - About Group

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(L("settings.about"))

            SettingsGroupedCard {
                infoRow(label: L("settings.version"), value: AppConstants.appVersion)
                cardDivider
                infoRow(label: L("settings.albums_count"), value: "\(albums.count)")
                cardDivider
                infoRow(label: L("settings.total_tracks"), value: "\(albums.flatMap(\.tracks).count)")
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
            .tracking(0.5)
            .padding(.leading, 4)
    }

    private var cardDivider: some View {
        Divider()
            .background(styleManager.theme.textSecondary.opacity(0.1))
            .padding(.leading, 56)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(styleManager.theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(styleManager.theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Grouped Card Container (shared across Settings sub-pages)

struct SettingsGroupedCard<Content: View>: View {
    @EnvironmentObject var styleManager: StyleManager
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(styleManager.theme.surfaceColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Navigation Row (shared across Settings sub-pages)

struct SettingsNavigationRow: View {
    @EnvironmentObject var styleManager: StyleManager

    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(styleManager.theme.textPrimary)

                Spacer()

                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(styleManager.theme.textSecondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(styleManager.theme.textSecondary.opacity(0.4))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance Picker Sheet

struct AppearancePickerSheet: View {
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        let isSelected = styleManager.appearanceMode == mode

                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                styleManager.appearanceMode = mode
                            }
                            HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                                    .frame(width: 32)

                                Text(mode.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(styleManager.theme.textPrimary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(styleManager.theme.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? styleManager.theme.accentColor.opacity(0.08) : styleManager.theme.surfaceColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle(L("settings.appearance"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Theme Picker Sheet

struct ThemePickerSheet: View {
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(StyleTheme.allCases) { theme in
                            themeCard(theme)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L("settings.visual_style"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func themeCard(_ theme: StyleTheme) -> some View {
        let isSelected = styleManager.theme == theme

        return Button {
            withAnimation(.spring(duration: 0.3)) {
                styleManager.theme = theme
            }
            HapticManager.shared.selectionTick(styleManager.hapticIntensity)
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.backgroundColor)
                    .frame(height: 64)
                    .overlay(
                        HStack(spacing: 8) {
                            Circle().fill(theme.accentColor).frame(width: 12, height: 12)
                            Circle().fill(theme.secondaryAccent).frame(width: 12, height: 12)
                            Circle().fill(theme.surfaceColor).frame(width: 12, height: 12)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? theme.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 0.5)
                    )

                Text(theme.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)

                Text(theme.description)
                    .font(.system(size: 10))
                    .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(styleManager.theme.surfaceColor)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Haptic Picker Sheet

struct HapticPickerSheet: View {
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 12) {
                    ForEach(HapticIntensity.allCases) { intensity in
                        let isSelected = styleManager.hapticIntensity == intensity

                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                styleManager.hapticIntensity = intensity
                            }
                            HapticManager.shared.impact(intensity)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: intensity.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                                    .frame(width: 32)

                                Text(intensity.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(styleManager.theme.textPrimary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(styleManager.theme.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? styleManager.theme.accentColor.opacity(0.08) : styleManager.theme.surfaceColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle(L("settings.haptic"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Lyrics Style Picker Sheet

struct LyricsStylePickerSheet: View {
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 12) {
                    ForEach(LyricsDisplayMode.allCases) { mode in
                        let isSelected = styleManager.lyricsDisplayMode == mode

                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                styleManager.lyricsDisplayMode = mode
                            }
                            HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(styleManager.theme.textPrimary)

                                    Text(mode.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(styleManager.theme.textSecondary)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(styleManager.theme.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? styleManager.theme.accentColor.opacity(0.08) : styleManager.theme.surfaceColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle(L("settings.lyrics_style"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Demo Data Factory

#if DEBUG
enum DemoDataFactory {

    static func createDemoAlbums() -> [Album] {
        [demoAlbum1(), demoAlbum2(), demoAlbum3()]
    }

    // MARK: Album 1 — Midnight Vinyl (Indie/Dream Pop)

    private static func demoAlbum1() -> Album {
        let tracks = [
            Track(
                title: "Neon Skyline",
                artist: "Luna Echo",
                albumTitle: "Midnight Vinyl",
                duration: 234,
                trackNumber: 1,
                side: .a,
                lyrics: """
                Driving through the city lights
                Every shadow tells a story
                Neon signs reflecting bright
                On the windshield wet with glory

                I remember every word you said
                Dancing underneath the streetlamp glow
                The way you turned and shook your head
                Laughing at the radio

                Neon skyline fading slow
                Where do all the lost ones go
                Chasing echoes down below
                Neon skyline fading slow

                Midnight pavement under shoes
                Every corner holds a memory
                Nothing left for me to lose
                Just the music and the remedy

                I can hear the sirens call
                Bouncing off these concrete walls
                But your voice above it all
                Keeps me standing tall

                Neon skyline fading slow
                Where do all the lost ones go
                Chasing echoes down below
                Neon skyline fading slow
                """
            ),
            Track(
                title: "Paper Moon",
                artist: "Luna Echo",
                albumTitle: "Midnight Vinyl",
                duration: 198,
                trackNumber: 2,
                side: .a,
                lyrics: """
                Fold me up like a paper moon
                Hang me in the sky too soon
                Silver thread and a borrowed tune
                Spinning in the afternoon

                We were paper thin and burning bright
                Catching fire in the fading light
                Every page we wrote took flight
                Disappearing out of sight

                Paper moon above the city line
                Fragile but the glow was mine
                Held together by design
                Paper moon you shine

                Cut me out from the morning news
                Paste me where the dreamers cruise
                Nothing fancy nothing to prove
                Just a silhouette that wants to move
                """
            ),
            Track(
                title: "Velvet Hour",
                artist: "Luna Echo",
                albumTitle: "Midnight Vinyl",
                duration: 267,
                trackNumber: 3,
                side: .a,
                lyrics: """
                The velvet hour comes creeping in
                Soft as whispers on the skin
                Clock stops ticking where to begin
                When the night is wearing thin

                Pour another glass of time
                Let the melody unwind
                Every note a valentine
                Lost between the yours and mine

                In the velvet hour we stay
                Where the dark meets light of day
                Nothing more we need to say
                Let the music lead the way

                Curtains drawn the candles low
                Shadows putting on a show
                This is all we need to know
                In the velvet afterglow
                """
            ),
            Track(
                title: "Concrete Garden",
                artist: "Luna Echo",
                albumTitle: "Midnight Vinyl",
                duration: 212,
                trackNumber: 4,
                side: .b,
                lyrics: """
                Growing flowers in the cracks
                Between the concrete and the tracks
                Little green rebellious acts
                Nature always pushing back

                We planted seeds in parking lots
                Watched them bloom like afterthoughts
                Beautiful forgotten spots
                Connecting all the dots

                Concrete garden standing tall
                Breaking through the urban sprawl
                Roots that climb the factory wall
                Answering a wilder call
                """
            ),
            Track(
                title: "Last Frequency",
                artist: "Luna Echo",
                albumTitle: "Midnight Vinyl",
                duration: 289,
                trackNumber: 5,
                side: .b,
                lyrics: """
                Tune the dial to the end
                Past the static past the bend
                One last signal left to send
                On this frequency my friend

                We broadcasted through the storm
                Every wavelength keeping warm
                Sound and fury taking form
                Beautiful beyond the norm

                Last frequency signing off
                Not a whisper not a scoff
                Just the hum before the soft
                Silence carries us aloft

                Turn the volume all the way
                Let the final chorus play
                Every note a new bouquet
                Blooming at the break of day
                """
            )
        ]

        return Album(
            title: "Midnight Vinyl",
            artist: "Luna Echo",
            releaseYear: 2024,
            genre: "Dream Pop",
            colorHex: "#4A2C82",
            tracks: tracks,
            artworkURL: nil,
            addedDate: Date()
        )
    }

    // MARK: Album 2 — Analog Heart (Synth/Electronic)

    private static func demoAlbum2() -> Album {
        let tracks = [
            Track(
                title: "Digital Sunrise",
                artist: "Circuit Theory",
                albumTitle: "Analog Heart",
                duration: 245,
                trackNumber: 1,
                side: .a,
                lyrics: """
                Binary stars above my head
                Zeros ones the words unsaid
                Pixel dawn in shades of red
                Following the path you led

                Every circuit tells a tale
                Of a love beyond the pale
                Voltage rising without fail
                Riding on the data trail

                Digital sunrise breaking through
                Every color coded new
                Synthesized in morning dew
                Everything reminds me of you

                Motherboard beneath my chest
                Processing what we had best
                Every signal every test
                You were different from the rest
                """
            ),
            Track(
                title: "Analog Heart",
                artist: "Circuit Theory",
                albumTitle: "Analog Heart",
                duration: 278,
                trackNumber: 2,
                side: .a,
                lyrics: """
                In a world of ones and zeros
                You were warm and undefined
                Not a program not a sequence
                Something I could never find

                Your analog heart beats softly
                Through the noise of modern days
                A signal pure and undistorted
                Cutting through the digital haze

                Analog heart keep beating
                Through the static and the snow
                Every wave a gentle greeting
                From a frequency below

                They can digitize the future
                Compress the sound until it breaks
                But your analog heart keeps humming
                With the music that it makes
                """
            ),
            Track(
                title: "Waveform",
                artist: "Circuit Theory",
                albumTitle: "Analog Heart",
                duration: 196,
                trackNumber: 3,
                side: .b,
                lyrics: """
                Riding on a waveform
                Sine and cosine intertwined
                Every peak a new platform
                Every valley redesigned

                Amplitude of what we share
                Frequency beyond compare
                Oscillating through the air
                Mathematics of the rare

                Waveform carry me away
                To the shores of yesterday
                Where the signals used to play
                In beautiful array
                """
            ),
            Track(
                title: "Tape Hiss",
                artist: "Circuit Theory",
                albumTitle: "Analog Heart",
                duration: 223,
                trackNumber: 4,
                side: .b,
                lyrics: """
                Listen to the tape hiss
                Background noise of better times
                Every crackle every kiss
                Recorded between the lines

                Magnetic strip remembers all
                The summer nights the autumn fall
                Pressed rewind against the wall
                Answering the siren call

                Tape hiss is the sound of home
                Of voices through the telephone
                Of songs we sang of seeds we've sown
                Beautiful and overblown
                """
            )
        ]

        return Album(
            title: "Analog Heart",
            artist: "Circuit Theory",
            releaseYear: 2023,
            genre: "Electronic",
            colorHex: "#1DB954",
            tracks: tracks,
            editions: [
                VinylEdition(
                    label: "Retro Records",
                    catalogNumber: "RR-042",
                    country: "Japan",
                    vinylColor: .clear
                )
            ],
            artworkURL: nil,
            addedDate: Date().addingTimeInterval(-86400)
        )
    }

    // MARK: Album 3 — Autumn Letters (Folk/Acoustic)

    private static func demoAlbum3() -> Album {
        let tracks = [
            Track(
                title: "October Rain",
                artist: "Willow & Pine",
                albumTitle: "Autumn Letters",
                duration: 256,
                trackNumber: 1,
                side: .a,
                lyrics: """
                October rain on windowpanes
                A letter left beside the door
                The ink has bled through autumn veins
                Saying things unsaid before

                Maple leaves like postcards sent
                From trees that knew us way back when
                Every branch a sentiment
                We may not feel again

                October rain keeps falling down
                On every rooftop in this town
                Washing colors gold and brown
                Into rivers underground

                I read your words between the drops
                Each syllable a gentle knock
                Time may pass but never stops
                The turning of the autumn clock
                """
            ),
            Track(
                title: "Fireside",
                artist: "Willow & Pine",
                albumTitle: "Autumn Letters",
                duration: 201,
                trackNumber: 2,
                side: .a,
                lyrics: """
                Gather round the fireside
                Stories older than the flame
                Embers drifting far and wide
                Nothing ever stays the same

                Grandma's quilt around my knees
                Cider steaming in a cup
                Crackling logs and maple trees
                The world outside is looking up

                Fireside where the shadows dance
                Every flicker is a chance
                To remember old romance
                In the warmth of circumstance
                """
            ),
            Track(
                title: "Harvest Moon Walk",
                artist: "Willow & Pine",
                albumTitle: "Autumn Letters",
                duration: 312,
                trackNumber: 3,
                side: .b,
                lyrics: """
                Walking underneath the harvest moon
                Corn stalks standing like a silver choir
                Humming an old familiar tune
                Fields of gold and amber fire

                Your hand in mine along the ridge
                The whole world spread below our feet
                We crossed the old stone bridge
                Where the river and the meadow meet

                Harvest moon show us the way
                Through the night and into day
                Light the path where lovers stray
                Golden bright in soft display

                When the season starts to turn
                And the leaves begin to fall
                In the light of what we learn
                Love is still the greatest of them all
                """
            )
        ]

        let album = Album(
            title: "Autumn Letters",
            artist: "Willow & Pine",
            releaseYear: 2022,
            genre: "Folk",
            colorHex: "#D4760A",
            tracks: tracks,
            editions: [
                VinylEdition(
                    label: "Woodland Press",
                    catalogNumber: "WP-017",
                    country: "UK",
                    vinylColor: .orange
                )
            ],
            artworkURL: nil,
            addedDate: Date().addingTimeInterval(-172800)
        )
        album.tags = ["acoustic", "cozy"]
        return album
    }
}
#endif

// MARK: - App Icon Picker Sheet

struct AppIconPickerSheet: View {
    @ObservedObject var appIconManager: AppIconManager
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppIcon.allCases) { icon in
                            let isSelected = appIconManager.currentIcon == icon

                            Button {
                                appIconManager.setIcon(icon)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(icon.previewImageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    isSelected ? styleManager.theme.accentColor : Color.primary.opacity(0.1),
                                                    lineWidth: isSelected ? 2.5 : 0.5
                                                )
                                        )
                                        .shadow(color: isSelected ? styleManager.theme.accentColor.opacity(0.3) : .clear, radius: 6)

                                    Text(icon.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L("settings.app_icon"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Language Picker Sheet

struct LanguagePickerSheet: View {
    @ObservedObject var localizationManager: LocalizationManager
    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: String
    @State private var showConfirmAlert = false

    init(localizationManager: LocalizationManager) {
        self.localizationManager = localizationManager
        _selectedLanguage = State(initialValue: localizationManager.selectedLanguage)
    }

    private var hasChanged: Bool {
        selectedLanguage != localizationManager.selectedLanguage
    }

    private var selectedDisplayName: String {
        LocalizationManager.AppLanguage(rawValue: selectedLanguage)?.displayName ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 12) {
                    ForEach(LocalizationManager.AppLanguage.allCases) { language in
                        let isSelected = selectedLanguage == language.rawValue

                        Button {
                            withAnimation(.spring(duration: 0.15)) {
                                selectedLanguage = language.rawValue
                            }
                            HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: language == .system ? "gear" : "globe")
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                                    .frame(width: 32)

                                Text(language.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(styleManager.theme.textPrimary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(styleManager.theme.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected
                                          ? styleManager.theme.accentColor.opacity(0.08)
                                          : styleManager.theme.surfaceColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle(L("settings.language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if hasChanged {
                            showConfirmAlert = true
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                     .buttonStyle(.borderedProminent)
                    .tint(styleManager.theme.accentColor)
                    .disabled(!hasChanged)
                }
            }
            .alert(
                L("settings.language_change_title"),
                isPresented: $showConfirmAlert
            ) {
                Button(L("album.cancel"), role: .cancel) {}
                Button(L("settings.language_confirm")) {
                    withAnimation(.spring(duration: 0.2)) {
                        localizationManager.selectedLanguage = selectedLanguage
                    }
                    dismiss()
                }
            } message: {
                Text(String(format: L("settings.language_change_message"), selectedDisplayName))
            }
        }
    }
}
