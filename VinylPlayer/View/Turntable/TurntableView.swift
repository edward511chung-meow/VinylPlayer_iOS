import SwiftUI
import Combine

struct TurntableView: View {
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.scenePhase) private var scenePhase
    @Binding var isExpanded: Bool

    // Vinyl spin animator (CADisplayLink-based, syncs with display refresh)
    // Retain the animator without observing its 60/120 Hz `rotation` changes
    // here. Only the disc's rotation modifiers observe them, so the display link
    // does not invalidate the entire full-player and lyrics hierarchy.
    @State private var vinylAnimator = VinylAnimator()

    // Needle
    @State private var needleLifted = false
    @State private var needleIsParked = true

    // Seek
    @State private var isSeeking = false
    @State private var seekProgress: Double = 0

    // Lyrics highlight & manual scroll
    @State private var currentLyricIndex: Int = 0
    @State private var isLyricDragging = false
    @State private var lyricDragIndex: Int = 0
    @State private var lastLyricDragTranslationY: CGFloat = 0
    @State private var intraLineProgress: Double = 0  // 0...1 progress within current line
    @State private var markerIntraLineProgress: Double = 0
    @State private var lyricPlaybackAnchor = LyricPlaybackAnchor(position: 0, date: .now, isPlaying: false)

    // Vinyl manual rotation seek
    @State private var isVinylDragging = false
    @State private var vinylDragStartAngle: Double = 0
    @State private var vinylDragStartProgress: Double = 0
    @State private var lastDragAngle: Double = 0
    @State private var lastDragTime: Date = .now

    // Sound effects
    private let soundEngine = VinylSoundEngine.shared

    // Dominant color from album artwork
    @State private var dominantColor: Color?
    @State private var albumImage: UIImage?

    // Lyrics visibility toggle
    @State private var showLyrics = true
    // Controls visibility toggle
    @State private var showControls = true
    @State private var controlsWereAutoHidden = false
    @State private var lyricsControlsAutoHideTask: Task<Void, Never>?
    // Queue sheet
    @State private var showQueueSheet = false
    @State private var previewAlbumDetail: Album?
    // Share sheet
    @State private var showShareSheet = false
    // Freeze expensive lyric rendering while a player sheet is composited.
    @State private var isPlayerSheetPresented = false

    // Namespace for matchedGeometryEffect (vinyl centering animation)
    @Namespace private var vinylNamespace

    private let lyricsControlsAutoHideDelay: Duration = .seconds(4)

    /// Whether the dominant color is light (luminance > 0.5), used to pick text color scheme.
    private var isDominantColorLight: Bool {
        guard let dominantColor else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(dominantColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        // Relative luminance formula (ITU-R BT.709)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.5
    }

    private let dismissDragDirectionRatio: CGFloat = 1.15
    private let dismissDragMinimumDistance: CGFloat = 12
    
    var playerAnimation: Namespace.ID
    private let miniPlayerBottomInset: CGFloat
    private let expandedCornerRadius: CGFloat
    
    var height = UIScreen.main.bounds.height / 3
    
    // Gesture Offset
    // Only the translation modifier observes per-frame drag updates.
    @State private var dismissTranslation = PlayerDismissTranslation()
    @State private var isPlayerDismissDragging = false
    @State private var miniSwipeOffset: CGFloat = 0
    @GestureState private var miniSwipeTranslation: CGFloat = 0
    
    // Safe Area
    var safeArea = UIApplication.shared.windows.first?.safeAreaInsets

    init(
        isExpanded: Binding<Bool>,
        playerAnimation: Namespace.ID,
        miniPlayerBottomInset: CGFloat = 0,
        expandedCornerRadius: CGFloat = 32
    ) {
        self._isExpanded = isExpanded
        self.playerAnimation = playerAnimation
        self.miniPlayerBottomInset = miniPlayerBottomInset
        self.expandedCornerRadius = expandedCornerRadius
    }
    
    private var screenBounds: CGRect { UIScreen.main.bounds }
    private var screenWidth: CGFloat { screenBounds.width }
    private var screenHeight: CGFloat { screenBounds.height }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full player background gradient
            dominantBackgroundGradient
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(false)

            // Keep the full-player's measured geometry alive until the
            // matched transition has finished. Collapsing this frame to zero
            // here makes SwiftUI repeatedly re-resolve the source geometry
            // while the outer container is also changing height.
            fullPlayerContent(fullWidth: screenWidth, fullHeight: screenHeight)
                .frame(width: screenWidth, height: screenHeight)
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)

            // Mini player header (always in hierarchy, hidden via opacity when expanded)
            miniPlayerHeader
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)
        }
        // The full-player stays measured at screen size for a stable matched
        // transition. When collapsed, reveal the bottom 64pt (where the mini
        // player lives) instead of the frame modifier's default centre slice.
        .frame(width: isExpanded ? screenWidth : screenWidth - 16)
        .frame(height: isExpanded ? screenHeight : 64, alignment: .bottom)
        .background {
            // Consume taps in the full player's empty areas as well as controls.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isExpanded { setExpanded(true) }
                }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: isExpanded ? expandedCornerRadius : 16,
                bottomLeadingRadius: isExpanded ? 0 : 16,
                bottomTrailingRadius: isExpanded ? 0 : 16,
                topTrailingRadius: isExpanded ? expandedCornerRadius : 16
            )
        )
        .modifier(PlayerDismissTranslationEffect(translation: dismissTranslation))
        .padding(.bottom, isExpanded ? 0 : miniPlayerBottomInset)
        // Keep one coordinate space throughout the transition. Switching safe
        // area rules halfway through a spring changes its layout endpoints.
        .ignoresSafeArea(.container)
        .frame(width: screenWidth, alignment: .bottom)
        // Scope the expand/collapse animation to the player subtree. Using
        // `withAnimation` when mutating the parent binding sends the same
        // transaction through ContentView and animates unrelated collection
        // toolbar and scrubber layout updates.
        .animation(playerTransitionAnimation, value: isExpanded)
        .onChange(of: collectionVM.isPlaying) { _, playing in
            if playing {
                // Starting from a freshly selected track swings the arm from
                // its rest to the lead-in groove. Resuming a paused track keeps
                // the arm at its current progress and simply lowers it again.
                needleIsParked = false
                needleLifted = false
            } else {
                // Pause lifts vertically but does not return the arm to rest.
                needleLifted = true
            }
            vinylAnimator.isPlaying = playing
            if playing {
                scheduleLyricsControlsAutoHide()
            } else {
                cancelLyricsControlsAutoHide(revealIfNeeded: true)
            }
        }
        .onChange(of: scenePhase) { _, _ in
            updateVinylAnimationVisibility()
        }
        .onChange(of: reduceMotion) { _, value in
            vinylAnimator.reduceMotion = value
        }
        .onChange(of: isExpanded) { _, expanded in
            updateVinylAnimationVisibility()
            if expanded {
                cancelLyricsControlsAutoHide(revealIfNeeded: true)
                scheduleLyricsControlsAutoHide()
            } else {
                cancelLyricsControlsAutoHide(revealIfNeeded: false)
            }
        }
        .onChange(of: lyricLines.isEmpty) { _, lyricsAreEmpty in
            if lyricsAreEmpty {
                cancelLyricsControlsAutoHide(revealIfNeeded: true)
            } else {
                scheduleLyricsControlsAutoHide()
            }
        }
        .onChange(of: needleLifted) { _, lifted in
            vinylAnimator.needleLifted = lifted
        }
        .onChange(of: collectionVM.currentRPM) { _, rpm in
            vinylAnimator.rpm = rpm
        }
        .onChange(of: collectionVM.playbackProgress) { _, progress in
            // Keep the full-player hierarchy stable while its interactive
            // dismissal is resolving. The service can catch the lyric state
            // up on the next progress tick after the transition.
            if !isLyricDragging && !isPlayerDismissDragging {
                updateCurrentLyricIndex(progress: progress)
            }
        }
        .onChange(of: isSeeking) { _, seeking in
            if seeking {
                cancelLyricsControlsAutoHide(revealIfNeeded: false)
            } else {
                scheduleLyricsControlsAutoHide()
            }
        }
        .onChange(of: collectionVM.currentAlbum) { _, _ in
            extractDominantColor()
        }
        // Auto-start playback & load lyrics when track changes
        .onChange(of: collectionVM.currentTrack?.id) { oldId, newId in
            needleIsParked = !collectionVM.isPlaying
            needleLifted = !collectionVM.isPlaying
            guard let _ = newId, newId != oldId,
                  let album = collectionVM.currentAlbum,
                  let track = collectionVM.currentTrack else { return }
            // Preload lyrics immediately so they show without delay
            musicServiceManager.preloadLyrics(for: track)
            cancelLyricsControlsAutoHide(revealIfNeeded: true)
            scheduleLyricsControlsAutoHide()
        }
        .onAppear(perform: configurePlayerOnAppear)
        .onDisappear {
            cancelLyricsControlsAutoHide(revealIfNeeded: false)
            vinylAnimator.stop()
        }
        .fullScreenCover(item: $previewAlbumDetail) { album in
            AlbumDetailView(album: album)
                .environmentObject(collectionVM)
                .environmentObject(styleManager)
                .environmentObject(musicServiceManager)
        }
        .sheet(isPresented: $showQueueSheet, onDismiss: resumeVinylAnimationAfterSheet) {
            QueueSheetView()
                .environmentObject(collectionVM)
                .environmentObject(styleManager)
                .environmentObject(musicServiceManager)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: resumeVinylAnimationAfterSheet) {
            if let album = collectionVM.currentAlbum {
                ShareSheetView(
                    data: ShareCardData(
                        album: album,
                        track: collectionVM.currentTrack,
                        lyrics: lyricLines.isEmpty ? nil : lyricLines,
                        currentLyricIndex: lyricLines.isEmpty ? nil : currentLyricIndex,
                        lyricLines: musicServiceManager.currentLyrics.isEmpty ? nil : musicServiceManager.currentLyrics,
                        baseStyle: styleManager.turntableBaseStyle,
                        playbackProgress: collectionVM.playbackProgress,
                        isPlaying: collectionVM.isPlaying,
                        rpm: collectionVM.currentRPM,
                        tonearmColor: styleManager.theme.tonearmColor,
                        needleLifted: needleLifted,
                        needleParked: needleIsParked,
                        lyricFillProgress: intraLineProgress,
                        lyricMarkerProgress: markerIntraLineProgress
                    )
                )
                .environmentObject(styleManager)
            }
        }
        // Sync real playback state from music service
        .onChange(of: musicServiceManager.playbackState) { _, state in
            lyricPlaybackAnchor = LyricPlaybackAnchor(position: state.currentTime, date: .now, isPlaying: state.isPlaying)
            // Don't overwrite progress while user is seeking
            if state.duration > 0,
               !isPlayerSheetPresented,
               !isSeeking,
               !isVinylDragging,
               !isLyricDragging,
               !isPlayerDismissDragging {
                collectionVM.playbackProgress = state.progress


            }
        }
    }

    private func configurePlayerOnAppear() {
            let playback = musicServiceManager.playbackState
            lyricPlaybackAnchor = LyricPlaybackAnchor(position: playback.currentTime, date: .now, isPlaying: playback.isPlaying)
            extractDominantColor()
            // Preload lyrics from SwiftData so they show immediately
            if let track = collectionVM.currentTrack {
                musicServiceManager.preloadLyrics(for: track)
            }
            // A fresh, unplayed selection starts on the rest. A track paused
            // after making progress keeps its arm over the current groove.
            configureInitialNeedleState()
            // Configure and start display-link animator
            vinylAnimator.isPlaying = collectionVM.isPlaying
            vinylAnimator.needleLifted = needleLifted
            vinylAnimator.rpm = collectionVM.currentRPM
            vinylAnimator.reduceMotion = reduceMotion
            updateVinylAnimationVisibility()
            scheduleLyricsControlsAutoHide()

            // Preview fallback; the bound queue owns playback requests in the app.
            if collectionVM.onPlaybackSelection == nil, collectionVM.isPlaying,
               let album = collectionVM.currentAlbum,
               let track = collectionVM.currentTrack,
               !musicServiceManager.isCurrentTrack(track) {
                Task {
                    do {
                        try await musicServiceManager.play(track: track, in: album)
                    } catch {
                        print("[Playback] onAppear auto-play error: \(error)")
                    }
                }
            }
    }

    private func configureInitialNeedleState() {
        if collectionVM.currentTrack == nil {
            needleIsParked = true
        } else {
            needleIsParked = !collectionVM.isPlaying
                && collectionVM.playbackProgress <= 0.001
        }
        needleLifted = !collectionVM.isPlaying
    }
    
    func onchanged(value: DragGesture.Value) {
        // Only allowing when its expanded...
        if value.translation.height > 0 && isExpanded {
            if !isPlayerDismissDragging {
                isPlayerDismissDragging = true
                // Prevent the four-second controls transition from changing
                // the full-player's layout in the middle of this gesture.
                cancelLyricsControlsAutoHide(revealIfNeeded: false)
            }
            dismissTranslation.offset = value.translation.height
        }
    }
    
    func onended(value: DragGesture.Value) {
        let shouldCollapse = value.translation.height > height

        if shouldCollapse {
            // `setExpanded` owns the only animation transaction. Previously
            // this path nested a default spring inside an interactive spring,
            // so the layout and gesture offset followed different curves and
            // visibly bounced against one another.
            setExpanded(false)
        } else {
            withAnimation(playerTransitionAnimation) {
                dismissTranslation.offset = 0
            }
        }

        // Defer progress-driven lyric updates until the current gesture
        // transaction has been committed.
        DispatchQueue.main.async {
            isPlayerDismissDragging = false
            if !shouldCollapse {
                scheduleLyricsControlsAutoHide()
            }
        }
    }

    private var playerTransitionAnimation: Animation {
        .interactiveSpring(response: 0.5, dampingFraction: 0.95, blendDuration: 0.95)
    }

    private func setExpanded(_ expanded: Bool) {
        // Send a non-animated transaction through the binding. The local
        // `.animation(value:)` above then supplies the spring only inside the
        // player subtree.
        // Settle the isolated translation with the same spring as the frame.
        withAnimation(playerTransitionAnimation) {
            dismissTranslation.offset = 0
        }
        withTransaction(Transaction(animation: nil)) {
            isExpanded = expanded
        }
    }

    private func updateVinylAnimationVisibility() {
        if isExpanded && scenePhase == .active && !isPlayerSheetPresented {
            vinylAnimator.start()
        } else {
            vinylAnimator.stop()
        }
    }

    private func pauseVinylAnimationForSheet() {
        // A presented sheet already adds its own compositing and backdrop work.
        // Freeze the frame-driven disc underneath so both render pipelines do
        // not compete during presentation and dismissal.
        cancelLyricsControlsAutoHide(revealIfNeeded: false)
        isPlayerSheetPresented = true
        vinylAnimator.stop()
    }

    private func resumeVinylAnimationAfterSheet() {
        // Catch the frozen UI up to the live service only after the sheet's
        // dismissal compositing has completed.
        let state = musicServiceManager.playbackState
        if state.duration > 0 {
            collectionVM.playbackProgress = state.progress
        }
        isPlayerSheetPresented = false
        vinylAnimator.isPlaying = collectionVM.isPlaying
        vinylAnimator.needleLifted = needleLifted
        vinylAnimator.rpm = collectionVM.currentRPM
        vinylAnimator.reduceMotion = reduceMotion
        updateVinylAnimationVisibility()
        scheduleLyricsControlsAutoHide()
    }

    private var miniEffectiveSwipeOffset: CGFloat {
        miniSwipeOffset + miniSwipeTranslation * 0.35
    }

    private var miniPlayerHeader: some View {
        ZStack(alignment: .leading) {
            miniPlayerTapBackground

            miniPlayerSlidingText
                .zIndex(0)

            miniPlayerAlbumCover
                .zIndex(2)

            miniPlayerTrailingControls
                .zIndex(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            AlbumPreviewContextMenu(album: collectionVM.currentAlbum, track: collectionVM.currentTrack,
                                    enabled: !isExpanded, receivesTouches: true,
                                    onTap: { setExpanded(true) },
                                    onPan: { translation, ended in
                guard collectionVM.currentTrack != nil else { return }
                if ended {
                    if translation < -44 { completeMiniTrackSwipe(direction: .next) }
                    else if translation > 44 { completeMiniTrackSwipe(direction: .previous) }
                    else { withAnimation(.spring(duration: 0.25)) { miniSwipeOffset = 0 } }
                } else {
                    miniSwipeOffset = translation * 0.35
                }
            }, menu: {
                UIMenu(children: [
                    albumContextAction(collectionVM.isPlaying ? "Pause" : "Play",
                                       symbol: collectionVM.isPlaying ? "pause.fill" : "play.fill") {
                        togglePlaybackFromMiniPlayer()
                    },
                    albumContextAction("Queue", symbol: "list.bullet") {
                        pauseVinylAnimationForSheet()
                        showQueueSheet = true
                    },
                    albumContextAction("Share", symbol: "square.and.arrow.up") {
                        pauseVinylAnimationForSheet()
                        showShareSheet = true
                    }
                ])
            }, onOpen: { album in previewAlbumDetail = album })
            .padding(.trailing, 112)
        }
    }

    private var miniPlayerExpandTapGesture: some Gesture {
        TapGesture()
            .onEnded {
                guard !isExpanded else { return }
                setExpanded(true)
            }
    }

    private var miniPlayerTapBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(miniPlayerExpandTapGesture)
    }

    private var miniPlayerAlbumCover: some View {
        Group {
            if let album = collectionVM.currentAlbum {
                AlbumCoverView(album: album, size: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(styleManager.theme.surfaceColor)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(styleManager.theme.textSecondary)
                            .font(.system(size: 16))
                    )
            }
        }
        .matchedGeometryEffect(id: "Album", in: playerAnimation, isSource: !isExpanded)
        .contentShape(Rectangle())
        .gesture(miniPlayerExpandTapGesture)
    }

    private var miniPlayerSlidingText: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    Text(collectionVM.currentTrack?.title ?? L("player.not_playing"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(styleManager.theme.textPrimary)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "Title", in: playerAnimation, isSource: !isExpanded)
                }

                if let artist = collectionVM.currentTrack?.artist {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundColor(styleManager.theme.textSecondary)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "Artist", in: playerAnimation, isSource: !isExpanded)
                }
            }
            .offset(x: miniEffectiveSwipeOffset)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, 64)
        .padding(.trailing, 112)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(miniPlayerExpandTapGesture)
        .simultaneousGesture(collectionVM.currentTrack == nil ? nil : miniPlayerTrackSwipeGesture)
    }

    private var miniPlayerTrailingControls: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            Button {
                togglePlaybackFromMiniPlayer()
            } label: {
                Image(systemName: collectionVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(
                        collectionVM.currentTrack != nil
                        ? styleManager.theme.textPrimary
                        : styleManager.theme.textSecondary.opacity(0.4)
                    )
                    .frame(width: 40, height: 40)
            }
            .disabled(collectionVM.currentTrack == nil)

            Button {
                collectionVM.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(
                        collectionVM.currentTrack != nil
                        ? styleManager.theme.textPrimary
                        : styleManager.theme.textSecondary.opacity(0.4)
                    )
                    .frame(width: 36, height: 36)
            }
            .disabled(collectionVM.currentTrack == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var miniPlayerTrackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($miniSwipeTranslation) { value, state, _ in
                guard collectionVM.currentTrack != nil else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                state = value.translation.width
            }
            .onEnded { value in
                let threshold: CGFloat = 44
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4
                guard isHorizontal, collectionVM.currentTrack != nil else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.05)) {
                        miniSwipeOffset = 0
                    }
                    return
                }

                if value.translation.width < -threshold {
                    completeMiniTrackSwipe(direction: .next)
                } else if value.translation.width > threshold {
                    completeMiniTrackSwipe(direction: .previous)
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.05)) {
                        miniSwipeOffset = 0
                    }
                }
            }
    }

    private enum MiniTrackSwipeDirection {
        case next
        case previous
    }

    private func completeMiniTrackSwipe(direction: MiniTrackSwipeDirection) {
        let exitOffset: CGFloat = direction == .next ? -180 : 180
        let enterOffset: CGFloat = direction == .next ? 180 : -180

        withAnimation(.spring(duration: 0.16)) {
            miniSwipeOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            switch direction {
            case .next:
                moveMiniPlayerTrackToNextWithWrap()
            case .previous:
                moveMiniPlayerTrackToPreviousWithWrap()
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                miniSwipeOffset = enterOffset
            }

            withAnimation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.06)) {
                miniSwipeOffset = 0
            }
        }
    }

    private func moveMiniPlayerTrackToNextWithWrap() { collectionVM.nextTrack() }
    private func moveMiniPlayerTrackToPreviousWithWrap() { collectionVM.previousTrack() }

    private var miniPlayerPlaylist: [Track] {
        guard let album = collectionVM.currentAlbum else { return [] }
        return album.tracks.sorted { lhs, rhs in
            let lhsSide = lhs.side.rawValue
            let rhsSide = rhs.side.rawValue
            if lhsSide != rhsSide {
                return lhsSide < rhsSide
            }
            return lhs.trackNumber < rhs.trackNumber
        }
    }

    private func setMiniPlayerTrack(_ track: Track) {
        collectionVM.currentTrack = track
        collectionVM.playbackProgress = 0
        seekProgress = 0

        if collectionVM.isPlaying,
           let album = collectionVM.currentAlbum {
            Task {
                do {
                    try await musicServiceManager.play(track: track, in: album)
                } catch {
                    print("[Playback] ERROR setting wrapped mini player track: \(error)")
                }
            }
        }
    }

    private func fullPlayerContent(fullWidth: CGFloat, fullHeight: CGFloat) -> some View {
        return ZStack {
            // Full-screen vinyl + radial lyrics
            vinylAndRadialLyrics(screenWidth: fullWidth, screenHeight: fullHeight)
                .frame(width: fullWidth, height: fullHeight)

            // Controls overlay at bottom
            VStack {
                fullPlayerDragIndicator
                    .frame(width: 64, height: 8)
                    .opacity(isExpanded ? 1 : 0)
                    .frame(width: 120, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isExpanded { setExpanded(false) }
                    }
                    .padding(.top, max(0, (safeArea?.top ?? 0) - 8))
                    // Dismissal is intentionally limited to the grabber. This
                    // keeps it out of the vinyl, lyrics, waveform and controls'
                    // interactive regions.
                    .simultaneousGesture(
                        isExpanded
                        ? DragGesture(minimumDistance: 12, coordinateSpace: .global)
                                .onEnded(onended(value:))
                                .onChanged(onchanged(value:))
                            : nil
                    )

                Spacer()

                if showControls {
                    VStack(spacing: 12) {
                        trackInfoBar

                        playbackControls
                            .padding(.top, 2)

                        waveformProgressBar
                            .padding(.horizontal, 24)

                        // Bottom row: keep the four lightweight actions direct.
                        HStack(spacing: 18) {
                            Button {
                                let lyricsWillBeVisible = !showLyrics
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showLyrics = lyricsWillBeVisible
                                }
                                if lyricsWillBeVisible {
                                    scheduleLyricsControlsAutoHide()
                                } else {
                                    cancelLyricsControlsAutoHide(revealIfNeeded: true)
                                }
                                HapticManager.shared.impact(styleManager.hapticIntensity)
                            } label: {
                                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                                    .font(.system(size: 18))
                                    .foregroundColor(
                                        showLyrics
                                            ? .primary
                                            : .secondary
                                    )
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)

                            Button {
                                pauseVinylAnimationForSheet()
                                showQueueSheet = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18))
                                    .foregroundColor(
                                        collectionVM.playbackQueue.isEmpty
                                            ? .secondary
                                            : styleManager.theme.accentColor
                                    )
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)

                            Button {
                                pauseVinylAnimationForSheet()
                                showShareSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)

                            Button {
                                controlsWereAutoHidden = false
                                cancelLyricsControlsAutoHide(revealIfNeeded: false)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    showControls = false
                                }
                                HapticManager.shared.impact(styleManager.hapticIntensity)
                            } label: {
                                Image(systemName: "arrow.up.right.and.arrow.down.left")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                        }
                        .padding(.bottom, 2)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(safeArea?.bottom ?? 0, 24) + 12)
                    // Overscan the backdrop above the controls so its feather
                    // begins outside the content instead of forming a visible
                    // horizontal boundary through the player UI.
                    .background(bottomControlsBackdrop.padding(.top, -72))
                    .environment(\.colorScheme, isDominantColorLight ? .light : .dark)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Floating button to show controls again
                    Button {
                        controlsWereAutoHidden = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showControls = true
                        }
                        scheduleLyricsControlsAutoHide()
                    } label: {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .environment(\.colorScheme, isDominantColorLight ? .light : .dark)
                    .padding(.bottom, max(safeArea?.bottom ?? 0, 24) + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: fullWidth, height: fullHeight)
        }
