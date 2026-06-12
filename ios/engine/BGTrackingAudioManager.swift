import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Owns the user-enabled audible background audio session for an active
/// tracking session and publishes user controls through Now Playing.
@objc public final class BGTrackingAudioManager: NSObject {
    @objc public static let shared = BGTrackingAudioManager()

    private let audioQueue = DispatchQueue(label: "BGTrackingAudioManager.audio")
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var shouldBeRunning = false
    private var active = false
    private var lastError: String?
    private var remoteCommandsConfigured = false

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc public func startIfNeeded() {
        guard BGConfig.sharedInstance().app.trackingAudioEnabled else { return }
        audioQueue.sync {
            self.shouldBeRunning = true
            self.startLocked()
        }
    }

    @objc public func stop() {
        audioQueue.sync {
            self.shouldBeRunning = false
            self.stopLocked(deactivateSession: true)
        }
    }

    @objc public func stateDictionary() -> [String: Any] {
        audioQueue.sync {
            var state: [String: Any] = [
                "enabled": BGConfig.sharedInstance().app.trackingAudioEnabled,
                "requested": shouldBeRunning,
                "active": active,
                "audible": true,
                "volume": BGConfig.sharedInstance().app.trackingAudioVolume,
                // iOS has no runtime permission for audio playback. The app
                // must obtain user consent in its own UI and declare the audio
                // background mode; microphone permission is unrelated.
                "permissionRequired": false,
                "authorizationStatus": "notRequired",
                "backgroundModeDeclared": hasAudioBackgroundMode(),
                "nowPlayingActive": MPNowPlayingInfoCenter.default().nowPlayingInfo != nil
            ]
            if let lastError {
                state["error"] = lastError
            }
            return state
        }
    }

    @objc private func applicationDidFinishLaunching() {
        audioQueue.async {
            if self.shouldBeRunning || BGConfig.sharedInstance().enabled {
                self.startLocked()
            }
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        audioQueue.async {
            switch type {
            case .began:
                self.stopLocked(deactivateSession: false)
            case .ended:
                let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if self.shouldBeRunning && options.contains(.shouldResume) {
                    self.startLocked()
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        audioQueue.async {
            self.stopLocked(deactivateSession: false)
            if self.shouldBeRunning {
                self.startLocked()
            }
        }
    }

    private func startLocked() {
        guard shouldBeRunning || BGConfig.sharedInstance().enabled else { return }
        guard BGConfig.sharedInstance().app.trackingAudioEnabled else { return }
        guard !active else { return }

        do {
            let config = BGConfig.sharedInstance().app
            let session = AVAudioSession.sharedInstance()
            let options: AVAudioSession.CategoryOptions =
                config.trackingAudioMixWithOthers ? [.mixWithOthers] : []
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)

            let audioEngine = AVAudioEngine()
            let sampleRate = 44_100.0
            let frequency = 196.0
            let amplitude = Float(min(max(config.trackingAudioVolume, 0.01), 1.0))
            var phase = 0.0
            let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate

            let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for frame in 0..<Int(frameCount) {
                    // A soft two-harmonic tracking tone. This is intentionally
                    // audible; the audio background mode must not be driven by
                    // silent playback.
                    let fundamental = sin(phase)
                    let harmonic = sin(phase * 2.0) * 0.18
                    let sample = Float(fundamental + harmonic) * amplitude
                    phase += phaseIncrement
                    if phase >= 2.0 * Double.pi {
                        phase -= 2.0 * Double.pi
                    }
                    for buffer in buffers {
                        guard let data = buffer.mData else { continue }
                        data.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                }
                return noErr
            }

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ) else {
                throw NSError(
                    domain: "BGTrackingAudioManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create audio format"]
                )
            }

            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
            audioEngine.prepare()
            try audioEngine.start()

            engine = audioEngine
            sourceNode = node
            active = true
            lastError = nil
            publishNowPlaying()
            log("Tracking audio started")
        } catch {
            active = false
            lastError = error.localizedDescription
            log("Unable to start tracking audio: \(error.localizedDescription)")
        }
    }

    private func stopLocked(deactivateSession: Bool) {
        engine?.stop()
        if let node = sourceNode {
            engine?.disconnectNodeOutput(node)
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
        active = false
        clearNowPlaying()

        if deactivateSession {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
        log("Tracking audio stopped")
    }

    private func publishNowPlaying() {
        let app = BGConfig.sharedInstance().app
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Background Geolocation"

        DispatchQueue.main.async {
            self.configureRemoteCommandsIfNeeded()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: app.liveActivityTitle,
                MPMediaItemPropertyArtist: appName,
                MPMediaItemPropertyAlbumTitle: app.liveActivitySubtitle,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
            ]
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    private func clearNowPlaying() {
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        commands.changePlaybackPositionCommand.isEnabled = false

        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.endTrackingFromRemoteCommand()
            return .success
        }

        commands.stopCommand.isEnabled = true
        commands.stopCommand.addTarget { [weak self] _ in
            self?.endTrackingFromRemoteCommand()
            return .success
        }

        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.endTrackingFromRemoteCommand()
            return .success
        }
    }

    private func endTrackingFromRemoteCommand() {
        DispatchQueue.main.async {
            BGLocationManager.sharedInstance().stop()
        }
    }

    private func hasAudioBackgroundMode() -> Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("audio") == true
    }

    private func log(_ message: String) {
        NSLog("[BGGEO][TrackingAudio] \(message)")
        BGLog.sharedInstance().notify(message, debug: true)
    }
}
