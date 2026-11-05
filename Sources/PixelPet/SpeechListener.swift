import AVFoundation
import PetCore
import Speech

/// The mic, turned into text on the Mac by the system's dictation model: no network, nothing written down.
/// The audio only lives in the buffers on their way to the recognizer.
@MainActor
final class SpeechListener {
    enum Failure: Error {
        case noPermission, noMic, unsupportedLanguage
        case failed(String)
    }

    /// The input level in dBFS, a few times a second.
    var onLevel: ((Float) -> Void)?
    /// Everything heard so far, the part still being recognized included.
    var onText: ((String) -> Void)?
    /// The language model is being downloaded (once per language).
    var onDownloading: ((Bool) -> Void)?

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var reader: Task<String, Never>?

    var isRunning: Bool { engine != nil }

    static func micAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    func start(locale: Locale) async throws(Failure) {
        guard await Self.micAccess() else { throw .noPermission }
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { throw .unsupportedLanguage }
        let transcriber = DictationTranscriber(locale: supported, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                                               reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onDownloading?(true)
                defer { onDownloading?(false) }
                try await request.downloadAndInstall()
            }
        } catch {
            throw .failed(error.localizedDescription)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw .unsupportedLanguage
        }
        let engine = AVAudioEngine()
        let micFormat = engine.inputNode.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0,
              let converter = AVAudioConverter(from: micFormat, to: format) else { throw .noMic }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        reader = Task { @MainActor [weak self] in
            var transcript = Transcript()
            do {
                for try await result in transcriber.results {
                    transcript.apply(String(result.text.characters), final: result.range.end <= result.resultsFinalizationTime)
                    self?.onText?(transcript.text)
                }
            } catch {}
            return transcript.text
        }
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            reader?.cancel()
            reader = nil
            throw .failed(error.localizedDescription)
        }
        let level: @Sendable (Float) -> Void = { [weak self] value in
            Task { @MainActor in self?.onLevel?(value) }
        }
        MicTap(converter: converter, format: format, input: continuation, level: level).install(on: engine.inputNode, format: micFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            reader?.cancel()
            reader = nil
            throw .noMic
        }
        self.engine = engine
        self.analyzer = analyzer
        self.input = continuation
    }

    /// Stop the mic and wait for the last words to be recognized.
    func finish() async -> String {
        stopMic()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = await reader?.value ?? ""
        analyzer = nil
        reader = nil
        return text
    }

    /// Stop at once and drop what was heard.
    func cancel() async {
        stopMic()
        await analyzer?.cancelAndFinishNow()
        reader?.cancel()
        analyzer = nil
        reader = nil
    }

    private func stopMic() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        input?.finish()
        input = nil
    }
}

/// Runs on the audio thread: converts each mic buffer to the recognizer's format and measures its level.
/// Not on the main actor, so the tap closure isn't either.
private final class MicTap: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let level: @Sendable (Float) -> Void

    init(converter: AVAudioConverter, format: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation,
         level: @escaping @Sendable (Float) -> Void) {
        self.converter = converter
        self.format = format
        self.input = input
        self.level = level
    }

    func install(on node: AVAudioInputNode, format micFormat: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [self] buffer, _ in receive(buffer) }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        level(Self.decibels(buffer))
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32)
        else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    /// RMS of the first channel in dBFS (-160 for silence).
    private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}
