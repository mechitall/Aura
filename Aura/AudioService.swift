//
//  AudioService.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation
import AVFoundation
import Speech
import Combine
import os.log

class AudioService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "AudioService")
    
    // MARK: - Speech Recognition Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Audio Properties
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode!
    private var audioFormat: AVAudioFormat!
    private var audioData = Data()
    private var isRecording = false
    
    // MARK: - Publishers
    @Published var recordingLevel: Float = 0.0
    @Published var hasPermission = false
    @Published var recognizedText = ""
    @Published var isRecognizing = false
    
    // Callback for audio data chunks
    var onAudioDataReceived: ((Data) -> Void)?
    
    // MARK: - Configuration
    private let sampleRate: Double = 16000 // Whisper prefers 16kHz
    private let channelCount: UInt32 = 1   // Mono
    private let bitDepth: UInt32 = 16      // 16-bit
    
    // Callback for transcription completion
    var onTranscriptionComplete: ((String) -> Void)?
    
    // MARK: - Configuration
    private let silenceTimeout: TimeInterval = 3.0
    private var silenceTimer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
        setupSpeechRecognizer()
        checkPermissions()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Speech Recognition Setup
    private func setupSpeechRecognizer() {
        // Try to use the user's preferred language, fallback to English
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        logger.info("✅ Speech recognizer initialized for locale: \(self.speechRecognizer?.locale.identifier ?? "unknown")")
    }
    
    // MARK: - Permission Handling
    private func checkPermissions() {
        // Check speech recognition permission first
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
        let permission = AVAudioSession.sharedInstance().recordPermission
        logger.info("📋 Current microphone permission status: \(String(describing: permission))")
        
        switch permission {
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
            logger.info("❓ Microphone permission undetermined, requesting...")
            requestMicrophonePermission()
        @unknown default:
            logger.warning("⚠️ Unknown microphone permission status")
            requestMicrophonePermission()
        }
    }
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.logger.info("✅ Microphone permission granted by user")
                    self?.hasPermission = true
                } else {
                    self?.logger.error("❌ Microphone permission denied by user")
                    self?.hasPermission = false
                }
            }
        }
    }
    
    // Public method to re-check permissions
    func recheckPermission() {
        checkPermissions()
    }
    
    var isAvailable: Bool {
        return speechRecognizer?.isAvailable ?? false
    }
    
    // MARK: - Speech Recognition Control
    func startRecording() throws {
        guard hasPermission else {
            throw AudioError.permissionDenied
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw AudioError.recognizerUnavailable
        }
        
        guard !isRecording else {
            return
        }
        
        // Cancel any existing recognition task
        _ = stopRecording()
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw AudioError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap to capture audio for both recognition and level monitoring
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
            self.isRecording = true
            self.isRecognizing = true
            self.recognizedText = ""
        }
        
        logger.info("🎤 Speech recognition started")
        startSilenceTimer()
    }
    
    func stopRecording() -> Data {
        // Stop silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Finish recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.isRecognizing = false
            self.recordingLevel = 0.0
        }
        
        logger.info("🛑 Speech recognition stopped")
        return Data() // No longer returning audio data since we're doing on-device recognition
    }
    
    // MARK: - Audio Processing
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Handle different audio formats from the input node
        var samples: [Int16] = []
        var data = Data()
        
        if let int16Data = buffer.int16ChannelData {
            // Already Int16 format
            let channelDataValue = int16Data.pointee
            let channelDataValueArray = stride(
                from: 0,
                to: Int(buffer.frameLength),
                by: buffer.stride
            ).map { channelDataValue[$0] }
            
            samples = channelDataValueArray
            data = channelDataValueArray.withUnsafeBufferPointer { bufferPointer in
                return Data(buffer: bufferPointer)
            }
        } else if let floatData = buffer.floatChannelData {
            // Convert from Float32 to Int16
            let channelDataValue = floatData.pointee
            let channelDataValueArray = stride(
                from: 0,
                to: Int(buffer.frameLength),
                by: buffer.stride
            ).map { channelDataValue[$0] }
            
            // Convert Float32 (-1.0 to 1.0) to Int16 (-32768 to 32767)
            samples = channelDataValueArray.map { sample in
                let clampedSample = max(-1.0, min(1.0, sample))
                return Int16(clampedSample * 32767.0)
            }
            
            data = samples.withUnsafeBufferPointer { bufferPointer in
                return Data(buffer: bufferPointer)
            }
        } else {
            print("Unsupported audio format")
            return
        }
        
        // Append to main audio data
        audioData.append(data)
        
        // Calculate recording level for UI feedback
        let level = calculateLevel(from: samples)
        DispatchQueue.main.async {
            self.recordingLevel = level
        }
        
        // Notify with audio chunk if needed
        onAudioDataReceived?(data)
    }
    
    private func calculateLevel(from samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sum = samples.reduce(0) { result, sample in
            result + abs(Int32(sample))
        }
        
        let average = Float(sum) / Float(samples.count)
        let normalizedLevel = min(average / 32767.0, 1.0) // Normalize to 0-1
        
        return normalizedLevel
    }
    
    // MARK: - Audio Format Conversion
    func convertToWAV(pcmData: Data) -> Data {
        let sampleRate = UInt32(self.sampleRate)
        let channels = UInt16(channelCount)
        let bitsPerSample = UInt16(bitDepth)
        
        let frameLength = pcmData.count
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let dataSize = UInt32(frameLength)
        let fileSize = dataSize + 36
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        var fileSizeLE = fileSize.littleEndian
        wavData.append(Data(bytes: &fileSizeLE, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)
        
        // Format chunk
        wavData.append("fmt ".data(using: .ascii)!)
        var fmtSize: UInt32 = 16
        var fmtSizeLE = fmtSize.littleEndian
        wavData.append(Data(bytes: &fmtSizeLE, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        var audioFormatLE = audioFormat.littleEndian
        wavData.append(Data(bytes: &audioFormatLE, count: 2))
        var channelsLE = channels.littleEndian
        wavData.append(Data(bytes: &channelsLE, count: 2))
        var sampleRateLE = sampleRate.littleEndian
        wavData.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE = byteRate.littleEndian
        wavData.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE = blockAlign.littleEndian
        wavData.append(Data(bytes: &blockAlignLE, count: 2))
        var bitsPerSampleLE = bitsPerSample.littleEndian
        wavData.append(Data(bytes: &bitsPerSampleLE, count: 2))
        
        // Data chunk
        wavData.append("data".data(using: .ascii)!)
        var dataSizeLE = dataSize.littleEndian
        wavData.append(Data(bytes: &dataSizeLE, count: 4))
        wavData.append(pcmData)
        
        return wavData
    }
    
    // MARK: - Speech Recognition Helpers
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            logger.error("Speech recognition error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isRecognizing = false
            }
            return
        }
        
        guard let result = result else { return }
        
        let transcription = result.bestTranscription.formattedString
        
        DispatchQueue.main.async {
            self.recognizedText = transcription
            
            if result.isFinal {
                self.isRecognizing = false
                self.logger.info("✅ Final transcription: \(transcription)")
                // Reset silence timer since we got a final result
                self.resetSilenceTimer()
            } else {
                // Reset silence timer on partial results to prevent premature stopping
                self.resetSilenceTimer()
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
        DispatchQueue.main.async {
            self.recordingLevel = level
        }
    }
    
    private func calculateAudioLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let squaredSamples = samples.map { $0 * $0 }
        let averagePower = squaredSamples.reduce(0, +) / Float(samples.count)
        
        if averagePower > 0 {
            let decibels = 10 * log10(averagePower)
            // Normalize to 0.0-1.0 range (assuming -60dB to 0dB range)
            let normalizedLevel = max(0, (decibels + 60) / 60)
            return normalizedLevel
        }
        
        return 0.0
    }
    
    // MARK: - Silence Detection
    private func startSilenceTimer() {
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.handleSilenceTimeout()
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        startSilenceTimer()
    }
    
    private func handleSilenceTimeout() {
        logger.info("🔇 Silence detected, stopping recognition")
        _ = stopRecording()
    }
}

// MARK: - Error Handling
enum AudioError: Error, LocalizedError {
    case permissionDenied
    case formatError
    case engineError(Error)
    case recognizerUnavailable
    case requestCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission denied"
        case .formatError:
            return "Audio format configuration error"
        case .engineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        }
    }
}