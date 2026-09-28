import SwiftUI
import MediaPlayer
import AVFoundation
import Combine

/// Apple Music–style system volume slider.
/// Uses a hidden MPVolumeView to control the actual system volume,
/// and AVAudioSession.outputVolume observation for the custom UI.
struct SystemVolumeSlider: View {
    var tintColor: Color = .primary
    var isVisible: Bool = true

    @StateObject private var volumeObserver = VolumeObserver()
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            // Min volume icon
            Image(systemName: volumeObserver.volume == 0 ? "speaker.fill" : "speaker.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 16)

            // Custom slim slider
            GeometryReader { geo in
                let width = geo.size.width
                let fillWidth = width * CGFloat(volumeObserver.volume)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    // Fill
                    Capsule()
                        .fill(tintColor.opacity(0.8))
                        .frame(width: max(4, fillWidth), height: 4)

                    // Thumb (only visible while dragging)
                    if isDragging {
                        Circle()
                            .fill(tintColor)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .offset(x: max(0, min(fillWidth - 10, width - 20)))
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let newVolume = Float(max(0, min(1, value.location.x / width)))
                            volumeObserver.setVolume(newVolume)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: 20)

            // Max volume icon
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 16)
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                volumeObserver.installHiddenVolumeView()
            } else {
                volumeObserver.removeHiddenVolumeView()
            }
        }
        .onAppear {
            if isVisible {
                volumeObserver.installHiddenVolumeView()
            }
        }
        .onDisappear {
            volumeObserver.removeHiddenVolumeView()
        }
    }
}

// MARK: - Volume Observer

/// Observes system volume via AVAudioSession and provides
/// a hidden MPVolumeView for programmatic volume control.
final class VolumeObserver: ObservableObject {
    @Published var volume: Float = 0

    private var observation: NSKeyValueObservation?
    private let audioSession = AVAudioSession.sharedInstance()
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?

    init() {
        // Don't set active here — the app-level audio session setup handles that.
        // Just observe the current volume.

        volume = audioSession.outputVolume

        observation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.volume = change.newValue ?? 0
            }
        }
    }

    deinit {
        observation?.invalidate()
        removeHiddenVolumeView()
    }

    func setVolume(_ newVolume: Float) {
        volumeSlider?.value = newVolume
    }

    /// Install hidden MPVolumeView to suppress system volume HUD.
    /// Call when the custom volume slider is visible (Now Playing).
    func installHiddenVolumeView() {
        guard volumeView == nil else { return }
        DispatchQueue.main.async { [weak self] in
            let mpVolumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            mpVolumeView.showsRouteButton = false

            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first {
                window.addSubview(mpVolumeView)
            }

            // Extract the slider for programmatic volume control
            for subview in mpVolumeView.subviews {
                if let slider = subview as? UISlider {
                    self?.volumeSlider = slider
                    break
                }
            }

            self?.volumeView = mpVolumeView
        }
    }

    /// Remove hidden MPVolumeView so system volume HUD shows again.
    /// Call when leaving Now Playing view.
    func removeHiddenVolumeView() {
        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
    }
}
