//
//  AudioService.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation
import AVFoundation
import Combine

class AudioService: NSObject, ObservableObject {
    
    // MARK: - Properties
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode!
    private var audioFormat: AVAudioFormat!
    private var audioData = Data()
    private var isRecording = false
    
    // MARK: - Publishers
    @Published var recordingLevel: Float = 0.0
    @Published var hasPermission = false
    
    // Callback for audio data chunks
    var onAudioDataReceived: ((Data) -> Void)?
    
    // MARK: - Configuration
    private let sampleRate: Double = 16000 // Whisper prefers 16kHz
    private let channelCount: UInt32 = 1   // Mono
    private let bitDepth: UInt32 = 16      // 16-bit
    
    override init() {
        super.init()
        setupAudioSession()
        checkMicrophonePermission()
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
    
    // MARK: - Permission Handling
    private func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            DispatchQueue.main.async {
                self.hasPermission = true
            }
        case .denied, .undetermined:
            requestMicrophonePermission()
        @unknown default:
            break
        }
    }
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
            }
        }
    }
    
    // MARK: - Recording Control
    func startRecording() throws {
        guard hasPermission else {
            throw AudioError.permissionDenied
        }
        
        guard !isRecording else {
            return
        }
        
        // Reset audio data
        audioData = Data()
        
        // Setup input node
        inputNode = audioEngine.inputNode
        
        // Create audio format for Whisper API (16kHz, mono, 16-bit)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
        
        guard let audioFormat = audioFormat else {
            throw AudioError.formatError
        }
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
        } catch {
            throw AudioError.engineError(error)
        }
    }
    
    func stopRecording() -> Data {
        guard isRecording else {
            return Data()
        }
        
        // Remove tap and stop engine
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        
        DispatchQueue.main.async {
            self.recordingLevel = 0.0
        }
        
        print("Recording stopped, audio data size: \(audioData.count) bytes")
        return audioData
    }
    
    // MARK: - Audio Processing
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        // Convert to Data
        let data = channelDataValueArray.withUnsafeBufferPointer { bufferPointer in
            return Data(buffer: bufferPointer)
        }
        
        // Append to main audio data
        audioData.append(data)
        
        // Calculate recording level for UI feedback
        let level = calculateLevel(from: channelDataValueArray)
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
        wavData.append(Data(bytes: &fileSize.littleEndian, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)
        
        // Format chunk
        wavData.append("fmt ".data(using: .ascii)!)
        var fmtSize: UInt32 = 16
        wavData.append(Data(bytes: &fmtSize.littleEndian, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        wavData.append(Data(bytes: &audioFormat.littleEndian, count: 2))
        wavData.append(Data(bytes: &channels.littleEndian, count: 2))
        wavData.append(Data(bytes: &sampleRate.littleEndian, count: 4))
        wavData.append(Data(bytes: &byteRate.littleEndian, count: 4))
        wavData.append(Data(bytes: &blockAlign.littleEndian, count: 2))
        wavData.append(Data(bytes: &bitsPerSample.littleEndian, count: 2))
        
        // Data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(Data(bytes: &dataSize.littleEndian, count: 4))
        wavData.append(pcmData)
        
        return wavData
    }
}

// MARK: - Error Handling
enum AudioError: Error, LocalizedError {
    case permissionDenied
    case formatError
    case engineError(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .formatError:
            return "Audio format configuration error"
        case .engineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        }
    }
}