//        .frame(width: isExpanded ? nil : 0, height: isExpanded ? nil : 0)
//        .opacity(isExpanded ? 1 : 0)
        // .allowsHitTesting(isExpanded)
        // .clipped()
    }

    private func scheduleLyricsControlsAutoHide() {
        lyricsControlsAutoHideTask?.cancel()
        guard isExpanded,
              showControls,
              showLyrics,
              collectionVM.isPlaying,
              !isSeeking,
              !lyricLines.isEmpty else { return }

        lyricsControlsAutoHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: lyricsControlsAutoHideDelay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  isExpanded,
                  showControls,
                  showLyrics,
                  collectionVM.isPlaying,
                  !isSeeking,
                  !lyricLines.isEmpty else { return }

            controlsWereAutoHidden = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showControls = false
            }
        }
    }

    private func cancelLyricsControlsAutoHide(revealIfNeeded: Bool) {
        lyricsControlsAutoHideTask?.cancel()
        lyricsControlsAutoHideTask = nil

        if revealIfNeeded, controlsWereAutoHidden {
            controlsWereAutoHidden = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showControls = true
            }
        }
    }

    @ViewBuilder
    private var fullPlayerDragIndicator: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                }
                .shadow(color: Color.black.opacity(0.20), radius: 2, y: 1)
        }
    }

    /// Gaussian-style system backdrop blur for the full player's bottom
    /// control region, colour-tinted from the current album artwork.
    private var bottomControlsBackdrop: some View {
        let tintColor = dominantColor
            ?? collectionVM.currentAlbum?.color
            ?? styleManager.theme.backgroundColor

        return ZStack {
            Rectangle()
                .fill(.thinMaterial)

            LinearGradient(
                stops: [
                    .init(color: tintColor.opacity(0.04), location: 0),
                    .init(color: tintColor.opacity(0.12), location: 0.28),
                    .init(color: tintColor.opacity(0.25), location: 0.62),
                    .init(color: tintColor.opacity(0.36), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .compositingGroup()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.04), location: 0.06),
                    .init(color: .white.opacity(0.16), location: 0.12),
                    .init(color: .white.opacity(0.32), location: 0.18),
                    .init(color: .white.opacity(0.50), location: 0.24),
                    .init(color: .white.opacity(0.68), location: 0.30),
                    .init(color: .white.opacity(0.84), location: 0.36),
                    .init(color: .white.opacity(0.96), location: 0.42),
                    .init(color: .white, location: 0.48),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .allowsHitTesting(false)
    }

    private func togglePlaybackFromMiniPlayer() {
        musicServiceManager.togglePlayback()
    }

    // MARK: - Dominant Color Background

    /// Gradient background extracted from album artwork image.
    @ViewBuilder
    private var dominantBackgroundGradient: some View {
        if albumImage != nil {
            ImageGradient(
                image: albumImage,
                count: 3,
                animation: .spring(duration: 0.8)
            ) { colors in
                dominantColor = colors.first
            }
        } else if !lyricLines.isEmpty {
            // The lyrics layer supplies its own dominant-colour backdrop.
            // Keep a neutral base underneath it so the tint is not applied
            // twice and made unnaturally saturated. This remains true when
            // the lyrics are temporarily hidden because the backdrop stays.
            Rectangle()
                .fill(colorScheme == .dark ? Color.black : Color.white)
        } else {
            // An album can have a saved representative colour even when it
            // has no usable artwork image. Use that colour only when lyrics
            // are hidden or unavailable, where no tinted lyrics backdrop exists.
            let fallbackColor = dominantColor
                ?? collectionVM.currentAlbum?.color
                ?? styleManager.theme.backgroundColor

            ZStack {
                Rectangle()
                    .fill(fallbackColor)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    /// Extract album artwork as UIImage for ImageGradient.
    private func extractDominantColor() {
        guard let album = collectionVM.currentAlbum else {
            albumImage = nil
            dominantColor = nil
            return
        }

        // Try local image data first
        if let data = album.customCoverImageData,
           let image = UIImage(data: data) {
            albumImage = image
            return
        }

        // Try remote URL
        if let urlString = album.displayArtworkURL,
           let url = URL(string: urlString) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        albumImage = image
                    }
                }
            }
            return
        }

        // No artwork available — clear image, use album color as fallback
        albumImage = nil
        dominantColor = album.color
    }

    // MARK: - Lyrics Helpers

    /// Lyric lines from the music service — single source of truth.
    /// Uses musicServiceManager.currentLyrics which has real timestamps when available.
    private var lyricLines: [String] {
        let lyrics = musicServiceManager.currentLyrics
        guard !lyrics.isEmpty else { return [] }
        return lyrics.map { $0.text }
    }

    /// Map playback time to the current lyric line index and intra-line progress.
    /// Uses actual timestamps from musicServiceManager.currentLyrics.
    private func updateCurrentLyricIndex(progress: Double) {
        let lyrics = musicServiceManager.currentLyrics
        guard !lyrics.isEmpty else { return }

        let duration = musicServiceManager.playbackState.duration > 0
            ? musicServiceManager.playbackState.duration
            : (collectionVM.currentTrack?.duration ?? 240)
        let currentTime = duration * progress

        // Find the last lyric line whose startTime <= currentTime
        var idx = -1
        for (i, line) in lyrics.enumerated() {
            if line.startTime <= currentTime { idx = i }
            else { break }
        }

        if idx < 0 {
            // Before first lyric line (intro) — no karaoke effect
            currentLyricIndex = 0
            intraLineProgress = 0
            markerIntraLineProgress = 0
            return
        }

        let previousIdx = currentLyricIndex
        currentLyricIndex = idx

        // Compute intra-line progress from timestamps
        let lineStart = lyrics[idx].startTime
        let lineEnd = lyrics[idx].endTime
            ?? (idx + 1 < lyrics.count ? lyrics[idx + 1].startTime : lineStart + 4)
        let lineDuration = lineEnd - lineStart
        if lineDuration > 0 {
            intraLineProgress = min(1, max(0, (currentTime - lineStart) / lineDuration))
            let markerRevealDuration: TimeInterval = 0.50
            if idx != previousIdx || markerIntraLineProgress < 1 {
                // Reset without inheriting the lyric wheel's transition, then
                // draw one continuous 0.5-second felt-tip stroke from the
                // moment this line actually appears in the UI. Publishing
                // a target of 1 immediately also prevents coarse 0.25/1.0 s
                // playback samples from repeatedly interrupting the animation.
                withTransaction(Transaction(animation: nil)) {
                    markerIntraLineProgress = 0
                }

                let expectedIndex = idx
                DispatchQueue.main.async {
                    guard currentLyricIndex == expectedIndex,
                          collectionVM.isPlaying else { return }
                    withAnimation(
                        .timingCurve(0.18, 0.72, 0.30, 1.0, duration: markerRevealDuration)
                    ) {
                        markerIntraLineProgress = 1
                    }
                }
            }
        } else {
            intraLineProgress = 1
            markerIntraLineProgress = 1
        }
    }

    // MARK: - Vinyl + Radial Lyrics Layout

    private func vinylAndRadialLyrics(screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        // When lyrics hidden → center the vinyl; when shown → keep left position
        let lyricsVinylSize = screenWidth * 1.14
        let centeredVinylSize = screenWidth * 0.80
        let vinylSize = showLyrics ? lyricsVinylSize : centeredVinylSize
        // Keep the centered plinth at its original width even though the
        // record itself is slightly smaller.
        let baseReferenceSize = showLyrics ? lyricsVinylSize : screenWidth * 0.85

        // Vinyl center positions
        let lyricsX: CGFloat = -screenWidth * 0.08
        let centeredX: CGFloat = screenWidth / 2
        // Fine-tune the complete turntable only while lyrics are visible.
        // The lyrics-hidden layout always remains centered.
        let lyricsTurntableHorizontalOffset: CGFloat = 16
        let vinylCenterX = showLyrics
            ? lyricsX + lyricsTurntableHorizontalOffset
            : centeredX
        // Move the hardware as one unit; selectors and the vinyl seek gesture
        // below derive their positions from this same center.
        let vinylCenterY = showLyrics ? screenHeight * 0.38 : screenHeight * 0.3 + 24

        return ZStack {
            // Layer 0: Dominant-colour lyric backdrop. Keep this behind the
            // complete turntable so it colours only the player background,
            // never the wooden base, platter, record or tonearm.
            if !lyricLines.isEmpty {
                lyricsBackdrop(
                    screenWidth: screenWidth,
                    screenHeight: screenHeight
                )
                .transition(.opacity)
            }

            if !showLyrics {
                // The entire screen is the machine's faceplate. Keep it outside
                // the rotated hardware so its edges meet the screen edges.
                TurntableInsetPanel(baseStyle: styleManager.turntableBaseStyle)
                    .frame(width: screenWidth, height: screenHeight)
                    .position(x: screenWidth / 2, y: screenHeight / 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // A layout-only source gives matched geometry the actual record
            // center, rather than the bounds of a full-screen positioned view.
            Color.clear
                .frame(width: vinylSize, height: vinylSize)
                .matchedGeometryEffect(id: "vinylDisc", in: vinylNamespace,
                                       properties: .position, isSource: true)
                .position(x: vinylCenterX, y: vinylCenterY)
                .allowsHitTesting(false)

            // Keep Canvas artwork at a stable resolution throughout the morph.
            // Geometry matches the center; one uniform scale animates all parts.
            vinylDiscLayer(
                vinylSize: 380,
                baseReferenceSize: 380 * baseReferenceSize / vinylSize
            )
            .rotationEffect(.degrees(showLyrics ? 0 : 45))
            .scaleEffect(vinylSize / 380)
            .matchedGeometryEffect(id: "vinylDisc", in: vinylNamespace,
                                   properties: .position, isSource: false)

            // Follow the lower-left plinth edge in lyrics mode; stay horizontal
            // on the full-screen faceplate when lyrics are hidden.
            // Each selector is 84pt wide; the first knob center is x = 60.
            let selectorScale = 0.75 * vinylSize / 380
            let selectorCenter = CGPoint(
                x: showLyrics
                    ? (24 / sqrt(2.0) - 9.6) * selectorScale + vinylSize * 0.025
                    : 84 * selectorScale,
                y: vinylCenterY + vinylSize * (showLyrics ? 0.64 : 0.49)
            )
            // Match the layout anchor, not the full-screen bounds introduced
            // by position(). Keep a single live control group during reversal.
            Color.clear
                .frame(width: 168 * selectorScale, height: 48 * selectorScale)
                .matchedGeometryEffect(id: "turntableSelectors", in: vinylNamespace,
                                       properties: .position, isSource: true)
                .position(selectorCenter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            TurntableSelectorControls(
                isPlaying: collectionVM.isPlaying,
                rpm: collectionVM.currentRPM,
                onTogglePlayback: { togglePlaybackFromMiniPlayer() },
                onToggleSpeed: {
                    collectionVM.currentRPM = collectionVM.currentRPM < 40
                        ? AppConstants.rpm45 : AppConstants.rpm33
                }
            )
            .frame(width: 168, height: 48)
            .rotationEffect(.degrees(showLyrics ? -45 : 0))
            .scaleEffect(selectorScale)
            .matchedGeometryEffect(id: "turntableSelectors", in: vinylNamespace,
                                   properties: .position, isSource: false)
            .disabled(collectionVM.currentTrack == nil)

            // Layer 2: Lyrics (radial or ripple based on setting)
            if showLyrics {
                ZStack {
                    if lyricLines.isEmpty {
                        noLyricsFallback(
                            centerX: screenWidth * 0.76,
                            centerY: vinylCenterY - 16
                        )
                    } else if styleManager.lyricsDisplayMode == .ripple {
                        RippleLyricsLayer(
                            timedLines: musicServiceManager.currentLyrics,
                            playbackAnchor: isLyricDragging ? nil : lyricPlaybackAnchor,
                            lines: lyricLines,
                            currentIndex: isLyricDragging ? lyricDragIndex : currentLyricIndex,
                            intraLineProgress: intraLineProgress,
                            markerIntraLineProgress: markerIntraLineProgress,
                            vinylCenterX: vinylCenterX,
                            vinylCenterY: vinylCenterY,
                            vinylRadius: vinylSize / 2,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .gesture(lyricScrollGesture(lineCount: lyricLines.count))
                    } else {
                        RadialLyricsLayer(
                            timedLines: musicServiceManager.currentLyrics,
                            playbackAnchor: isLyricDragging ? nil : lyricPlaybackAnchor,
                            lines: lyricLines,
                            currentIndex: radialContinuousLyricIndex,
                            intraLineProgress: intraLineProgress,
                            markerIntraLineProgress: markerIntraLineProgress,
                            isInteractive: isLyricDragging,
                            vinylCenterX: vinylCenterX,
                            vinylCenterY: vinylCenterY,
                            vinylRadius: vinylSize / 2,
                            canvasWidth: screenWidth,
                            canvasHeight: screenHeight
                        )
                        .contentShape(Rectangle())
                        .gesture(lyricScrollGesture(lineCount: lyricLines.count))
                    }
                }
                .transition(
                    .move(edge: .trailing)
                        .combined(with: .opacity)
                )
            }

            // Layer 3: Invisible vinyl drag overlay
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: vinylSize * 0.85, height: vinylSize * 0.85)
                .position(x: vinylCenterX, y: vinylCenterY)
                .gesture(collectionVM.currentTrack != nil ? vinylRotationGesture(centerX: vinylCenterX, centerY: vinylCenterY) : nil)

        }
        .frame(width: screenWidth, height: screenHeight)
    }

    // MARK: - Vinyl Disc Layer

    private func vinylDiscLayer(
        vinylSize: CGFloat,
        baseReferenceSize: CGFloat
    ) -> some View {
        let layout = TurntableHardwareLayout(
            recordDiameter: vinylSize,
            baseReferenceSize: baseReferenceSize,
            showsLyrics: showLyrics
        )

        return ZStack {
            if showLyrics {
                TurntableBaseView(layout: layout, baseStyle: styleManager.turntableBaseStyle,
                                  isPlaying: collectionVM.isPlaying)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(colors: [.black.opacity(0.75), .white.opacity(0.25)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 5)
                    }
                    .frame(width: vinylSize + 25, height: vinylSize + 25)
            }
            TurntablePlatterView(recordDiameter: vinylSize,
                                 showsTransparentRecord: collectionVM.currentAlbum?.usesTransparentVinyl ?? false)

            // Keep frame-by-frame record updates isolated from the hardware.
            IsolatedSpinningVinylView(
                animator: vinylAnimator,
                album: collectionVM.currentAlbum,
                size: vinylSize,
                vinylColor: collectionVM.currentAlbum?.selectedEdition?.vinylColor ?? .black,
                customColorHex: collectionVM.currentAlbum?.customVinylColorHex,
                discOpacityOverride: collectionVM.currentAlbum?.effectiveVinylOpacity ?? 1.0,
                playerAnimation: playerAnimation,
                isPlayerExpanded: isExpanded
            )

            TurntableTonearmView(
                layout: layout,
                progress: collectionVM.playbackProgress,
                isLifted: $needleLifted,
                isParked: needleIsParked,
                tonearmColor: styleManager.theme.tonearmColor,
                onSeek: { progress in
                    collectionVM.playbackProgress = progress
                }
            )
            .allowsHitTesting(collectionVM.currentTrack != nil)
        }
        .frame(width: vinylSize, height: vinylSize)
    }

    // MARK: - Turntable Base

    private func isDismissDirection(_ translation: CGSize) -> Bool {
        let verticalAmount = max(translation.height, 0)
        let horizontalAmount = abs(translation.width)
        return verticalAmount > dismissDragMinimumDistance && verticalAmount > horizontalAmount * dismissDragDirectionRatio
    }


    /// Drag on the vinyl to manually rotate and seek.
    /// Computes the angular change from the drag relative to the vinyl center
    /// and maps it to playback progress.
    /// Normalize an angle delta to [-180, 180] to handle atan2 wrapping.
    private func normalizeAngleDelta(_ delta: Double) -> Double {
        var d = delta
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private func vinylRotationGesture(centerX: CGFloat, centerY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isVinylDragging {
                    isVinylDragging = true
                    vinylAnimator.isDragging = true
                    isSeeking = true
                    vinylDragStartProgress = collectionVM.playbackProgress
                    lastDragAngle = atan2(
                        Double(value.startLocation.x - centerX),
                        Double(-(value.startLocation.y - centerY))
                    ) * 180.0 / .pi
                    vinylDragStartAngle = lastDragAngle
                    lastDragTime = .now
                    soundEngine.startScratch()
                }

                let currentAngle = atan2(
                    Double(value.location.x - centerX),
                    Double(-(value.location.y - centerY))
                ) * 180.0 / .pi

                // Compute delta BEFORE updating lastDragAngle, with wrapping fix
                let rawDelta = currentAngle - lastDragAngle
                let angleDelta = normalizeAngleDelta(rawDelta)

                // Calculate angular velocity for scratch intensity
                let now = Date.now
                let dt = now.timeIntervalSince(lastDragTime)
                if dt > 0.001 {
                    let angularVelocity = angleDelta / dt
                    soundEngine.updateScratch(velocity: angularVelocity)
                }

                // Sync visual rotation with drag — the disc follows the finger
                vinylAnimator.addRotation(angleDelta)

                // Update tracking state AFTER computing delta
                lastDragAngle = currentAngle
                lastDragTime = now

                // Accumulate total angle for progress seeking
                let totalRawDelta = currentAngle - vinylDragStartAngle
                let totalAngleDelta = normalizeAngleDelta(totalRawDelta)
                // Full rotation (360°) = full track. Scaled down for usability.
                let progressDelta = totalAngleDelta / 720.0
                let newProgress = max(0, min(1, vinylDragStartProgress + progressDelta))

                seekProgress = newProgress
                collectionVM.playbackProgress = newProgress

                // Haptic on meaningful progress change
                HapticManager.shared.selectionTick(styleManager.hapticIntensity)
            }
            .onEnded { value in
                guard isVinylDragging else { return }

                isVinylDragging = false
                vinylAnimator.isDragging = false
                // Seek the actual audio to the dragged position
                musicServiceManager.seek(to: seekProgress)
                isSeeking = false
                soundEngine.stopScratch()
            }
    }

    private var needleAngle: Double {
        // A selected track remains on the physical rest until playback first
        // starts. Pause only lifts the cartridge and preserves the groove.
        guard collectionVM.currentTrack != nil, !needleIsParked else {
            return AppConstants.needleRestAngle
        }
        let start = AppConstants.needleStartAngle
        let end = AppConstants.needleEndAngle
        return start + (end - start) * collectionVM.playbackProgress
    }

    // MARK: - Radial Lyrics Layer

    private var radialContinuousLyricIndex: Double {
        guard isLyricDragging else { return Double(currentLyricIndex) }
        let continuousLineDelta = Double(-lastLyricDragTranslationY / 30)
        return min(
            max(0, Double(currentLyricIndex) + continuousLineDelta),
            Double(max(0, lyricLines.count - 1))
        )
    }

    /// Dominant-colour gradient placed behind the complete turntable assembly.
    /// The turntable remains visually untouched because it is rendered above this layer.
    private func lyricsBackdrop(
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        let tintColor = dominantColor
            ?? collectionVM.currentAlbum?.color
            ?? styleManager.theme.backgroundColor

        return LinearGradient(
            colors: [
                tintColor.opacity(0.65),
                tintColor.opacity(0.52),
                tintColor.opacity(0.60)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: screenWidth, height: screenHeight)
        .position(x: screenWidth / 2, y: screenHeight / 2)
        .opacity(0.75)
        .allowsHitTesting(false)
    }

    /// Auto-scrolling radial lyrics: the current line is always at 90°
    /// (horizontal, pointing right). Lines above/below scroll through as
    /// playback progresses. Each line is a spoke pointing at the vinyl center.
    ///
    /// Dragging vertically on the lyrics area scrolls through lines manually.
    /// On release, playback seeks to the selected lyric's time position.
    private func radialLyricsLayer(
        vinylCenterX: CGFloat,
        vinylCenterY: CGFloat,
        vinylRadius: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        let lines = lyricLines
        let textStartRadius = vinylRadius + 24
        let textLeftEdge = vinylCenterX + textStartRadius
        let maxTextWidth = max(80, screenWidth - textLeftEdge - 12)
        let effectiveRadius = textStartRadius + maxTextWidth / 2

        let anchorAngle: Double = 90.0
        let minVisibleAngle: Double = 5
        let maxVisibleAngle: Double = 175
        let visualGap: CGFloat = 36

        // Use manual index while dragging, otherwise auto index
        let requestedIndex = isLyricDragging ? lyricDragIndex : currentLyricIndex
        let activeIndex = min(max(0, requestedIndex), lines.count - 1)

        /// Available length from the platter edge to the first screen boundary
        /// along a lyric's actual radial direction. Diagonal lyrics can use the
        /// otherwise-empty top-right and bottom-right corners instead of being
        /// constrained to the narrower horizontal width at 90°.
        func availableTextWidth(at angleDeg: Double) -> CGFloat {
            let angleRad = angleDeg * .pi / 180
            let directionX = sin(angleRad)
            let directionY = -cos(angleRad)
            let startX = vinylCenterX + textStartRadius * directionX
            let startY = vinylCenterY + textStartRadius * directionY
            let edgePadding: CGFloat = 12

            var boundaryDistances: [CGFloat] = []

            if directionX > 0.001 {
                boundaryDistances.append(
                    (screenWidth - edgePadding - startX) / directionX
                )
            }

            if directionY < -0.001 {
                boundaryDistances.append(
                    (edgePadding - startY) / directionY
                )
            } else if directionY > 0.001 {
                boundaryDistances.append(
                    (screenHeight - edgePadding - startY) / directionY
                )
            }

            let usableDistance = boundaryDistances
                .filter { $0 > 0 }
                .min()
                ?? maxTextWidth

            return max(80, min(usableDistance, screenWidth * 0.9))
        }

        // Treat each lyric (including a wrapped lyric) as one visual block.
        // Adjacent block edges receive the same point gap, so the result stays
        // compact without allowing a two-line active lyric to collide.
        func blockHeight(at index: Int) -> CGFloat {
            let distance = abs(index - activeIndex)
            let style = lyricStyle(distance: distance)
            let uiWeight: UIFont.Weight
            switch distance {
            case 0: uiWeight = .bold
            case 1: uiWeight = .semibold
            case 2: uiWeight = .medium
            default: uiWeight = .regular
            }
            let lineCount = estimatedLineCount(
                for: lines[index],
                fontSize: style.fontSize,
                weight: uiWeight,
                maxWidth: maxTextWidth
            )
            let font = UIFont.systemFont(ofSize: style.fontSize, weight: uiWeight)
            return CGFloat(lineCount) * font.lineHeight * style.scale
        }

        var baseAngles = Array(repeating: 0.0, count: lines.count)
        if activeIndex + 1 < lines.count {
            for index in (activeIndex + 1)..<lines.count {
                let centreDistance = blockHeight(at: index - 1) / 2
                    + visualGap
                    + blockHeight(at: index) / 2
                let angleDistance = Double(centreDistance / effectiveRadius) * (180.0 / .pi)
                baseAngles[index] = baseAngles[index - 1] + angleDistance
            }
        }
        if activeIndex > 0 {
            for index in stride(from: activeIndex - 1, through: 0, by: -1) {
                let centreDistance = blockHeight(at: index) / 2
                    + visualGap
                    + blockHeight(at: index + 1) / 2
                let angleDistance = Double(centreDistance / effectiveRadius) * (180.0 / .pi)
                baseAngles[index] = baseAngles[index + 1] - angleDistance
            }
        }

        // Scroll offset: shift so activeIndex sits at anchorAngle
        let scrollOffset = baseAngles[min(activeIndex, lines.count - 1)] - anchorAngle

        // Keep the radial lyric wheel attached to the finger between line
        // changes. `lyricDragIndex` still selects a line every 30pt, while the
        // remaining fractional drag continuously interpolates toward the next
        // line's angle. At the threshold the fraction returns to zero and the
        // newly selected line is already in the same visual position.
        let continuousAngleOffset: Double = {
            guard isLyricDragging else { return 0 }

            let continuousLineDelta = Double(-lastLyricDragTranslationY / 30)
            let selectedLineDelta = Double(lyricDragIndex - currentLyricIndex)
            let remainingFraction = continuousLineDelta - selectedLineDelta

            if remainingFraction > 0, activeIndex + 1 < lines.count {
                let nextGap = baseAngles[activeIndex + 1] - baseAngles[activeIndex]
                return -remainingFraction * nextGap
            }

            if remainingFraction < 0, activeIndex > 0 {
                let previousGap = baseAngles[activeIndex] - baseAngles[activeIndex - 1]
                return -remainingFraction * previousGap
            }

            return 0
        }()

        return ZStack {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let angleDeg = baseAngles[index] - scrollOffset + continuousAngleOffset

                if angleDeg >= minVisibleAngle && angleDeg <= maxVisibleAngle {
                    let angleRad = angleDeg * .pi / 180.0
                    let lineMaxWidth = availableTextWidth(at: angleDeg)
                    let lineRadius = textStartRadius + lineMaxWidth / 2
                    let x = vinylCenterX + lineRadius * sin(angleRad)
                    let y = vinylCenterY - lineRadius * cos(angleRad)
                    let textRotation = angleDeg - 90

                    let distance = abs(index - activeIndex)
                    let isCurrent = distance == 0
                    let style = lyricStyle(distance: distance)

                    Group {
                        if isCurrent {
                            KaraokeLyricText(
                                text: line,
                                fillProgress: intraLineProgress,
                                markerFillProgress: markerIntraLineProgress,
                                fontSize: style.fontSize,
                                weight: style.weight,
                                filledColor: .black,
                                unfilledColor: Color.black.opacity(0.38),
                                maxWidth: lineMaxWidth,
                                showsHandwrittenHighlight: true
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
                            )
                        } else {
                            Text(line)
                                .font(.system(size: style.fontSize, weight: style.weight, design: .rounded))
                                .foregroundColor(.white.opacity(style.opacity))
                                .shadow(color: Color.white.opacity(0.4), radius: 8)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: lineMaxWidth, alignment: .leading)
                                .transition(
                                    .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
                                )
                        }
                    }
                    .blur(radius: style.blur)
                    .scaleEffect(style.scale, anchor: .leading)
                    .rotationEffect(.degrees(textRotation))
                    .position(x: x, y: y)
                    // Position, lyric styling and the marker rendered inside
                    // KaraokeLyricText now share one transition timeline.
                    .animation(
                        .interactiveSpring(response: 0.28, dampingFraction: 0.86),
                        value: activeIndex
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(lyricScrollGesture(lineCount: lines.count))
    }

    /// Drag vertically to scroll through lyrics. On release, seek to
    /// the time position corresponding to the selected line.
    private func lyricScrollGesture(lineCount: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isLyricDragging {
                    isLyricDragging = true
                    isSeeking = true
                    lyricDragIndex = currentLyricIndex
                    seekProgress = collectionVM.playbackProgress
                    // Pause display-link rotation while lyric seeking controls
                    // the record position directly.
                    vinylAnimator.isDragging = true
                    lastLyricDragTranslationY = 0
                }

                // Rotate continuously from the finger's incremental movement.
                // Lyric selection may snap every 30pt, but the record must not.
                let translationDelta = value.translation.height - lastLyricDragTranslationY
                vinylAnimator.addRotation(-Double(translationDelta) * 1.8)
                lastLyricDragTranslationY = value.translation.height

                // Vertical drag: negative Y = scroll up (earlier lyrics)
                // Every 30pt of drag = 1 line
                let lineDelta = Int(-value.translation.height / 30)
                let newIndex = max(0, min(lineCount - 1, currentLyricIndex + lineDelta))
                if newIndex != lyricDragIndex {
                    HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                        lyricDragIndex = newIndex
                    }
                }

                // Update progress bar in real-time during lyrics drag
                let lyrics = musicServiceManager.currentLyrics
                let duration = musicServiceManager.playbackState.duration > 0
                    ? musicServiceManager.playbackState.duration
                    : (collectionVM.currentTrack?.duration ?? 240)
                if newIndex < lyrics.count && duration > 0 {
                    let progress = max(0, min(1, lyrics[newIndex].startTime / duration))
                    seekProgress = progress
                    collectionVM.playbackProgress = progress
                }
            }
            .onEnded { _ in
                guard isLyricDragging else { return }
                // Seek to the selected lyric's time position
                guard lineCount > 0 else { return }

                let lyrics = musicServiceManager.currentLyrics
                let duration = musicServiceManager.playbackState.duration > 0
                    ? musicServiceManager.playbackState.duration
                    : (collectionVM.currentTrack?.duration ?? 240)

                let targetProgress: Double
                if lyricDragIndex < lyrics.count && duration > 0 {
                    targetProgress = lyrics[lyricDragIndex].startTime / duration
                } else {
                    targetProgress = Double(lyricDragIndex) / Double(lineCount)
                }

                let clampedProgress = max(0, min(1, targetProgress))
                collectionVM.playbackProgress = clampedProgress
                musicServiceManager.seek(to: clampedProgress)
                vinylAnimator.isDragging = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    currentLyricIndex = lyricDragIndex
                    lastLyricDragTranslationY = 0
                    isLyricDragging = false
                    isSeeking = false
                }
            }
    }

    /// Measure how many visual lines a text string occupies using NSString.boundingRect for accuracy.
    private func estimatedLineCount(for text: String, fontSize: CGFloat, weight: UIFont.Weight = .regular, maxWidth: CGFloat) -> Int {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let constraintSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let boundingRect = (text as NSString).boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let singleLineHeight = font.lineHeight
        return max(1, Int(ceil(boundingRect.height / singleLineHeight)))
    }

    private func lyricStyle(distance: Int) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat, scale: CGFloat) {
        switch distance {
        case 0:  return (30, 1.0,  .bold,      0,   1.0)
        case 1:  return (24, 0.45, .semibold,  0.5, 0.92)
        case 2:  return (22, 0.30, .medium,    1.0, 0.84)
        case 3:  return (20, 0.20, .regular,   1.5, 0.76)
        case 4:  return (18, 0.15, .regular,   2.2, 0.68)
        default: return (18, 0.10, .regular,   3.0, 0.60)
        }
    }

    // MARK: - No Lyrics Fallback

    private func noLyricsFallback(centerX: CGFloat, centerY: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.6))
            Text(L("player.no_lyrics"))
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .environment(\.colorScheme, isDominantColorLight ? .light : .dark)
        .position(x: centerX, y: centerY)
    }

    // MARK: - Track Info

    private var trackInfoBar: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Group {
                    MarqueeText(
                        text: collectionVM.currentTrack?.title ?? L("player.not_playing"),
                        font: .system(size: 18, weight: .semibold),
                        foregroundColor: .primary,
                        fontSize: 18
                    )
                    .shadow(color: trackInfoTextShadow, radius: 1.5, y: 0.5)
                    .matchedGeometryEffect(id: "Title", in: playerAnimation, isSource: isExpanded)
                }

                Group {
                    MarqueeText(
                        text: collectionVM.currentTrack?.artist ?? "",
                        font: .system(size: 14),
                        foregroundColor: .secondary,
                        fontSize: 14
                    )
                    .shadow(color: trackInfoTextShadow, radius: 1.25, y: 0.5)
                    .matchedGeometryEffect(id: "Artist", in: playerAnimation, isSource: isExpanded)
                }

            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            trackInfoBackdrop
                .frame(width: min(screenWidth - 24, 400), height: 96)
        }
    }

    /// A local, feathered blur that separates track metadata from lyrics passing
    /// behind it without reading as a distinct card or hiding the lyric motion.
    private var trackInfoBackdrop: some View {
        let tintColor = dominantColor
            ?? collectionVM.currentAlbum?.color
            ?? styleManager.theme.backgroundColor

        return Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: tintColor.opacity(0.28), location: 0),
                        .init(color: tintColor.opacity(0.15), location: 0.42),
                        .init(color: tintColor.opacity(0.05), location: 0.74),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 190
                )
            )
        .blur(radius: 10)
        .opacity(showLyrics ? 0.72 : 0)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: showLyrics)
    }

    private var trackInfoTextShadow: Color {
        isDominantColorLight
            ? Color.white.opacity(0.46)
            : Color.black.opacity(0.55)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        let hasTrack = collectionVM.currentTrack != nil
        return HStack(spacing: 24) {
            // Shuffle
            Button {
                HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                collectionVM.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16))
                    .foregroundColor(
                        collectionVM.isShuffled
                            ? .primary
                            : .secondary
                    )
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.pressable)

            // Previous
            Button {
                HapticManager.shared.impact(styleManager.hapticIntensity)
                collectionVM.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22))
                    .foregroundColor(hasTrack ? .primary : .secondary.opacity(0.4))
            }
            .buttonStyle(.pressable)
            .disabled(!hasTrack)

            // Play / Pause
            Button {
                HapticManager.shared.impact(styleManager.hapticIntensity)
                if collectionVM.isPlaying { soundEngine.playNeedleLift() }
                else { soundEngine.playNeedleDrop() }
                musicServiceManager.togglePlayback()
            } label: {
                Image(systemName: collectionVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(hasTrack ? .primary : .secondary.opacity(0.4))
            }
            .buttonStyle(.pressable(scale: 0.9, opacity: 0.8))
            .disabled(!hasTrack)

            // Next
            Button {
                HapticManager.shared.impact(styleManager.hapticIntensity)
                collectionVM.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22))
                    .foregroundColor(hasTrack ? .primary : .secondary.opacity(0.4))
            }
            .buttonStyle(.pressable)
            .disabled(!hasTrack)

            // Repeat
            Button {
                HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                collectionVM.cycleRepeatMode()
            } label: {
                Image(systemName: collectionVM.repeatMode.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(
                        collectionVM.repeatMode != .off
                            ? .primary
                            : .secondary
                    )
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: - Waveform Progress Bar

    private var waveformProgressBar: some View {
        let hasTrack = collectionVM.currentTrack != nil
        let effectiveProgress = isSeeking ? seekProgress : collectionVM.playbackProgress
        let currentTime = (collectionVM.currentTrack?.duration ?? 0) * effectiveProgress

        return WaveformProgressBar(
            progress: hasTrack ? effectiveProgress : 0,
            currentTime: hasTrack ? currentTime.formattedDuration : "0:00",
            totalTime: collectionVM.currentTrack?.duration.formattedDuration ?? "0:00",
            trackSeed: collectionVM.currentTrack?.id.hashValue ?? 0,
            isDisabled: !hasTrack,
            onSeekChanged: hasTrack ? { newProgress in
                if !isSeeking {
                    // Cancel immediately on touch-down so a timer expiring in
                    // this same run-loop cannot hide the control under the finger.
                    cancelLyricsControlsAutoHide(revealIfNeeded: false)
                }
                isSeeking = true
                seekProgress = newProgress
                collectionVM.playbackProgress = newProgress
            } : nil,
            onSeekEnded: hasTrack ? {
                collectionVM.playbackProgress = seekProgress
                musicServiceManager.seek(to: seekProgress)
                isSeeking = false
            } : nil
        )
    }
}

/// Supplies static disc content. Only its rotation modifiers observe frame ticks.
private struct IsolatedSpinningVinylView: View {
    let animator: VinylAnimator

    let album: Album?
    let size: CGFloat
    let vinylColor: VinylColor
    let customColorHex: String?
    let discOpacityOverride: Double
    let playerAnimation: Namespace.ID
    let isPlayerExpanded: Bool

    var body: some View {
        VinylDiscView(
            album: album,
            size: size,
            rotation: 0,
            vinylColor: vinylColor,
            customColorHex: customColorHex,
            discOpacityOverride: discOpacityOverride,
            playerAnimation: playerAnimation,
            isPlayerExpanded: isPlayerExpanded,
            animator: animator
        )
    }
}

#Preview("Turntable — Radial Mock Lyrics") {
    @Previewable @Namespace var playerAnimation

    let mockLyrics = [
        LyricLine(startTime: 0, endTime: 4, text: "Rubber Bands"),
        LyricLine(startTime: 4, endTime: 8, text: "Mapping Values to Color"),
        LyricLine(startTime: 8, endTime: 12, text: "Pointer Reactivity"),
        LyricLine(startTime: 12, endTime: 16, text: "Painting Order"),
        LyricLine(startTime: 16, endTime: 20, text: "Isolation"),
        LyricLine(startTime: 20, endTime: 24, text: "Grouping & Opacity"),
        LyricLine(startTime: 24, endTime: 28, text: "Overlapping Transparency"),
        LyricLine(startTime: 28, endTime: 32, text: "Image Cross-Fades"),
        LyricLine(startTime: 32, endTime: 36, text: "Backdrop Filters"),
        LyricLine(startTime: 36, endTime: 40, text: "Layered Shadows"),
        LyricLine(startTime: 40, endTime: 44, text: "Graphics vs. Images"),
        LyricLine(startTime: 44, endTime: 48, text: "Working with Alignment"),
        LyricLine(startTime: 48, endTime: 52, text: "Simple Machines"),
        LyricLine(startTime: 52, endTime: nil, text: "State Galleries")
    ]
    let mockTrack = Track(
        title: "Radial Study",
        artist: "Preview Artist",
        albumTitle: "Interface Sessions",
        duration: 56,
        lyrics: LyricLine.toLRC(mockLyrics)
    )
    let mockAlbum = Album(
        title: "Interface Sessions",
        artist: "Preview Artist",
        releaseYear: 2026,
        genre: "Electronic",
        colorHex: "#075C31",
        tracks: [mockTrack]
    )
    let collectionVM = CollectionViewModel()
    let musicServiceManager = MusicServiceManager()
    let styleManager = StyleManager()

    collectionVM.currentAlbum = mockAlbum
    collectionVM.currentTrack = mockTrack
    collectionVM.isPlaying = false
    musicServiceManager.currentLyrics = mockLyrics
    styleManager.lyricsDisplayMode = .radial

    return TurntableView(
        isExpanded: .constant(true),
        playerAnimation: playerAnimation
    )
    .id("turntable-radial-preview")
    .environmentObject(collectionVM)
    .environmentObject(styleManager)
    .environmentObject(musicServiceManager)
}

