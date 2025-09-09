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
    @Published var isListening: Bool = false
    @Published var appState: AppState = .idle
    @Published var errorMessage: String?
    @Published var recordingLevel: Float = 0.0
    @Published var accumulatedText: String = ""
    @Published var timeUntilNextSend: TimeInterval = 0
    @Published var manualSpeechInput: String = ""
    
    // MARK: - Services
    private let apiService = ThetaAPIService()
    private let continuousSpeechService = ContinuousSpeechService()
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - App State
    enum AppState: Equatable {
        case idle
        case continuousListening
        case processing
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle:
                return "Start continuous listening"
            case .continuousListening:
                return "Aura is listening continuously..."
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
        
        // Auto-start continuous listening after brief delay if permissions are available
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.continuousSpeechService.hasPermission && !self.isListening {
                self.logger.info("🎯 Auto-starting continuous listening from ChatViewModel")
                self.startContinuousListening()
            }
        }
    }
    
    private func setupBindings() {
        // Bind continuous speech service properties to view model
        continuousSpeechService.$recordingLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.recordingLevel = level
            }
            .store(in: &cancellables)
        
        // Monitor speech recognition permission
        continuousSpeechService.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                self?.logger.debug("🎤 Speech recognition permission status: \(hasPermission)")
                if hasPermission, case .error(let errorText) = self?.appState, errorText.contains("permission") {
                    self?.appState = .idle
                }
            }
            .store(in: &cancellables)
        
        // Bind listening state
        continuousSpeechService.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isListening in
                self?.isListening = isListening
                if isListening {
                    self?.appState = .continuousListening
                } else if self?.appState == .continuousListening {
                    self?.appState = .idle
                }
            }
            .store(in: &cancellables)
        
        // Bind accumulated text
        continuousSpeechService.$accumulatedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.accumulatedText = text
            }
            .store(in: &cancellables)
        
        // Bind countdown timer
        continuousSpeechService.$timeUntilNextSend
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timeLeft in
                self?.timeUntilNextSend = timeLeft
            }
            .store(in: &cancellables)
        
        // Setup callback for accumulated text processing
        continuousSpeechService.onTextAccumulated = { [weak self] accumulatedText in
            Task { @MainActor in
                await self?.processAccumulatedText(accumulatedText)
            }
        }
    }
    
    private func setupWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            text: "Hello! I'm Aura, your AI life coach. I'm here to listen continuously and help you process your thoughts and feelings. I'll start listening automatically once permissions are granted. Just speak naturally - I'll respond every minute or when you pause.",
            role: .ai
        )
        messages.append(welcomeMessage)
    }
    
    // MARK: - Continuous Listening Control
    func startContinuousListening() {
        guard !isListening else { return }
        
        // Check if speech recognition is available and permissions are granted
        guard continuousSpeechService.hasPermission else {
            appState = .error("Speech recognition permission required. Please enable in Settings.")
            return
        }
        
        continuousSpeechService.startContinuousListening()
        errorMessage = nil
        logger.info("🔄 Started continuous speech recognition")
    }
    
    func stopContinuousListening() {
        guard isListening else { return }
        
        continuousSpeechService.stopContinuousListening()
        logger.info("🛑 Stopped continuous speech recognition")
    }
    
    func toggleContinuousListening() {
        if isListening {
            stopContinuousListening()
        } else {
            startContinuousListening()
        }
    }
    
    // MARK: - Text Processing (from Continuous Speech Recognition)
    private func processAccumulatedText(_ accumulatedText: String) async {
        let trimmedText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            logger.info("ℹ️ No accumulated text to process")
            return
        }
        
        // Check if text is meaningful enough (at least 5 characters)
        guard trimmedText.count >= 5 else {
            logger.info("ℹ️ Accumulated text too short, skipping: \(trimmedText)")
            return
        }
        
        logger.info("� 👤 SENDING TO AI: Processing accumulated text (\(trimmedText.count) chars)")
        logger.info("📝 Full text: '\(trimmedText)'")
        
        // Add user message with accumulated text
        await MainActor.run {
            self.appState = .processing
            let userMessage = ChatMessage(text: trimmedText, role: .user)
            self.messages.append(userMessage)
            self.logger.info("✨ User message added to chat - total messages: \(self.messages.count)")
        }
        
        // Get AI response with rate limiting check
        logger.info("🤖 Requesting AI response from Theta...")
        await getAIResponse()
    }
    
    private func getAIResponse() async {
        do {
            logger.info("🌐 Making API request to ThetaEdgeCloud...")
            let aiResponse = try await apiService.generateAIInsight(messages: messages)
            
            await MainActor.run {
                self.logger.info("✨ 🤖 AI RESPONSE RECEIVED: '\(String(aiResponse.prefix(100)))...'") 
                let aiMessage = ChatMessage(text: aiResponse, role: .ai)
                self.messages.append(aiMessage)
                
                // Return to continuous listening state if still listening
                if self.isListening {
                    self.appState = .continuousListening
                } else {
                    self.appState = .idle
                }
                
                self.logger.info("✅ AI response added successfully, conversation has \(self.messages.count) messages")
            }
            
        } catch ThetaAPIService.APIError.rateLimited {
            await MainActor.run {
                self.logger.warning("⏱️ Rate limited - will retry later")
                // Don't show error to user, just continue listening
                if self.isListening {
                    self.appState = .continuousListening
                } else {
                    self.appState = .idle
                }
            }
            
            // Retry after cooldown period
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await getAIResponse()
            
        } catch {
            await MainActor.run {
                self.logger.error("❌ API ERROR: \(error.localizedDescription)")
                self.handleError(error)
            }
        }
    }
    
    // MARK: - Helper Methods
    func recheckPermissions() {
        continuousSpeechService.recheckPermissions()
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        let errorText: String
        var shouldShowError = true
        
        if let apiError = error as? ThetaAPIService.APIError {
            switch apiError {
            case .rateLimited:
                // Don't show rate limit errors to user
                errorText = "API rate limited"
                shouldShowError = false
                logger.info("📊 API rate limited - continuing silently")
            case .noResponse:
                errorText = "No response from AI service"
            case .networkError(let underlyingError):
                errorText = "Network error: \(underlyingError.localizedDescription)"
            default:
                errorText = "AI service error: \(apiError.localizedDescription)"
            }
        } else if let audioError = error as? AudioError {
            errorText = "Audio error: \(audioError.localizedDescription)"
        } else {
            errorText = error.localizedDescription
        }
        
        logger.error("❌ Error handled: \(errorText)")
        
        if shouldShowError {
            appState = .error(errorText)
            errorMessage = errorText
            
            // Reset to appropriate state after showing error
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if case .error = self.appState {
                    if self.isListening {
                        self.appState = .continuousListening
                    } else {
                        self.appState = .idle
                    }
                    self.errorMessage = nil
                }
            }
        } else {
            // For non-user-facing errors, just return to listening state
            if isListening {
                appState = .continuousListening
            } else {
                appState = .idle
            }
        }
    }
    
    // MARK: - Helper Methods
    func clearMessages() {
        messages.removeAll()
        apiService.clearContext() // Clear API context as well
        setupWelcomeMessage()
        logger.info("🧠 Messages and context cleared")
    }
    
    // Send current accumulated speech to AI immediately
    func sendCurrentSpeechToAI() {
        let currentText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !currentText.isEmpty else {
            logger.warning("⚠️ No accumulated text to send")
            return
        }
        
        logger.info("📤 Manual send triggered - processing \(currentText.count) characters")
        
        Task {
            await processAccumulatedText(currentText)
            
            // Clear the accumulated text after sending
            await MainActor.run {
                self.continuousSpeechService.clearAccumulatedText()
            }
        }
    }
    
    // Add manual speech input to accumulated text (for simulator testing)
    func addManualSpeech() {
        let inputText = manualSpeechInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputText.isEmpty else { return }
        
        logger.info("⌨️ Adding manual speech input: \(inputText)")
        
        // Add to accumulated text (with space if there's existing text)
        if !accumulatedText.isEmpty {
            accumulatedText += " "
        }
        accumulatedText += inputText
        
        // Also update the service's accumulated text
        continuousSpeechService.setTestAccumulatedText(accumulatedText)
        
        // Clear the input field
        manualSpeechInput = ""
    }
    
    func getApiContextSize() -> Int {
        return apiService.getContextSize()
    }
    
    var timeUntilNextApiRequest: TimeInterval {
        return apiService.timeUntilNextRequest
    }
    
    var lastMessage: ChatMessage? {
        return messages.last
    }
    
    var conversationHistory: [ChatMessage] {
        return messages.filter { !$0.text.isEmpty }
    }
}