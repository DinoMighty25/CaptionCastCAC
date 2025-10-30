//
//  SpeechRecognitionService.swift
//  captionapp5
//
//
import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine

class SpeechRecognitionService: NSObject, ObservableObject {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var error: Error?
    @Published var confidence: Float = 0.0

    // Callbacks
    var onTranscriptionResult: ((String, Bool, Float?) -> Void)?
    var onError: ((Error) -> Void)?

    // For sentence boundary detection
    private var partialText: String = ""
    private var lastSignificantText: String = ""
    private var lastProcessedText: String = ""
    private var sentenceEndTimer: Timer?
    private var duplicatePreventionTimer: Timer?
    
    // Duplicate suppression
    private var lastEmittedFinalText: String = ""
    
    private var lastEmittedPartialText: String = ""
    
    // Audio Level Gating - prevent distant voices from triggering transcription
    private var currentAudioLevel: Float = 0.0
    private var audioLevelThreshold: Float {
        get {
            let saved = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.audioThreshold)
            return saved != 0 ? Float(saved) : Constants.defaultAudioThreshold
        }
    }
    @Published var isSpeakerNearby: Bool = false
    
    // Configuration
    private var isContinuousMode = true
    private var recognitionTimeout: Timer?
    private var silenceTimer: Timer?
    private var lastSpeechTime = Date()
    private var lastFinalizationTime = Date()
    private var isFinalizingOnSilence = false
    private var hasFinalizedCurrentSession = false // Track if we've already processed a final result
    private var restartWorkItem: DispatchWorkItem? // For cancelling pending restarts
    
    // Session state tracking
    private enum SessionState {
        case idle, recognizing, finalizing, restarting
    }
    private var sessionState: SessionState = .idle
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        checkAuthorization()
    }
    
    deinit {
        stopRecording()
        cleanupTimers()
        recognizer = nil
        print("SpeechRecognitionService deallocated")
    }
    
    private func cleanupTimers() {
        recognitionTimeout?.invalidate()
        recognitionTimeout = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        sentenceEndTimer?.invalidate()
        sentenceEndTimer = nil
        duplicatePreventionTimer?.invalidate()
        duplicatePreventionTimer = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognizer() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.delegate = self
        
        // Configure audio session
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to setup audio session: \(error)")
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    private func checkAuthorization() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        case .notDetermined:
            requestAuthorization()
        @unknown default:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        guard isAuthorized else {
            error = SpeechRecognitionError.notAuthorized
            return
        }
        
        guard !isRecording else { return }
        
        do {
            try startAudioEngine()
            startRecognition()
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.transcribedText = ""
                self.error = nil
            }
            
            print("Started speech recognition")
        } catch {
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Before stopping, check if there's a final piece of text to send.
        let finalFragment = lastEmittedPartialText
        if !finalFragment.isEmpty && finalFragment != lastEmittedFinalText {
            print("Finalizing last partial text before stopping: '\(finalFragment)'")
            onTranscriptionResult?(finalFragment, true, confidence)
            lastEmittedFinalText = finalFragment
        }
        
        stopRecognition()
        stopAudioEngine()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        print("Stopped speech recognition")
    }
    
    func pauseRecording() {
        guard isRecording else { return }
        
        recognitionRequest?.endAudio()
        audioEngine.stop()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    func resumeRecording() {
        guard !isRecording else { return }
        
        do {
            try startAudioEngine()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true // Enable automatic punctuation
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        recognitionRequest.requiresOnDeviceRecognition = true
        
        // Set up microphone listening
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Constants.maxAudioBufferSize), format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Check if someone's actually talking nearby
            self.checkIfSpeakerIsNearby(from: buffer)
            
            // Only send to speech recognition if it's loud enough
            // This stops distant voices from being transcribed
            if self.currentAudioLevel > self.audioLevelThreshold {
                self.recognitionRequest?.append(buffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    // Check if someone's actually talking near this device
    // Stops the app from transcribing distant conversations
    private func checkIfSpeakerIsNearby(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        
        // Calculate how loud the audio is
        var totalSquaredVolume: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            totalSquaredVolume += sample * sample
        }
        
        let averageVolume = sqrt(totalSquaredVolume / Float(frameLength))
        
        // Convert to decibels
        // Normal speaking = around -30 dB
        let volumeInDecibels = 20 * log10(averageVolume)
        
        // Update our tracking
        DispatchQueue.main.async {
            self.currentAudioLevel = volumeInDecibels
            self.isSpeakerNearby = volumeInDecibels > self.audioLevelThreshold
        }
    }
    
    private func startRecognition() {
        sessionState = .recognizing
        isFinalizingOnSilence = false
        hasFinalizedCurrentSession = false
        guard let recognizer = recognizer,
              let recognitionRequest = recognitionRequest else {
            error = SpeechRecognitionError.recognizerNotAvailable
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.handleRecognitionError(error)
                    return
                }

                if let result = result {
                    self.handleRecognitionResult(result)
                } else {
                    self.error = SpeechRecognitionError.noResult
                }
            }
        }
    }
    
    private func stopRecognition() {
        recognitionTask?.finish() // Finish instead of cancel to get final result
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        sessionState = .idle
    }
    
    private func stopAudioEngine() {
        // Stop audio engine safely
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let transcribedText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        //simple finalization logic – no length checks, no heavy suppression
        let isFinalByPause = result.isFinal
        let endsWithPunctuation = [".", "?", "!"].contains { transcribedText.hasSuffix($0) }
        let shouldFinalize = isFinalByPause || endsWithPunctuation

        if shouldFinalize {
            guard !transcribedText.isEmpty else {
                self.onTranscriptionResult?("", true, 0.0)
                lastEmittedFinalText = ""
                lastEmittedPartialText = ""
                restartRecognition()
                return
            }

            self.onTranscriptionResult?(transcribedText, true, calculateAverageConfidence(from: result.bestTranscription))
            lastEmittedFinalText = transcribedText
            lastEmittedPartialText = ""
            
        } else {
            // It's a partial result, send it for live preview
            if transcribedText != lastEmittedPartialText {
                self.onTranscriptionResult?(transcribedText, false, calculateAverageConfidence(from: result.bestTranscription))
                lastEmittedPartialText = transcribedText
            }
        }
    }

    

    private func restartRecognition() {
        // Prevent rapid restarts
        guard sessionState != .restarting else { return }
        sessionState = .restarting
        
        stopRecognition()
        
        // Brief delay to allow services to reset cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.isRecording {
                do {
                    // We only need to restart the recognition part, not the whole audio engine
                    try self.startAudioEngineForRestart()
                    self.startRecognition()
                } catch {
                    self.error = error
                }
            }
        }
    }

    private func startAudioEngineForRestart() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        recognitionRequest.requiresOnDeviceRecognition = true

        // Re-install the tap if it was removed
        let inputNode = audioEngine.inputNode
        if inputNode.numberOfInputs == 0 {
             let recordingFormat = inputNode.outputFormat(forBus: 0)
             inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Constants.maxAudioBufferSize), format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
        }
        
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
    }

    private func calculateAverageConfidence(from transcription: SFTranscription) -> Float {
        guard !transcription.segments.isEmpty else { return 0.0 }

        let totalConfidence = transcription.segments.reduce(0.0) { sum, segment in
            return sum + segment.confidence
        }

        return totalConfidence / Float(transcription.segments.count)
    }

    private func handleRecognitionError(_ error: Error) {
        let nsError = error as NSError
        // Ignore "speech recognition is finishing" error which can happen during restarts
        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
            return
        }
        
        switch nsError.code {
        case 203: // SFSpeechRecognizerErrorCode.notAuthorized
            self.error = SpeechRecognitionError.notAuthorized
        case 201: // SFSpeechRecognizerErrorCode.recognizerNotAvailable
            self.error = SpeechRecognitionError.recognizerNotAvailable
        case 209: // SFSpeechRecognizerErrorCode.networkError
            self.error = SpeechRecognitionError.networkError
        case 207: // SFSpeechRecognizerErrorCode.audioEngineError
            self.error = SpeechRecognitionError.audioEngineStartFailed
        default:
            self.error = SpeechRecognitionError.unknownError(error)
        }
        
        // Stop recording on error
        if isRecording {
            stopRecording()
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isRecording {
                self.stopRecording()
                self.error = SpeechRecognitionError.recognizerNotAvailable
            }
        }
    }
}

// MARK: - Error Types

enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case requestCreationFailed
    case audioEngineStartFailed
    case networkError
    case noResult
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable it in Settings."
        case .recognizerNotAvailable:
            return "Speech recognizer not available. Please try again later."
        case .requestCreationFailed:
            return "Failed to create recognition request. Please restart the app."
        case .audioEngineStartFailed:
            return "Failed to start audio engine. Please check microphone permissions."
        case .networkError:
            return "Network error occurred. Please check your internet connection."
        case .noResult:
            return "No speech recognition result received. Please try speaking again."
        case .unknownError(let error):
            return "Speech recognition error: \(error.localizedDescription)"
        }
    }
}
