//
//  ChatViewModel.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation
import Combine
import SwiftUI
import AVFoundation
import os.log

@MainActor
class ChatViewModel: ObservableObject {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ChatViewModel")
    
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
    
    // MARK: - App State
    enum AppState: Equatable {
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
        
        // Monitor speech recognition permission
        audioService.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                self?.logger.debug("🎤 Speech recognition permission status: \(hasPermission)")
                // Clear any existing permission error when permission is granted
                if hasPermission, case .error(let errorText) = self?.appState, errorText.contains("permission") {
                    self?.appState = .idle
                }
            }
            .store(in: &cancellables)
        
        // Bind recognized text updates
        audioService.$recognizedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                // Show live transcription feedback in UI if needed
                self?.logger.debug("📝 Live transcription: \(text.prefix(50))...")
            }
            .store(in: &cancellables)
        
        // Monitor for recognition completion - when final text is available and recognition stops
        audioService.$isRecognizing
            .combineLatest(audioService.$recognizedText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isRecognizing, recognizedText) in
                // When recognition stops and we have text, process it
                if !isRecognizing && !recognizedText.isEmpty {
                    Task { @MainActor in
                        await self?.processTranscribedText(recognizedText)
                        // Clear the recognized text for next session
                        self?.audioService.recognizedText = ""
                    }
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
        
        // Check if speech recognition is available and permissions are granted
        guard audioService.hasPermission else {
            appState = .error("Speech recognition permission required. Please enable in Settings.")
            return
        }
        
        guard audioService.isAvailable else {
            appState = .error("Speech recognition is not available on this device.")
            return
        }
        
        do {
            try audioService.startRecording()
            isRecording = true
            appState = .listening
            errorMessage = nil
            
        } catch {
            handleError(error)
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        _ = audioService.stopRecording()
        isRecording = false
        appState = .processing
    }
    
    // MARK: - Text Processing (from On-Device Speech Recognition)
    private func processTranscribedText(_ transcribedText: String) async {
        let trimmedText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            await MainActor.run {
                self.appState = .idle
            }
            return
        }
        
        // Add user message with transcribed text
        await MainActor.run {
            let userMessage = ChatMessage(text: trimmedText, role: .user)
            self.messages.append(userMessage)
        }
        
        // Get AI response after brief delay to allow UI update
        do {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await getAIResponse()
        } catch {
            await MainActor.run {
                self.handleError(error)
            }
        }
    }
    
    private func getAIResponse() async {
        do {
            let aiResponse = try await apiService.generateAIInsight(messages: messages)
            
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
    
    // MARK: - Helper Methods
    func recheckPermissions() {
        audioService.recheckPermission()
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        let errorText: String
        
        if let apiError = error as? ThetaAPIService.APIError {
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