#Preview("Turntable — Ripple Mock Lyrics") {
    @Previewable @Namespace var playerAnimation

    let mockLyrics = [
        LyricLine(startTime: 0, endTime: 4, text: "Rubber Bands"),
        LyricLine(startTime: 4, endTime: 8, text: "Mapping Values to Color"),
        LyricLine(startTime: 8, endTime: 12, text: "Pointer Reactivity"),
        LyricLine(startTime: 12, endTime: 16, text: "Painting Order"),
        LyricLine(startTime: 16, endTime: 20, text: "Isolation"),
        LyricLine(startTime: 20, endTime: 24, text: "Grouping & Opacity"),
        LyricLine(startTime: 24, endTime: 28, text: "Overlapping Transparency"),
        LyricLine(startTime: 28, endTime: 32, text: "Image Cross-Fades"),
        LyricLine(startTime: 32, endTime: 36, text: "Backdrop Filters"),
        LyricLine(startTime: 36, endTime: 40, text: "Layered Shadows"),
        LyricLine(startTime: 40, endTime: 44, text: "Graphics vs. Images"),
        LyricLine(startTime: 44, endTime: 48, text: "Working with Alignment"),
        LyricLine(startTime: 48, endTime: 52, text: "Simple Machines"),
        LyricLine(startTime: 52, endTime: nil, text: "State Galleries")
    ]
    let mockTrack = Track(
        title: "Ripple Study",
        artist: "Preview Artist",
        albumTitle: "Interface Sessions",
        duration: 56,
        lyrics: LyricLine.toLRC(mockLyrics)
    )
    let mockAlbum = Album(
        title: "Interface Sessions",
        artist: "Preview Artist",
        releaseYear: 2026,
        genre: "Electronic",
        colorHex: "#075C31",
        tracks: [mockTrack]
    )
    let collectionVM = CollectionViewModel()
    let musicServiceManager = MusicServiceManager()
    let styleManager = StyleManager()

    collectionVM.currentAlbum = mockAlbum
    collectionVM.currentTrack = mockTrack
    collectionVM.isPlaying = false
    musicServiceManager.currentLyrics = mockLyrics
    styleManager.lyricsDisplayMode = .ripple

    return TurntableView(
        isExpanded: .constant(true),
        playerAnimation: playerAnimation
    )
    .id("turntable-ripple-preview")
    .environmentObject(collectionVM)
    .environmentObject(styleManager)
    .environmentObject(musicServiceManager)
    .onAppear {
        // Advance after TurntableView has installed its progress observer so
        // completed lines are visible in their dispersed directions.
        DispatchQueue.main.async {
            collectionVM.playbackProgress = 0.58
        }
    }
}

// Keep drag-frequency invalidation outside the turntable and lyrics hierarchy.
private final class PlayerDismissTranslation: ObservableObject {
    @Published var offset: CGFloat = 0
}

private struct PlayerDismissTranslationEffect: ViewModifier {
    @ObservedObject var translation: PlayerDismissTranslation

    func body(content: Content) -> some View {
        content.offset(y: translation.offset)
    }
}
