//
//  SpeechRecognitionService.swift
//  Aura
//
//  Created on 9/9/25.
//

import Foundation
import Speech
import AVFoundation
import Combine
import os.log

class SpeechRecognitionService: ObservableObject {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "SpeechRecognitionService")
    
    // MARK: - Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    // MARK: - Publishers
    @Published var isRecognizing = false
    @Published var hasPermission = false
    @Published var recognizedText = ""
    @Published var recordingLevel: Float = 0.0
    
    // Callback for final transcription results
    var onTranscriptionComplete: ((String) -> Void)?
    
    // MARK: - Configuration
    private let silenceTimeout: TimeInterval = 3.0 // 3 seconds of silence
    private var silenceTimer: Timer?
    
    // MARK: - Initialization
    init() {
        setupSpeechRecognizer()
        checkPermissions()
    }
    
    // MARK: - Setup
    private func setupSpeechRecognizer() {
        // Try to use the user's preferred language, fallback to English
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        guard speechRecognizer != nil else {
            logger.error("❌ Speech recognizer not available for current locale")
            return
        }
        
        speechRecognizer?.delegate = self
        logger.info("✅ Speech recognizer initialized for locale: \(self.speechRecognizer?.locale.identifier ?? "unknown")")
    }
    
    // MARK: - Permission Management
    private func checkPermissions() {
        // Check speech recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        logger.info("📋 Current speech recognition permission: \(String(describing: speechStatus))")
        
        switch speechStatus {
        case .authorized:
            checkMicrophonePermission()
        case .denied, .restricted:
            logger.error("❌ Speech recognition permission denied or restricted")
            DispatchQueue.main.async {
                self.hasPermission = false
            }
        case .notDetermined:
            requestSpeechPermission()
        @unknown default:
            logger.warning("⚠️ Unknown speech recognition permission status")
            requestSpeechPermission()
        }
    }
    
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.logger.info("✅ Speech recognition permission granted")
                    self?.checkMicrophonePermission()
                case .denied, .restricted:
                    self?.logger.error("❌ Speech recognition permission denied")
                    self?.hasPermission = false
                case .notDetermined:
                    self?.logger.warning("⚠️ Speech recognition permission still not determined")
                    self?.hasPermission = false
                @unknown default:
                    self?.logger.error("❌ Unknown speech recognition authorization status")
                    self?.hasPermission = false
                }
            }
        }
    }
    
    private func checkMicrophonePermission() {
        let microphoneStatus = AVAudioSession.sharedInstance().recordPermission
        
        switch microphoneStatus {
        case .granted:
            logger.info("✅ Both speech recognition and microphone permissions granted")
            DispatchQueue.main.async {
                self.hasPermission = true
            }
        case .denied:
            logger.error("❌ Microphone permission denied")
            DispatchQueue.main.async {
                self.hasPermission = false
            }
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.logger.info("✅ Microphone permission granted")
                        self?.hasPermission = true
                    } else {
                        self?.logger.error("❌ Microphone permission denied by user")
                        self?.hasPermission = false
                    }
                }
            }
        @unknown default:
            logger.warning("⚠️ Unknown microphone permission status")
            DispatchQueue.main.async {
                self.hasPermission = false
            }
        }
    }
    
    // MARK: - Speech Recognition Control
    func startRecognition() throws {
        guard hasPermission else {
            throw SpeechRecognitionError.permissionDenied
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        
        // Cancel any existing recognition task
        stopRecognition()
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateRecordingLevel(from: buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error)
        }
        
        DispatchQueue.main.async {
            self.isRecognizing = true
            self.recognizedText = ""
        }
        
        logger.info("🎤 Speech recognition started")
        startSilenceTimer()
    }
    
    func stopRecognition() {
        // Stop silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Finish recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isRecognizing = false
            self.recordingLevel = 0.0
        }
        
        logger.info("🛑 Speech recognition stopped")
    }
    
    // MARK: - Recognition Result Handling
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            logger.error("❌ Speech recognition error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.stopRecognition()
            }
            return
        }
        
        guard let result = result else { return }
        
        let transcribedText = result.bestTranscription.formattedString
        
        DispatchQueue.main.async {
            self.recognizedText = transcribedText
            
            // Reset silence timer on new speech
            if !transcribedText.isEmpty {
                self.resetSilenceTimer()
            }
        }
        
        // If result is final, complete transcription
        if result.isFinal {
            logger.info("✅ Final transcription: \(transcribedText)")
            DispatchQueue.main.async {
                self.stopRecognition()
                self.onTranscriptionComplete?(transcribedText)
            }
        }
    }
    
    // MARK: - Audio Level Monitoring
    private func updateRecordingLevel(from buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let channelDataValue = floatData.pointee
        let samples = UnsafeBufferPointer(start: channelDataValue, count: Int(buffer.frameLength))
        
        // Calculate RMS (Root Mean Square) for audio level
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        
        DispatchQueue.main.async {
            self.recordingLevel = min(rms * 10, 1.0) // Scale and clamp to 0-1
        }
    }
    
    // MARK: - Silence Detection
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleSilenceTimeout()
            }
        }
    }
    
    private func resetSilenceTimer() {
        startSilenceTimer()
    }
    
    private func handleSilenceTimeout() {
        guard isRecognizing else { return }
        
        logger.info("⏱️ Silence timeout reached, stopping recognition")
        
        // Complete transcription with current text
        let currentText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecognition()
        
        if !currentText.isEmpty {
            onTranscriptionComplete?(currentText)
        }
    }
    
    // MARK: - Helper Methods
    func recheckPermissions() {
        checkPermissions()
    }
    
    var isAvailable: Bool {
        return speechRecognizer?.isAvailable ?? false
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechRecognitionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        logger.info("🔄 Speech recognizer availability changed: \(available)")
        DispatchQueue.main.async {
            // If recognizer becomes unavailable while recognizing, stop
            if !available && self.isRecognizing {
                self.stopRecognition()
            }
        }
    }
}

// MARK: - Error Handling
enum SpeechRecognitionError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case requestCreationFailed
    case audioSessionError(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition or microphone permission denied"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .audioSessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        }
    }
}