import Foundation
import AVFoundation

/// Manages CarPlay spoken turn-by-turn audio guidance through car speakers with audio ducking
final class CarPlayVoiceGuidance: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    static let shared = CarPlayVoiceGuidance()

    private let synthesizer = AVSpeechSynthesizer()
    private var isMuted: Bool = false
    private var lastSpokenPhrase: String = ""
    private var lastSpokenTimestamp: Date = Date.distantPast

    private override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        } catch {
            NSLog("VOYPLAN CarPlay: Failed to configure navigation audio session: \(error)")
        }
    }

    func setMuted(_ muted: Bool) {
        self.isMuted = muted
        if muted && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func toggleMute() -> Bool {
        setMuted(!isMuted)
        return isMuted
    }

    func speak(_ text: String, force: Bool = false) {
        guard !isMuted else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prevent repeating identical prompt within 8 seconds unless forced
        if !force && trimmed == lastSpokenPhrase && Date().timeIntervalSince(lastSpokenTimestamp) < 8.0 {
            return
        }

        lastSpokenPhrase = trimmed
        lastSpokenTimestamp = Date()

        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            NSLog("VOYPLAN CarPlay: AudioSession setActive error: \(error)")
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        synthesizer.speak(utterance)
        NSLog("VOYPLAN CarPlay Voice: \"\(trimmed)\"")
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Deactivate audio session to un-duck car radio/music
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
