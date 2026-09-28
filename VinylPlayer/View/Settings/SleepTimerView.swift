import SwiftUI

struct SleepTimerView: View {
    @EnvironmentObject private var manager: MusicServiceManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let deadline = manager.sleepPlan.deadline {
                        HStack { Text(L("sleep.remaining")); Spacer(); Text(deadline, style: .timer).monospacedDigit() }
                    }
                    if manager.sleepPlan.afterCurrentTrack { Label(L("sleep.after_track"), systemImage: "moon.zzz") }
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) \(L("sleep.minutes"))") { manager.setSleepTimer(minutes: minutes) }
                    }
                    Button(L("sleep.after_track")) { manager.setSleepAfterTrack() }
                        .disabled(!manager.canSleepAfterTrack)
                    if manager.sleepPlan.isActive {
                        Button(L("sleep.cancel"), role: .destructive) { manager.cancelSleepTimer() }
                    }
                } footer: {
                    Text(L("sleep.background_hint"))
                }
            }
            .navigationTitle(L("sleep.title"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } } }
        }
    }
}

struct PlaybackStatusBanner: View {
    @EnvironmentObject private var manager: MusicServiceManager
    var body: some View {
        if manager.isLoadingPlayback {
            HStack(spacing: 12) {
                ProgressView()
                Text(L("playback.loading")).font(.subheadline)
                Spacer()
                Button(L("common.cancel")) { manager.pause() }
            }.padding(16).background(.regularMaterial, in: .rect(cornerRadius: 16))
        } else if let failure = manager.playbackFailure {
            VStack(alignment: .leading, spacing: 8) {
                Text(failure.title).font(.headline).lineLimit(1)
                Text(failure.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                HStack(spacing: 16) {
                    Button(L("common.retry")) { manager.retryPlayback() }
                    Button(L("common.dismiss")) { manager.playbackFailure = nil }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }
}
