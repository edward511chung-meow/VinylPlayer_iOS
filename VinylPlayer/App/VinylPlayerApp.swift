import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit

@main
struct VinylPlayerApp: App {
    @StateObject private var collectionVM = CollectionViewModel()
    @StateObject private var styleManager = StyleManager()
    @StateObject private var musicServiceManager = MusicServiceManager()
    @ObservedObject private var localizationManager = LocalizationManager.shared

    init() {
        // Session activation can block while negotiating a route. Submit this
        // before local sound effects, on their shared serial audio queue.
        AudioExecutionQueue.shared.async {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playback, mode: .default, options: [])
                try audioSession.setActive(true)
                print("[Audio] Session configured: category=playback")
            } catch {
                print("[Audio] Failed to configure audio session: \(error)")
            }
        }

        // Configure tab bar appearance
        let savedTheme: StyleTheme
        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.selectedStyleTheme),
           let theme = StyleTheme(rawValue: saved) {
            savedTheme = theme
        } else {
            savedTheme = .modern
        }
        UITabBar.appearance().tintColor = UIColor(savedTheme.accentColor)
        UITabBar.appearance().unselectedItemTintColor = UIColor.secondaryLabel

        // End any stale Live Activities from previous sessions
        for activity in Activity<NowPlayingAttributes>.activities {
            let state = NowPlayingAttributes.ContentState(isPlaying: false, progress: 0, elapsedTime: 0)
            let content = ActivityContent(state: state, staleDate: nil)
            Task {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }

    @ViewBuilder
    private var appRoot: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--metadata-design-preview") {
            HomeDesignPreview(screen: "metadata")
        } else if ProcessInfo.processInfo.arguments.contains("--search-design-preview") {
            HomeDesignPreview(screen: "search")
        } else if ProcessInfo.processInfo.arguments.contains("--backup-design-preview") {
            HomeDesignPreview(screen: "backup")
        } else if ProcessInfo.processInfo.arguments.contains("--sleep-design-preview") {
            HomeDesignPreview(screen: "sleep")
        } else if ProcessInfo.processInfo.arguments.contains("--library-design-preview") {
            HomeDesignPreview(showsLibrary: true)
        } else if ProcessInfo.processInfo.arguments.contains("--home-design-preview") {
            HomeDesignPreview()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            appRoot
                .modelContainer(for: [Album.self, ListeningRecord.self, LibraryPlaylist.self])
                .environmentObject(collectionVM)
                .environmentObject(styleManager)
                .environmentObject(musicServiceManager)
                .tint(styleManager.theme.accentColor)
                .preferredColorScheme(styleManager.preferredColorScheme)
                .id(localizationManager.selectedLanguage) // Force full UI refresh on language change
                .onAppear {
                    NowPlayingManager.shared.configure(
                        collectionVM: collectionVM,
                        musicServiceManager: musicServiceManager
                    )
                }
                .onOpenURL { url in
                    // Handle Spotify OAuth callback
                    if url.scheme == "vinylplayer" && url.host == "spotify-callback" {
                        musicServiceManager.handleSpotifyCallback(url: url)
                    }
                }
        }
    }
}
