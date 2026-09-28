import SwiftUI

/// A non-blocking toast that shows post-import progress (lyrics + Apple Music matching).
/// Positioned above the mini player in ContentView.
struct ImportProgressBanner: View {
    @ObservedObject var taskManager = ImportTaskManager.shared
    @EnvironmentObject var styleManager: StyleManager

    var body: some View {
        if taskManager.isActive {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    statusText
                    if let progress = currentProgress {
                        ProgressView(value: progress)
                            .tint(styleManager.theme.textSecondary)
                            .scaleEffect(y: 0.6)
                    }
                }
                Spacer()

                if isCompleted {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            taskManager.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(styleManager.theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            .padding(.horizontal, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: taskManager.phase)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch taskManager.phase {
        case .idle:
            EmptyView()
        case .importing:
            ProgressView()
                .tint(styleManager.theme.textSecondary)
                .scaleEffect(0.7)
        case .fetchingLyrics:
            Image(systemName: "music.note.list")
                .font(.system(size: 14))
                .foregroundColor(styleManager.theme.textSecondary)
        case .matchingAppleMusic:
            Image(systemName: "music.note.tv")
                .font(.system(size: 14))
                .foregroundColor(.pink)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch taskManager.phase {
        case .idle:
            EmptyView()
        case .importing(let title):
            Text(L("banner.importing", title))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(styleManager.theme.textPrimary)
                .lineLimit(1)
        case .fetchingLyrics(let title, _):
            Text(L("banner.lyrics", title))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(styleManager.theme.textPrimary)
                .lineLimit(1)
        case .matchingAppleMusic(let title, _):
            Text(L("banner.matching", title))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(styleManager.theme.textPrimary)
                .lineLimit(1)
        case .completed(_, let lyricsCount, let matchCount):
            VStack(alignment: .leading, spacing: 2) {
                Text(L("banner.complete"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(styleManager.theme.textPrimary)
                let details = completionDetails(lyrics: lyricsCount, matched: matchCount)
                if !details.isEmpty {
                    Text(details)
                        .font(.system(size: 11))
                        .foregroundColor(styleManager.theme.textSecondary)
                }
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
                .lineLimit(2)
        }
    }

    private var currentProgress: Double? {
        switch taskManager.phase {
        case .fetchingLyrics(_, let p): return p
        case .matchingAppleMusic(_, let p): return p
        default: return nil
        }
    }

    private var isCompleted: Bool {
        switch taskManager.phase {
        case .completed, .failed: return true
        default: return false
        }
    }

    private func completionDetails(lyrics: Int, matched: Int) -> String {
        var parts: [String] = []
        if lyrics > 0 {
            parts.append(L("banner.lyrics_found", lyrics))
        }
        if matched > 0 {
            parts.append(L("banner.tracks_matched", matched))
        }
        return parts.joined(separator: " · ")
    }
}
