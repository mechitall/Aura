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
    @Published var livePartial: String = "" // live partial transcription (currentSessionText)
    @Published var lastSentUserAccumulation: String = "" // EXACT text block most recently sent to AI
    @Published var debugMode: Bool = true // Enable debug utilities (can be toggled off for production)
    
    // MARK: - Theta Edge Analysis Properties
    @Published var lastAnalysis: String = ""
    @Published var isAnalyzing: Bool = false
    @Published var analysisHistory: [ThetaEdgeAnalysisService.AnalysisResult] = []
    
    // MARK: - Services
    private let apiService = ThetaAPIService()
    private let continuousSpeechService = ContinuousSpeechService()
    private let emotionalAnalysisService = EmotionalAnalysisService()
    private let thetaEdgeAnalysisService = ThetaEdgeAnalysisService()
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var didAutoDebugPrompt = false // ensure we only auto-fire a debug test prompt once
    private var emotionalAnalysisTimer: Timer?
    
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

        // Automatically fire a single test prompt shortly after launch in debug mode so we can
        // validate network path & observe logs without UI interaction (useful in CI / automation).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.debugMode && !self.didAutoDebugPrompt {
                self.logger.info("🧪 Auto-debug: dispatching initial test prompt for connectivity check")
                self.didAutoDebugPrompt = true
                self.sendTestPrompt()
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

        // Bind live partial (current session text)
        continuousSpeechService.$currentSessionText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.livePartial = text
            }
            .store(in: &cancellables)
        
        // Bind countdown timer
        continuousSpeechService.$timeUntilNextSend
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timeLeft in
                self?.timeUntilNextSend = timeLeft
            }
            .store(in: &cancellables)
        
        // Bind emotional analysis
        emotionalAnalysisService.$analysis
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analysis in
                if let analysis = analysis {
                    self?.lastAnalysis = "\(analysis.emoji) \(analysis.emotion)"
                }
            }
            .store(in: &cancellables)
        
        // Setup callback for accumulated text processing
        continuousSpeechService.onTextAccumulated = { [weak self] accumulatedText in
            Task { @MainActor in
                await self?.processAccumulatedText(accumulatedText)
            }
        }
        
        // MARK: - Theta Edge Analysis Service Bindings
        
        // Bind analysis service properties
        thetaEdgeAnalysisService.$lastAnalysis
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analysis in
                self?.lastAnalysis = analysis
            }
            .store(in: &cancellables)
        
        thetaEdgeAnalysisService.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analyzing in
                self?.isAnalyzing = analyzing
            }
            .store(in: &cancellables)
        
        thetaEdgeAnalysisService.$analysisHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (history: [ThetaEdgeAnalysisService.AnalysisResult]) in
                self?.analysisHistory = history
            }
            .store(in: &cancellables)
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
        startEmotionalAnalysisTimer()
        errorMessage = nil
        logger.info("🔄 Started continuous speech recognition")
    }
    
    func stopContinuousListening() {
        guard isListening else { return }
        
        continuousSpeechService.stopContinuousListening()
        stopEmotionalAnalysisTimer()
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
        
        logger.info("👤 SENDING TO AI: Processing accumulated text (\(trimmedText.count) chars)")
        logger.info("📝 Full text: '\(trimmedText)'")
        
        // Send text to Theta Edge Analysis Service for emotional/contextual analysis
        // thetaEdgeAnalysisService.addTranscribedText(trimmedText)
        
        // Add user message with accumulated text
        await MainActor.run {
            self.appState = .processing
            // Record exactly what we're sending for UI + diagnostics before any mutation
            self.lastSentUserAccumulation = trimmedText
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
                
                // ✅ CONFIRM SUCCESSFUL PROCESSING - Now it's safe to clear accumulated text
                // Note: The continuous speech service manages its own text accumulation
                
                // Return to continuous listening state if still listening
                if self.isListening {
                    self.appState = .continuousListening
                } else {
                    self.appState = .idle
                }
                
                self.logger.info("✅ AI response added successfully, conversation has \(self.messages.count) messages")
            }
            
        } catch ThetaAPIService.APIError.rateLimited {
            logger.warning("⏱️ Rate limited - keeping accumulated text for retry")
            // Don't clear text on rate limit - we'll retry
            
            await MainActor.run {
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
            logger.error("❌ API ERROR - keeping accumulated text: \(error.localizedDescription)")
            
            // ❌ HANDLE PROCESSING ERROR - Keep accumulated text for potential retry
            await MainActor.run {
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

    // MARK: - Diagnostics
    func dumpDiagnostics() {
        logger.info("📊 ChatViewModel diagnostics: livePartial='\(self.livePartial)' accumulatedCount=\(self.accumulatedText.count) lastSentLen=\(self.lastSentUserAccumulation.count) messages=\(self.messages.count)")
    }

    // MARK: - Theta Edge Analysis Methods
    
    /// Manually trigger analysis of current pending text
    func triggerAnalysisNow() {
        thetaEdgeAnalysisService.analyzeNow()
        logger.info("🧠 Manual analysis triggered")
    }
    
    // MARK: - Emotional Analysis Timer
    
    private func startEmotionalAnalysisTimer() {
        stopEmotionalAnalysisTimer() // Ensure no duplicate timers
        emotionalAnalysisTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let textToAnalyze = self.accumulatedText
            if !textToAnalyze.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task {
                    await self.emotionalAnalysisService.analyzeText(textToAnalyze)
                }
            }
        }
        logger.info("✅ Started emotional analysis timer (30s interval)")
    }
    
    private func stopEmotionalAnalysisTimer() {
        emotionalAnalysisTimer?.invalidate()
        emotionalAnalysisTimer = nil
        logger.info("🛑 Stopped emotional analysis timer")
    }
    
    /// Clear pending analysis text
    func clearAnalysisText() {
        thetaEdgeAnalysisService.clearPendingText()
        logger.info("🗑️ Cleared pending analysis text")
    }
    
    /// Get the most recent analysis result
    var mostRecentAnalysis: ThetaEdgeAnalysisService.AnalysisResult? {
        return analysisHistory.last
    }

    // MARK: - Debug / Test Utilities
    func sendTestPrompt() {
        Task { @MainActor in
            let prompt = "Give me one concise, uplifting self-improvement insight and a reflective question."
            logger.info("🧪 DEBUG: Injecting test prompt -> '\(prompt)'")
            appState = .processing
            lastSentUserAccumulation = prompt
            let userMessage = ChatMessage(text: prompt, role: .user)
            messages.append(userMessage)
        }
        Task { await getAIResponse() }
    }
}