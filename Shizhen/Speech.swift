import Foundation
import AVFoundation
import Speech

/// Voice guidance (zh-CN / en-US) and on-device speech recognition for word recall.
final class Voice: NSObject, ObservableObject {
    static let shared = Voice()
    private let synth = AVSpeechSynthesizer()

    func say(_ zh: String, _ en: String) {
        let lang = AppStore.currentLanguage
        let u = AVSpeechUtterance(string: lang == .zh ? zh : en)
        u.voice = AVSpeechSynthesisVoice(language: lang == .zh ? "zh-CN" : "en-US")
        u.rate = 0.42
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

final class Listener: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var available = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func prepare() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: AppStore.currentLanguage == .zh ? "zh-CN" : "en-US"))
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.available = status == .authorized && granted && (self.recognizer?.isAvailable ?? false)
                }
            }
        }
    }

    func start() {
        guard available, let recognizer, !isListening else { return }
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { return }
        isListening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                if let r = result { self?.transcript = r.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self?.stop() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
}
