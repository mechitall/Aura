//
//  ChatViewModel.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var isRecording: Bool = false
    @Published var appState: AppState = .idle
    @Published var errorMessage: String?
    @Published var recordingLevel: Float = 0.0
    
    // MARK: - Services
    private let apiService = ThetaAPIService()
    private let audioService = AudioService()
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 4.0 // 4 seconds of silence
    
    // MARK: - App State
    enum AppState {
        case idle
        case listening
        case processing
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle:
                return "Tap to speak with Aura"
            case .listening:
                return "Listening..."
            case .processing:
                return "Aura is thinking..."
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        setupBindings()
        setupWelcomeMessage()
    }
    
    private func setupBindings() {
        // Bind audio service recording level to view model
        audioService.$recordingLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.recordingLevel = level
            }
            .store(in: &cancellables)
        
        // Monitor microphone permission
        audioService.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                if !hasPermission {
                    self?.appState = .error("Microphone permission required")
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            text: "Hello! I'm Aura, your AI life coach. I'm here to listen and help you process your thoughts and feelings. Tap the microphone to start our conversation.",
            role: .ai
        )
        messages.append(welcomeMessage)
    }
    
    // MARK: - Recording Control
    func startRecording() {
        guard !isRecording else { return }
        guard audioService.hasPermission else {
            appState = .error("Microphone permission required")
            return
        }
        
        do {
            try audioService.startRecording()
            isRecording = true
            appState = .listening
            errorMessage = nil
            
            // Start silence detection timer
            startSilenceTimer()
            
        } catch {
            handleError(error)
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        appState = .processing
        
        // Stop silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Get recorded audio data
        let audioData = audioService.stopRecording()
        
        // Process the audio
        Task {
            await processRecordedAudio(audioData)
        }
    }
    
    // MARK: - Audio Processing
    private func processRecordedAudio(_ audioData: Data) async {
        guard !audioData.isEmpty else {
            await MainActor.run {
                self.appState = .idle
            }
            return
        }
        
        do {
            // Convert PCM data to WAV format for Whisper API
            let wavData = audioService.convertToWAV(pcmData: audioData)
            
            // Transcribe audio to text
            let transcription = try await apiService.transcribe(audioData: wavData)
            
            // Add user message if transcription is not empty
            if !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    let userMessage = ChatMessage(text: transcription, role: .user)
                    self.messages.append(userMessage)
                }
                
                // Get AI response after brief delay to allow UI update
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await getAIResponse()
            } else {
                await MainActor.run {
                    self.appState = .idle
                }
            }
            
        } catch {
            await MainActor.run {
                self.handleError(error)
            }
        }
    }
    
    private func getAIResponse() async {
        do {
            let aiResponse = try await apiService.getAIInsight(history: messages)
            
            await MainActor.run {
                let aiMessage = ChatMessage(text: aiResponse, role: .ai)
                self.messages.append(aiMessage)
                self.appState = .idle
            }
            
        } catch {
            await MainActor.run {
                self.handleError(error)
            }
        }
    }
    
    // MARK: - Silence Detection
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceTimeout()
            }
        }
    }
    
    private func handleSilenceTimeout() {
        guard isRecording else { return }
        
        // Auto-stop recording after silence
        stopRecording()
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        let errorText: String
        
        if let apiError = error as? APIError {
            errorText = apiError.localizedDescription
        } else if let audioError = error as? AudioError {
            errorText = audioError.localizedDescription
        } else {
            errorText = error.localizedDescription
        }
        
        appState = .error(errorText)
        errorMessage = errorText
        
        // Reset to idle after showing error briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if case .error = self.appState {
                self.appState = .idle
                self.errorMessage = nil
            }
        }
    }
    
    // MARK: - Helper Methods
    func clearMessages() {
        messages.removeAll()
        setupWelcomeMessage()
    }
    
    var lastMessage: ChatMessage? {
        return messages.last
    }
    
    var conversationHistory: [ChatMessage] {
        return messages.filter { !$0.text.isEmpty }
    }
}