import SwiftUI

struct PersonalizationSettingsView: View {
    @EnvironmentObject var styleManager: StyleManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var appIconManager = AppIconManager.shared

    @State private var showAppearancePicker = false
    @State private var showThemePicker = false
    @State private var showHapticPicker = false
    @State private var showLyricsStylePicker = false
    @State private var showLanguagePicker = false
    @State private var showTurntableBasePicker = false
    @State private var showAppIconPicker = false

    var body: some View {
        ZStack {
            styleManager.theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Appearance section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(L("settings.appearance_section"))

                        SettingsGroupedCard {
                            SettingsNavigationRow(
                                icon: styleManager.appearanceMode.iconName,
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.appearance"),
                                value: styleManager.appearanceMode.displayName
                            ) {
                                showAppearancePicker = true
                            }

                            settingsDivider

                            SettingsNavigationRow(
                                icon: "paintpalette",
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.visual_style"),
                                value: styleManager.theme.displayName
                            ) {
                                showThemePicker = true
                            }

                            settingsDivider

                            SettingsNavigationRow(
                                icon: "app.badge",
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.app_icon"),
                                value: appIconManager.currentIcon.displayName
                            ) {
                                showAppIconPicker = true
                            }
                        }
                    }

                    // Player section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(L("settings.player_section"))

                        SettingsGroupedCard {
                            SettingsNavigationRow(
                                icon: "waveform",
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.haptic"),
                                value: styleManager.hapticIntensity.displayName
                            ) {
                                showHapticPicker = true
                            }

                            settingsDivider

                            SettingsNavigationRow(
                                icon: styleManager.lyricsDisplayMode.iconName,
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.lyrics_style"),
                                value: styleManager.lyricsDisplayMode.displayName
                            ) {
                                showLyricsStylePicker = true
                            }

                            settingsDivider

                            SettingsNavigationRow(
                                icon: "square.on.square",
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.turntable_base"),
                                value: styleManager.turntableBaseStyle.displayName
                            ) {
                                showTurntableBasePicker = true
                            }
                        }
                    }

                    // General section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(L("settings.general_section"))

                        SettingsGroupedCard {
                            SettingsNavigationRow(
                                icon: "globe",
                                iconColor: styleManager.theme.accentColor,
                                title: L("settings.language"),
                                value: currentLanguageDisplayName
                            ) {
                                showLanguagePicker = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(L("settings.personalization"))
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(isPresented: $showAppIconPicker) {
            AppIconPickerSheet(appIconManager: appIconManager)
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
    }

    private var currentLanguageDisplayName: String {
        let code = localizationManager.selectedLanguage
        return LocalizationManager.AppLanguage(rawValue: code)?.displayName ?? "System"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
            .tracking(0.5)
            .padding(.leading, 4)
    }

    private var settingsDivider: some View {
        Divider()
            .background(styleManager.theme.textSecondary.opacity(0.1))
            .padding(.leading, 56)
    }
}
