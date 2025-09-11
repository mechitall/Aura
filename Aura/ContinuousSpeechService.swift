//
//  ContinuousSpeechService.swift
//  Aura
//
//  Created on 9/9/25.
//

import Foundation
import AVFoundation
import Speech
import Combine
import os.log

@MainActor
class ContinuousSpeechService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ContinuousSpeechService")
    
    // MARK: - Configuration
    private let accumulationInterval: TimeInterval = 60.0 // 1 minute
    private let silenceThreshold: TimeInterval = 2.5 // Stop after 2.5 seconds of silence
    private let minimumSpeechDuration: TimeInterval = 0.8 // Minimum speech to consider
    private let noiseFloor: Float = -50.0 // dB threshold for meaningful audio
    private let speechConfidenceThreshold: Float = 0.3 // Minimum confidence for speech
    private let maxSessionDuration: TimeInterval = 30.0 // Max single session duration
    
    // MARK: - Speech Recognition Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Audio Properties
    private var audioEngine = AVAudioEngine()
    private var accumulationTimer: Timer?
    private var silenceTimer: Timer?
    private var lastSpeechTime: Date?
    
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var hasPermission = false
    @Published var accumulatedText = ""
    @Published var currentSessionText = ""
    @Published var recordingLevel: Float = 0.0
    @Published var timeUntilNextSend: TimeInterval = 0
    // Language management
    @Published var activeLanguage: SpeechLanguage = .english {
        didSet {
            if oldValue != self.activeLanguage {
                self.logger.info("🌐 Switching speech recognition language to \(self.activeLanguage.rawValue)")
                self.rebuildRecognizerForActiveLanguage()
            }
        }
    }
    
    // MARK: - Callbacks
    var onTextAccumulated: ((String) -> Void)?
    // Raw final utterance callback (for language detection heuristics)
    var onFinalUserUtterance: ((String) -> Void)?
    
    // MARK: - Private Properties
    private var speechSegments: [String] = []
    private var isCurrentlyRecognizing = false
    private var sessionStartTime: Date?
    private var currentSessionStartTime: Date?
    private var averageAudioLevel: Float = 0.0
    private var speechActivity: Bool = false
    private var consecutiveSilenceCount: Int = 0
    private var lastMeaningfulSpeechTime: Date?
    private var autoStarted: Bool = false
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        
        // Request permissions explicitly on init
        requestAllPermissions()
        
        // Auto-start after permissions are handled
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.hasPermission && !self.isListening {
                self.logger.info("🎯 Auto-starting continuous listening after permission check")
                self.autoStarted = true
                self.startContinuousListening()
            }
        }
    }
    
    private func requestAllPermissions() {
        // First check if we need to request speech recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            logger.info("📋 Requesting speech recognition permission...")
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.logger.info("📋 Speech recognition permission result: \(String(describing: status))")
                    self?.checkPermissions()
                }
            }
        } else {
            checkPermissions()
        }
    }
    
    // MARK: - Setup
    private func setupSpeechRecognizer() {
        // Prefer the explicitly selected activeLanguage over system locale for determinism.
    let locale = self.activeLanguage.locale
        speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        logger.info("✅ Continuous speech recognizer initialized for locale: \(self.speechRecognizer?.locale.identifier ?? "unknown")")
    }

    private func rebuildRecognizerForActiveLanguage() {
        // Stop any current recognition session first
        let wasListening = isListening
        if wasListening { stopContinuousListening() }
        stopCurrentSession()
        speechRecognizer = nil
        setupSpeechRecognizer()
        if wasListening {
            // Resume after small delay to avoid race with AVAudioSession teardown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.startContinuousListening()
            }
        }
    }

    /// Public setter to change language externally.
    func setLanguage(_ language: SpeechLanguage) {
        guard activeLanguage != language else { return }
        activeLanguage = language
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Use proper category for speech recognition
            try audioSession.setCategory(.record, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Set preferred sample rate and buffer duration for speech recognition
            try audioSession.setPreferredSampleRate(16000.0)
            try audioSession.setPreferredIOBufferDuration(0.005)
            
            logger.info("✅ Audio session configured successfully")
        } catch {
            logger.error("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Permission Handling
    private func checkPermissions() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        logger.info("📋 Current speech recognition permission: \(String(describing: speechStatus))")
        
        switch speechStatus {
        case .authorized:
            logger.info("✅ Speech recognition permission already granted")
            checkMicrophonePermission()
        case .denied, .restricted:
            logger.error("❌ Speech recognition permission denied or restricted")
            hasPermission = false
        case .notDetermined:
            logger.info("❓ Speech recognition permission not determined, requesting...")
            requestSpeechPermission()
        @unknown default:
            logger.warning("⚠️ Unknown speech recognition permission status")
            requestSpeechPermission()
        }
    }
    
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
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
        let permission = AVAudioSession.sharedInstance().recordPermission
        logger.info("📋 Current microphone permission status: \(String(describing: permission))")
        
        switch permission {
        case .granted:
            logger.info("✅ Both speech recognition and microphone permissions granted")
            hasPermission = true
            
            // Auto-start if not already listening and not manually started
            if !isListening && !autoStarted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.autoStarted = true
                    self.startContinuousListening()
                }
            }
        case .denied:
            logger.error("❌ Microphone permission denied")
            hasPermission = false
        case .undetermined:
            logger.info("❓ Microphone permission undetermined, requesting...")
            requestMicrophonePermission()
        @unknown default:
            logger.warning("⚠️ Unknown microphone permission status")
            requestMicrophonePermission()
        }
    }
    
    private func requestMicrophonePermission() {
        logger.info("🎤 Requesting microphone permission...")
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if granted {
                    self?.logger.info("✅ Microphone permission granted by user")
                    self?.hasPermission = true
                    
                    // Auto-start after permission granted
                    if let self = self, !self.isListening && !self.autoStarted {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.logger.info("🎯 Auto-starting after microphone permission granted")
                            self.autoStarted = true
                            self.startContinuousListening()
                        }
                    }
                } else {
                    self?.logger.error("❌ Microphone permission denied by user")
                    self?.logger.error("ℹ️ Please enable microphone access in Settings > Privacy & Security > Microphone")
                    self?.hasPermission = false
                }
            }
        }
    }
    
    // MARK: - Public Interface
    func startContinuousListening() {
        guard hasPermission else {
            logger.error("❌ Cannot start continuous listening: Permission not granted")
            logger.error("ℹ️ Please ensure both Speech Recognition and Microphone permissions are enabled")
            return
        }
        
        guard let speechRecognizer = speechRecognizer else {
            logger.error("❌ Cannot start continuous listening: Speech recognizer not initialized")
            return
        }
        
        guard speechRecognizer.isAvailable else {
            logger.error("❌ Cannot start continuous listening: Speech recognizer unavailable")
            logger.error("ℹ️ Speech recognition may not be supported on this device or in simulator")
            return
        }
        
        guard !isListening else {
            logger.info("ℹ️ Continuous listening already active")
            return
        }
        
        logger.info("🎤 Starting continuous speech recognition")
        logger.info("🎯 Speech recognizer locale: \(speechRecognizer.locale.identifier)")
        
        isListening = true
        
        // Start the accumulation timer
        startAccumulationTimer()
        
        // Start listening for speech
        startListeningSession()
    }
    
    func stopContinuousListening() {
        logger.info("🛑 Stopping continuous speech recognition")
        
        isListening = false
        
        // Stop timers
        accumulationTimer?.invalidate()
        accumulationTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop current recognition session
        stopCurrentSession()
        
        // Process any remaining accumulated text
        if !accumulatedText.isEmpty {
            logger.info("📤 Processing final accumulated text before stopping")
            processAccumulatedText()
        }
    }
    
    func recheckPermissions() {
        checkPermissions()
    }
    
    // MARK: - Private Implementation
    private func startAccumulationTimer() {
        accumulationTimer = Timer.scheduledTimer(withTimeInterval: accumulationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.processAccumulatedText()
            }
        }
        
        // Start countdown timer
        updateTimeUntilNextSend()
    }
    
    private func updateTimeUntilNextSend() {
        guard accumulationTimer != nil else { return }
        
        if sessionStartTime == nil {
            sessionStartTime = Date()
        }
        
        let elapsed = Date().timeIntervalSince(sessionStartTime!)
        timeUntilNextSend = max(0, accumulationInterval - elapsed.truncatingRemainder(dividingBy: accumulationInterval))
        
        // Schedule next update
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateTimeUntilNextSend()
        }
    }
    
    private func processAccumulatedText() {
        guard !accumulatedText.isEmpty else {
            logger.info("ℹ️ No accumulated text to process")
            return
        }
        
        let textToProcess = accumulatedText
        logger.info("📤 Processing accumulated text (\(textToProcess.count) chars): \(String(textToProcess.prefix(100)))...")
        
        // Clear accumulated text
        accumulatedText = ""
        speechSegments.removeAll()
        
        // Send to callback
        onTextAccumulated?(textToProcess)
        
        // Reset timer
        sessionStartTime = Date()
    }
    
    private func startListeningSession() {
        // Stop any existing session
        stopCurrentSession()
        
        do {
            setupAudioSession()
            
            // Create new recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                logger.error("❌ Failed to create recognition request")
                return
            }
            
            // Configure recognition request for optimal speech detection
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy
            
            // Enhanced configuration for better recognition
            if #available(iOS 16.0, *) {
                recognitionRequest.addsPunctuation = true
            }
            
            // Set task hint for better speech recognition
            if #available(iOS 13.0, *) {
                recognitionRequest.taskHint = .search
            }
            
            logger.info("✅ Recognition request configured")
            
            // Setup audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            logger.info("🎤 Audio format: \(recordingFormat)")
            
            // Remove any existing taps first
            inputNode.removeTap(onBus: 0)
            
            // Install tap with optimal buffer size for speech recognition
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                // Process audio buffer on background queue to avoid blocking
                DispatchQueue.global(qos: .userInteractive).async {
                    self?.recognitionRequest?.append(buffer)
                    
                    Task { @MainActor in
                        self?.updateRecordingLevel(from: buffer)
                        self?.detectSpeechActivity(from: buffer)
                    }
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            logger.info("✅ Audio engine started successfully")
            
            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleRecognitionResult(result: result, error: error)
                }
            }
            
            isCurrentlyRecognizing = true
            currentSessionStartTime = Date()
            logger.info("✅ Speech recognition session started")
            
            // Add session timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + maxSessionDuration) {
                if self.isCurrentlyRecognizing && self.currentSessionStartTime != nil {
                    let sessionDuration = Date().timeIntervalSince(self.currentSessionStartTime!)
                    if sessionDuration >= self.maxSessionDuration {
                        self.logger.info("⏰ Session timeout reached, restarting")
                        self.restartSessionIfNeeded()
                    }
                }
            }
            
        } catch {
            logger.error("❌ Failed to start listening session: \(error)")
            // Retry after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isListening {
                    self.startListeningSession()
                }
            }
        }
    }
    
    private func stopCurrentSession() {
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // End recognition
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isCurrentlyRecognizing = false
        recordingLevel = 0.0
        
        logger.info("🛑 Recognition session stopped")
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Suppress common simulator/network errors to avoid log spam
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
                // This is a common, noisy error on the simulator. Don't log it as an error.
                logger.debug("🎤 Ignoring common speech recognition error (code 1101)")
            } else {
                logger.error("Speech recognition error: \(error.localizedDescription)")
            }

            // Restart session after error with exponential backoff
            let delay = min(8.0, pow(2.0, Double(consecutiveSilenceCount)))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.isListening {
                    self.startListeningSession()
                }
            }
            return
        }
        
        guard let result = result else { return }
        
        let transcription = result.bestTranscription.formattedString
        let confidence = result.bestTranscription.segments.map { $0.confidence }.reduce(0, +) / Float(max(1, result.bestTranscription.segments.count))
        
        currentSessionText = transcription
        
        if result.isFinal {
            logger.info("✅ Final transcription segment (confidence: \(confidence)): \(transcription)")
            
            // Add to accumulated text if meaningful and confident enough
            let cleanedText = cleanTranscription(transcription)
            if isValidSpeech(cleanedText, confidence: confidence) {
                if !accumulatedText.isEmpty {
                    accumulatedText += " "
                }
                accumulatedText += cleanedText
                speechSegments.append(cleanedText)
                lastMeaningfulSpeechTime = Date()
                consecutiveSilenceCount = 0
                // Fire per-utterance callback for auto-language detection
                onFinalUserUtterance?(cleanedText)
                
                logger.info("📝 Added to accumulation: \(cleanedText) (Total: \(self.accumulatedText.count) chars)")
            }
            
            // Clear current session text
            currentSessionText = ""
            
            // Start silence timer
            startSilenceTimer()
        } else {
            // Reset silence timer on partial results if they seem meaningful
            if !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && confidence > speechConfidenceThreshold {
                lastSpeechTime = Date()
                silenceTimer?.invalidate()
            }
        }
    }
    
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceDetected()
            }
        }
    }
    
    private func handleSilenceDetected() {
        consecutiveSilenceCount += 1
        logger.info("🔇 Silence detected (count: \(self.consecutiveSilenceCount)), restarting recognition session")
        
        if isListening {
            // Restart the listening session for continuous operation
            let delay = min(2.0, 0.5 + Double(consecutiveSilenceCount) * 0.2)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.isListening {
                    self.startListeningSession()
                }
            }
        }
    }
    
    private func updateRecordingLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0,
                                         to: Int(buffer.frameLength),
                                         by: buffer.stride).map { channelDataValue[$0] }
        
        let level = calculateAudioLevel(from: channelDataValueArray)
        recordingLevel = level
    }
    
    private func calculateAudioLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let squaredSamples = samples.map { $0 * $0 }
        let averagePower = squaredSamples.reduce(0, +) / Float(samples.count)
        
        if averagePower > 0 {
            let decibels = 10 * log10(averagePower)
            let normalizedLevel = max(0, (decibels + 60) / 60)
            
            // Update running average
            averageAudioLevel = (averageAudioLevel * 0.8) + (normalizedLevel * 0.2)
            
            return normalizedLevel
        }
        
        return 0.0
    }
    
    // MARK: - Enhanced Speech Processing
    private func detectSpeechActivity(from buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let channelDataValue = floatData.pointee
        let samples = Array(UnsafeBufferPointer(start: channelDataValue, count: Int(buffer.frameLength)))
        
        // Calculate RMS and detect speech activity
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let dbLevel = rms > 0 ? 20 * log10(rms) : -160.0
        
        speechActivity = dbLevel > noiseFloor
    }
    
    private func cleanTranscription(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common false positives and noise
        let noisePhrases = ["um", "uh", "hmm", "mm", "ah", "er", "..."]
        var result = cleaned
        
        for phrase in noisePhrases {
            result = result.replacingOccurrences(of: "\\b\(phrase)\\b", with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Clean up extra whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isValidSpeech(_ text: String, confidence: Float) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check minimum length and confidence
        guard cleanText.count >= 2, confidence >= speechConfidenceThreshold else {
            return false
        }
        
        // Reject if mostly numbers or symbols
        let letterCount = cleanText.filter { $0.isLetter }.count
        let totalCount = cleanText.count
        
        return Double(letterCount) / Double(totalCount) >= 0.5
    }
    
    // MARK: - Public Methods
    func clearAccumulatedText() {
        logger.info("🧹 Clearing accumulated text")
        accumulatedText = ""
        currentSessionText = ""
        speechSegments.removeAll()
    }
    
    // Set test accumulated text for simulator testing
    func setTestAccumulatedText(_ text: String) {
        logger.info("🧪 Setting test accumulated text: \(text)")
        accumulatedText = text
    }
    
    private func restartSessionIfNeeded() {
        guard isListening else { return }
        
        logger.info("🔄 Restarting recognition session for continuous listening")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.isListening {
                self.startListeningSession()
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension ContinuousSpeechService {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        logger.info("Speech recognizer availability changed: \(available)")
        
        if !available {
            Task { @MainActor in
                if self.isListening {
                    self.logger.warning("⚠️ Speech recognizer became unavailable, stopping continuous listening")
                    self.stopContinuousListening()
                }
            }
        }
    }
}