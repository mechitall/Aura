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
    // Reduced interval so user gets responses faster (was 60s)
    private let accumulationInterval: TimeInterval = 30.0 // send roughly every 30s
    private let speechConfidenceThreshold: Float = 0.15 // Slightly lower to capture more words
    private let maxSessionDuration: TimeInterval = 55.0 // Slightly under 60s to avoid iOS limits
    // New heuristics for immediate sentence-based sending
    private let minSentenceSendChars: Int = 40 // minimum accumulated chars before sending on punctuation
    private let minSecondsBetweenAutoSends: TimeInterval = 8.0 // debounce for auto sentence sends
    private let largeChunkImmediateThreshold: Int = 120 // existing large accumulation trigger

    // Response strategy (future flexibility)
    enum ResponseStrategy {
        case intervalOnly      // Only timer / large chunk
        case sentenceOrInterval // Sentence punctuation OR timer (default)
    }
    var responseStrategy: ResponseStrategy = .sentenceOrInterval
    
    // MARK: - Speech Recognition Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Audio Properties
    private var audioEngine = AVAudioEngine()
    private var accumulationTimer: Timer?
    private var sessionRestartTimer: Timer?
    
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var hasPermission = false
    @Published var accumulatedText = ""
    @Published var currentSessionText = ""
    @Published var recordingLevel: Float = 0.0
    @Published var timeUntilNextSend: TimeInterval = 0
    // Diagnostics
    @Published var lastFinalSegment: String = ""
    
    // MARK: - Callbacks
    var onTextAccumulated: ((String) -> Void)?
    
    // MARK: - Private Properties
    private var speechSegments: [String] = []
    private var isCurrentlyRecognizing = false
    private var sessionStartTime: Date?
    private var currentSessionStartTime: Date?
    private var averageAudioLevel: Float = 0.0
    private var autoStarted: Bool = false
    private var isProcessingText = false
    private var lastAutoTriggerTime: Date?
    private var consecutiveNoSpeechErrors: Int = 0
    private var nextRetryDelay: TimeInterval = 1.0
    
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
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        logger.info("✅ Continuous speech recognizer initialized for locale: \(self.speechRecognizer?.locale.identifier ?? "unknown")")
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
        
        // Stop all timers
        accumulationTimer?.invalidate()
        accumulationTimer = nil
        sessionRestartTimer?.invalidate()
        sessionRestartTimer = nil
        
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
        guard !accumulatedText.isEmpty && !isProcessingText else {
            if isProcessingText {
                logger.info("⏳ Already processing text, skipping...")
            } else {
                logger.info("ℹ️ No accumulated text to process")
            }
            return
        }
        
        let textToProcess = accumulatedText
        logger.info("📤 Processing accumulated text (\(textToProcess.count) chars): \(String(textToProcess.prefix(100)))...")
        
        // Mark as processing - DO NOT clear text yet
        isProcessingText = true
        logger.info("🔒 Marked text as processing - waiting for confirmation")
        
        // Send to callback
        onTextAccumulated?(textToProcess)
        
        // Reset timer
        sessionStartTime = Date()
    }
    
    // Called by ChatViewModel when AI processing completes successfully
    func confirmTextProcessed() {
        logger.info("✅ CONFIRMING TEXT PROCESSING COMPLETE")
        
        guard isProcessingText else {
            logger.warning("⚠️ Attempted to confirm when no text was being processed")
            return
        }
        
        // NOW clear accumulated data after successful processing
        accumulatedText = ""
        speechSegments.removeAll()
        isProcessingText = false
        
        logger.info("🧹 Cleared accumulated data after successful AI processing")
    }
    
    // Called by ChatViewModel if AI processing fails
    func handleProcessingError() {
        logger.error("❌ AI PROCESSING FAILED - keeping accumulated text for retry")
        isProcessingText = false
        logger.info("🔓 Unlocked processing state, keeping text: '\(String(self.accumulatedText.prefix(50)))...'")
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
            logger.info("✅ Continuous speech recognition session started (no silence detection)")
            
            // Schedule automatic session restart to maintain continuous operation
            scheduleSessionRestart()
            
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
            logger.error("Speech recognition error: \(error.localizedDescription)")
            if error.localizedDescription.contains("No speech detected") {
                self.consecutiveNoSpeechErrors += 1
                self.nextRetryDelay = min(5.0, self.nextRetryDelay * 1.3)
                if self.consecutiveNoSpeechErrors == 3 {
                    self.logger.warning("🤔 Detected repeated 'No speech detected' errors. If you're in Simulator enable 'Audio Input > Mac Microphone'.")
                }
            } else {
                self.consecutiveNoSpeechErrors = 0
                self.nextRetryDelay = 1.0
            }
            let delay = self.nextRetryDelay
            self.logger.info("🔄 Restarting recognition after delay=\(String(format: "%.2f", delay))s (noSpeechErrors=\(self.consecutiveNoSpeechErrors))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.isListening {
                    self.startListeningSession()
                }
            }
            return
        }
        
        guard let result = result else { return }
        
        let transcription = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = result.bestTranscription.segments.map { $0.confidence }.reduce(0, +) / Float(max(1, result.bestTranscription.segments.count))
        
        // Always update current session text (for UI display)
        currentSessionText = transcription
        
        if result.isFinal {
            logger.info("✅ Final transcription (confidence: \(String(format: "%.2f", confidence))): \(transcription)")
            
            // Add ALL final text to accumulation (no silence detection)
            let cleanedText = cleanTranscription(transcription)
            if !cleanedText.isEmpty && confidence >= speechConfidenceThreshold {
                appendToAccumulation(cleanedText)
                lastFinalSegment = cleanedText
                logger.info("📝 Final segment accumulated: \(cleanedText) (Total: \(self.accumulatedText.count) chars)")

                let endsWithPunctuation = cleanedText.last.map { [".", "?", "!"].contains(String($0)) } ?? false

                // Large chunk trigger (existing behavior but now uses constant)
                if self.accumulatedText.count >= self.largeChunkImmediateThreshold && self.canAutoTrigger() {
                    logger.info("⚡ Immediate processing: large accumulated chunk (\(self.accumulatedText.count) chars >= \(self.largeChunkImmediateThreshold))")
                    self.processAccumulatedText()
                }
                // Sentence-ending trigger (if strategy allows and length threshold met)
                else if self.responseStrategy == .sentenceOrInterval && endsWithPunctuation && self.accumulatedText.count >= self.minSentenceSendChars && self.canAutoTrigger() {
                    logger.info("⚡ Immediate processing: sentence end detected ('\(cleanedText.suffix(1))') with accumulated=\(self.accumulatedText.count) chars")
                    self.processAccumulatedText()
                }
            }

            // Clear current session text after adding to accumulation
            currentSessionText = ""
        } else {
            // Show partial results in UI and opportunistically accumulate stable trailing portion
            logger.debug("🔄 Partial: \(transcription) (conf: \(String(format: "%.2f", confidence)))")
            accumulateStablePartial(result: result, confidence: confidence)
        }
    }

    // Append text safely to accumulation
    private func appendToAccumulation(_ text: String) {
        if !accumulatedText.isEmpty { accumulatedText += " " }
        accumulatedText += text
        speechSegments.append(text)
        logger.debug("ACCUM += (total=\(self.accumulatedText.count)) last='\(text)'")
    }

    // Debounce auto triggers
    private func canAutoTrigger() -> Bool {
        if isProcessingText { return false }
        let now = Date()
        if let last = lastAutoTriggerTime, now.timeIntervalSince(last) < minSecondsBetweenAutoSends { return false }
        lastAutoTriggerTime = now
        return true
    }

    // Heuristic: accumulate partial text segments that are unlikely to change dramatically.
    // We look at the last transcription segment; if its duration/length passes thresholds we treat it as stable.
    private func accumulateStablePartial(result: SFSpeechRecognitionResult, confidence: Float) {
        guard confidence >= speechConfidenceThreshold else { return }
        let transcription = result.bestTranscription
        guard let lastSegment = transcription.segments.last else { return }
        // Only accumulate if segment ended > 0.8s ago to reduce duplication while text still mutating
    // SFTranscription doesn't expose a global start timestamp; approximate stability by segment duration only.
    // If the last segment is reasonably long, treat it as stable after a short delay since partial updates stopped.
    if lastSegment.duration < 0.25 { return } // ignore extremely short noises
        let segmentText = cleanTranscription(lastSegment.substring)
        guard !segmentText.isEmpty else { return }
        // Avoid re-adding if it already appears at end
        if !accumulatedText.hasSuffix(segmentText) && !currentSessionText.hasSuffix(segmentText) {
            appendToAccumulation(segmentText)
            // Do not overwrite lastFinalSegment here; partials are tentative
            logger.info("✏️ Partial segment locked-in: \(segmentText)")
        }
    }

    // MARK: - Diagnostics
    func snapshotDiagnostics(reason: String = "manual") {
        logger.info("🧪 Diagnostics snapshot (")
        logger.info("🧪 reason=\(reason) isListening=\(self.isListening) hasPermission=\(self.hasPermission) recognizerActive=\(self.isCurrentlyRecognizing)")
        logger.info("🧪 currentSessionText='\(self.currentSessionText)' accumulated='\(String(self.accumulatedText.prefix(120)))' chars=\(self.accumulatedText.count)")
        logger.info("🧪 lastFinal='\(self.lastFinalSegment)' segments=\(self.speechSegments.count) processing=\(self.isProcessingText)")
    }
    
    // MARK: - Session Management (Continuous without silence detection)
    
    private func scheduleSessionRestart() {
        // Restart sessions every ~50 seconds to stay within iOS limits but maintain continuity
        sessionRestartTimer?.invalidate()
        sessionRestartTimer = Timer.scheduledTimer(withTimeInterval: maxSessionDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isListening == true {
                    self?.logger.info("🔄 Restarting session for continuous operation (no silence detection)")
                    self?.startListeningSession()
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
    
    // MARK: - Text Processing (Permissive for continuous transcription)
    
    private func cleanTranscription(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Minimal cleaning - keep most speech patterns for continuous transcription
        // Only remove excessive repetitive noise
        let excessiveNoise = ["um um", "uh uh", "hmm hmm", "ah ah"]
        var result = cleaned
        
        for phrase in excessiveNoise {
            result = result.replacingOccurrences(of: phrase, with: phrase.components(separatedBy: " ").first ?? "", options: .caseInsensitive)
        }
        
        // Clean up extra whitespace but preserve single spaces
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isValidSpeech(_ text: String, confidence: Float) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Very permissive validation for continuous transcription
        guard !cleanText.isEmpty else { return false }
        
        // Accept almost everything with minimal confidence threshold
        guard confidence >= speechConfidenceThreshold else { return false }
        
        // Only reject if entirely non-alphabetic (keep mixed content)
        let letterCount = cleanText.filter { $0.isLetter }.count
        return letterCount > 0 || cleanText.count >= 3 // Allow short words or any text with letters
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