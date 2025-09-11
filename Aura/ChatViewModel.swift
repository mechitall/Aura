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
import NaturalLanguage

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
    @Published var lastAnalysis: EmotionalAnalysis?
    @Published var isAnalyzing: Bool = false
    @Published var emotionalTrend: [EmotionalPoint] = [] // history for emotional trend visualization
    // Daily pattern analysis
    @Published var dailyPatterns: [DailyPattern] = []
    @Published var isPatternAnalyzing: Bool = false
    @Published var patternAnalysisError: String? = nil
    @Published var lastPatternAnalysisAt: Date? = nil
    private var lastPatternTranscriptHash: Int? = nil
    // Single active speech recognition language
    @Published var primaryLanguage: SpeechLanguage = .english {
        didSet {
            if oldValue != self.primaryLanguage {
                self.logger.info("🌐 Active language changed → \(self.primaryLanguage.rawValue)")
                self.continuousSpeechService.setLanguage(self.primaryLanguage)
                self.persistLanguageSelection()
            }
        }
    }
    @Published var autoDetectEnabled: Bool = false {
        didSet { persistLanguageSelection() }
    }

    struct DailyPattern: Identifiable, Hashable {
        let id = UUID()
        let title: String      // Short label e.g. "Repeated Stress Theme"
        let summary: String    // One-line summary
        let emoji: String
        let evidenceSnippet: String // Short snippet from transcript
    }
    
    // MARK: - Services
    private let apiService = ThetaAPIService()
    private let continuousSpeechService = ContinuousSpeechService()
    private let emotionalAnalysisService = EmotionalAnalysisService()
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var didAutoDebugPrompt = false // ensure we only auto-fire a debug test prompt once
    private var emotionalAnalysisTimer: Timer?
    private let emotionalAnalysisInterval: TimeInterval = 30.0
    @Published var lastEmotionalAnalysisAt: Date? = nil
    @Published var timeUntilNextEmotionalAnalysis: TimeInterval = 0
    private var emotionalCountdownTimer: Timer?
    // Auto language detection state
    private var lastAutoDetectAt: Date? = nil
    private var recentUtteranceBuffer: [String] = [] // maintain last few utterances for aggregated detection
    private let autoDetectMinChars: Int = 25
    private let autoDetectCooldown: TimeInterval = 90 // seconds between automatic switches
    private let autoDetectConfidenceThreshold: Double = 0.5 // lowered to make detection more responsive
    
    struct EmotionalPoint: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let emotion: String
        let emoji: String
        let score: Double // -1 (negative) ... +1 (positive)
    }
    
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
    // Default emotional state so UI always shows something
    self.lastAnalysis = EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
    // Load persisted multi-language selection if present
    migrateAndLoadLanguages()
        setupBindings()
        setupWelcomeMessage()
    // Start emotional analysis loop immediately so it runs every 30s without user interaction
    startEmotionalAnalysisTimer()
        
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

    // MARK: - Full Transcript Accessor
    /// Returns the full speech recognition context since app launch (accumulated + live partial)
    private func fullTranscript() -> String {
        let parts = [accumulatedText, livePartial]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    // MARK: - Daily Pattern Analysis
    /// Analyze the entire transcript for behavioral / emotional patterns.
    func analyzeDailyPatterns() {
        let transcript = fullTranscript()
        guard !transcript.isEmpty else {
            patternAnalysisError = "No transcript available yet"
            return
        }
        guard !isPatternAnalyzing else { return }
        // Prevent immediate redundant re-run on identical transcript (within 30s window)
        let currentHash = transcript.hashValue
        if let lastHash = lastPatternTranscriptHash, lastHash == currentHash, let lastTime = lastPatternAnalysisAt, Date().timeIntervalSince(lastTime) < 30 {
            patternAnalysisError = "Already analyzed (no new speech yet). Speak more before re-running."
            return
        }
        isPatternAnalyzing = true
        patternAnalysisError = nil
        logger.info("🧩 Starting daily pattern analysis (len=\(transcript.count) chars)")
        Task { @MainActor in
            do {
                let patterns = try await self.generatePatternAnalysis(transcript: transcript)
                self.dailyPatterns = patterns
                logger.info("✅ Daily pattern analysis complete: found \(patterns.count) patterns")
                self.lastPatternAnalysisAt = Date()
                self.lastPatternTranscriptHash = currentHash
            } catch {
                self.patternAnalysisError = error.localizedDescription
                logger.error("❌ Daily pattern analysis failed: \(error.localizedDescription)")
            }
            self.isPatternAnalyzing = false
        }
    }

    /// Uses Theta EdgeCloud via existing API service to extract structured patterns.
    private func generatePatternAnalysis(transcript: String) async throws -> [DailyPattern] {
    // Cap transcript length to avoid server/context limits (retain last N chars for recency bias)
    let maxChars = 12_000
    let trimmed = transcript.count > maxChars ? String(transcript.suffix(maxChars)) : transcript

    let systemPrompt = """
    You are an elite AI life coach specialized in longitudinal pattern mining across a user's spoken diary for a single day.
    Return ONLY structured JSON when asked (no pre/post text) if the user explicitly requests JSON output.
    """.trimmingCharacters(in: .whitespacesAndNewlines)

        let userPrompt = """
Full-day transcript (chronological):

\(trimmed)

Task: Identify up to 6 meaningful behavioral or emotional patterns. Focus on: repetitions, loops, triggers, coping strategies, emotional spikes, avoidance, growth signals.
Return ONLY compact JSON: {
    "patterns": [ {
        "title": short pattern name,
        "summary": one-line explanation under 120 chars,
        "emoji": a single relevant emoji,
        "evidence": one short supporting snippet (<=140 chars)
    } ]
}
Do not include any prose outside of the JSON object.
"""

    let raw = try await apiService.oneOffAnalysis(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.55, maxTokens: 700)
    let patterns = parsePatternJSON(from: raw)
    return patterns
    }

    private func parsePatternJSON(from text: String) -> [DailyPattern] {
        // Find JSON block
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return heuristicExtractPatterns(text) }
        let jsonSlice = text[start...end]
        let jsonString = String(jsonSlice)
        struct Root: Decodable {
            struct P: Decodable {
                let title: String
                let summary: String
                let emoji: String?
                let evidence: String?
            }
            let patterns: [P]
        }
        if let data = jsonString.data(using: .utf8) {
            if let root = try? JSONDecoder().decode(Root.self, from: data) {
                return root.patterns.map { p in
                    DailyPattern(title: p.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 summary: p.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                 emoji: (p.emoji ?? "🧠"),
                                 evidenceSnippet: (p.evidence ?? "") )
                }
            }
        }
        return heuristicExtractPatterns(text)
    }

    private func heuristicExtractPatterns(_ text: String) -> [DailyPattern] {
        // Fallback: split into lines and grab bullet/numbered lines
        var patterns: [DailyPattern] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 8 else { continue }
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                let cmp = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
                let title = String(cmp.prefix(40))
                patterns.append(DailyPattern(title: title, summary: cmp, emoji: "🧠", evidenceSnippet: ""))
            }
            if patterns.count >= 6 { break }
        }
        if patterns.isEmpty {
            patterns.append(DailyPattern(title: "No clear patterns", summary: "Could not parse structured patterns from analysis output.", emoji: "ℹ️", evidenceSnippet: ""))
        }
        return patterns
    }
    
    private func setupBindings() {
        // Bind active language from service (mirror changes initiated elsewhere)
        continuousSpeechService.$activeLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lang in
                guard let self = self else { return }
                if self.primaryLanguage != lang {
                    self.primaryLanguage = lang
                }
            }
            .store(in: &cancellables)
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
                guard let self = self else { return }
                self.lastAnalysis = analysis
                if let analysis = analysis {
                    let point = EmotionalPoint(date: Date(), emotion: analysis.emotion, emoji: analysis.emoji, score: self.score(for: analysis.emotion))
                    self.emotionalTrend.append(point)
                    if self.emotionalTrend.count > 120 { // keep roughly last hour at 30s cadence + manual
                        self.emotionalTrend.removeFirst(self.emotionalTrend.count - 120)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Setup callback for accumulated text processing
        continuousSpeechService.onTextAccumulated = { [weak self] accumulatedText in
            Task { @MainActor in
                await self?.processAccumulatedText(accumulatedText)
            }
        }
        // Per-utterance callback for language detection
        continuousSpeechService.onFinalUserUtterance = { [weak self] utterance in
            Task { @MainActor in
                self?.handleFinalUtterance(utterance)
            }
        }
    }

    // MARK: - Auto Language Detection
    private func handleFinalUtterance(_ text: String) {
        guard autoDetectEnabled else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        recentUtteranceBuffer.append(cleaned)
        if recentUtteranceBuffer.count > 6 { recentUtteranceBuffer.removeFirst() }
        let aggregate = recentUtteranceBuffer.joined(separator: " ")
        maybeAutoDetectLanguage(on: aggregate)
    }

    private func maybeAutoDetectLanguage(on aggregate: String) {
        // Size gate
        guard aggregate.count >= self.autoDetectMinChars else {
            logger.debug("🌐 AutoDetect skip: not enough chars (\(aggregate.count)/\(self.autoDetectMinChars))")
            return
        }
        // Cooldown gate
        if let last = self.lastAutoDetectAt {
            let since = Date().timeIntervalSince(last)
            if since < self.autoDetectCooldown {
                logger.debug("🌐 AutoDetect skip: cooldown (\(Int(since))s < \(Int(self.autoDetectCooldown))s)")
                return
            }
        }

        // Heuristic script / token checks first (fast path)
        if let (heuristicLang, hConf) = heuristicLanguage(for: aggregate) {
            if heuristicLang != self.primaryLanguage {
                self.logger.info("🌐 Heuristic switch → \(heuristicLang.rawValue) (confidence=\(hConf))")
                self.primaryLanguage = heuristicLang
                self.lastAutoDetectAt = Date()
                return
            } else {
                logger.debug("🌐 Heuristic detected current primary (\(heuristicLang.rawValue)); no switch")
            }
        }

        // Use built-in language recognizer (slower path)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(aggregate)
        guard let hypothesis = recognizer.dominantLanguage else {
            logger.debug("🌐 AutoDetect skip: no dominantLanguage")
            return
        }
        let confidences = recognizer.languageHypotheses(withMaximum: 3)
        let confidence = confidences[hypothesis] ?? 0
        logger.debug("🌐 AutoDetect hypotheses: \(confidences) chosen=\(hypothesis.rawValue) conf=\(confidence)")
        // Map to supported SpeechLanguage
        let mapped: SpeechLanguage? = {
            switch hypothesis {
            case .english: return .english
            case .german: return .german
            case .russian: return .russian
            default: return nil
            }
        }()
        guard let candidate = mapped else { return }
        guard candidate != self.primaryLanguage else {
            logger.debug("🌐 AutoDetect skip: candidate == current (\(candidate.rawValue))")
            return
        }
        guard confidence >= self.autoDetectConfidenceThreshold else {
            logger.debug("🌐 AutoDetect skip: confidence \(confidence) < threshold \(self.autoDetectConfidenceThreshold)")
            return
        }
        self.logger.info("🌐 Auto-detected language switch to \(candidate.rawValue) (confidence=\(confidence))")
        self.primaryLanguage = candidate
        self.lastAutoDetectAt = Date()
    }

    private func heuristicLanguage(for text: String) -> (SpeechLanguage, Double)? {
        // Detect Cyrillic quickly
        if text.range(of: "[\\u0400-\\u04FF]", options: .regularExpression) != nil {
            return (.russian, 0.9)
        }
        // German diacritics or common short words pattern; keep false positives low
        let hasDiacritic = text.range(of: "[äöüÄÖÜß]", options: .regularExpression) != nil
        let lower = text.lowercased()
        let germanTokens = [" und ", " ich ", " nicht ", " der ", " die ", " das "]
        let germanHits = germanTokens.filter { lower.contains($0) }.count
        if hasDiacritic || germanHits >= 2 {
            return (.german, hasDiacritic ? 0.85 : 0.7)
        }
        return nil
    }

    // MARK: - Language Persistence
    private let primaryLanguageDefaultsKey = "Aura.PrimaryLanguage"
    private let legacySingleLanguageKey = "Aura.SelectedLanguage"
    private let autoDetectDefaultsKey = "Aura.AutoDetectLanguages"
    private func persistLanguageSelection() {
        UserDefaults.standard.set(primaryLanguage.rawValue, forKey: primaryLanguageDefaultsKey)
    UserDefaults.standard.set(autoDetectEnabled, forKey: autoDetectDefaultsKey)
    }
    private func migrateAndLoadLanguages() {
        let defaults = UserDefaults.standard
        if let primaryRaw = defaults.string(forKey: primaryLanguageDefaultsKey), let primary = SpeechLanguage(rawValue: primaryRaw) {
            primaryLanguage = primary
        } else {
            // Fallback to legacy single-language key or default english
            if let legacy = defaults.string(forKey: legacySingleLanguageKey), let legacyLang = SpeechLanguage(rawValue: legacy) {
                primaryLanguage = legacyLang
            } else {
                primaryLanguage = .english
            }
        }
    autoDetectEnabled = defaults.bool(forKey: autoDetectDefaultsKey)
        continuousSpeechService.setLanguage(primaryLanguage)
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
        if emotionalAnalysisTimer == nil { // avoid resetting schedule if already running from init
            startEmotionalAnalysisTimer()
        }
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
        logger.info("🧠 Manual analysis triggered")
        // Build snapshot combining accumulated + live partial (recent) text
        let textToAnalyze = emotionalAnalysisSnapshot()
        guard !textToAnalyze.isEmpty else {
            logger.info("ℹ️ No text available for manual emotional analysis")
            self.appState = .error("No text to analyze")
            self.errorMessage = "No text to analyze"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if case .error = self.appState {
                    self.appState = self.isListening ? .continuousListening : .idle
                    self.errorMessage = nil
                }
            }
            return
        }

        logger.info("🧵 Emotional snapshot length: \(textToAnalyze.count) chars")
        // Avoid overlapping analyses
        guard !isAnalyzing else {
            logger.info("⏳ Ignoring manual trigger; analysis already running")
            return
        }
        isAnalyzing = true
        Task { @MainActor in
            await self.emotionalAnalysisService.analyzeText(textToAnalyze)
            self.isAnalyzing = false
            self.lastEmotionalAnalysisAt = Date()
            // Restart timer so next automatic run is interval from this manual override
            self.restartEmotionalAnalysisTimer()
        }
    }
    
    // MARK: - Emotional Analysis Timer
    
    private func startEmotionalAnalysisTimer() {
        stopEmotionalAnalysisTimer() // Ensure no duplicate timers
        let fireInterval = emotionalAnalysisInterval
        emotionalAnalysisTimer = Timer.scheduledTimer(withTimeInterval: fireInterval, repeats: true) { [weak self] _ in
            self?.performScheduledEmotionalAnalysis()
        }
        logger.info("✅ Started emotional analysis timer (\(Int(fireInterval))s interval) with immediate first run")
        // Fire first analysis immediately so UI has an initial neutral/real state
        performScheduledEmotionalAnalysis()
    startEmotionalCountdown()
    }

    private func performScheduledEmotionalAnalysis() {
        guard !isAnalyzing else {
            logger.info("⏱️ Skipping scheduled analysis; one already running")
            return
        }
        let textToAnalyze = emotionalAnalysisSnapshot()
        // Always run (even if empty) so UI keeps updating; service defaults to Neutral for empty text
        isAnalyzing = true
        Task { @MainActor in
            await self.emotionalAnalysisService.analyzeText(textToAnalyze)
            self.isAnalyzing = false
            self.lastEmotionalAnalysisAt = Date()
            self.updateEmotionalCountdown()
        }
    }

    private func restartEmotionalAnalysisTimer() {
        logger.info("🔄 Restarting emotional analysis timer after manual override")
        startEmotionalAnalysisTimer()
    }
    
    private func stopEmotionalAnalysisTimer() {
        emotionalAnalysisTimer?.invalidate()
        emotionalAnalysisTimer = nil
        logger.info("🛑 Stopped emotional analysis timer")
    emotionalCountdownTimer?.invalidate()
    emotionalCountdownTimer = nil
    }
    
    /// Clear pending analysis text
    func clearAnalysisText() {
        logger.info("🗑️ Cleared pending analysis text")
    }
    
    /// Get the most recent analysis result
    var mostRecentAnalysis: EmotionalAnalysis? {
        return self.lastAnalysis
    }

    // Always-present analysis (falls back to Neutral)
    var currentAnalysis: EmotionalAnalysis {
        lastAnalysis ?? EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
    }

    // MARK: - Debug / Test Utilities
    func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        // This should be called on the main thread as it modifies a @Published property
        DispatchQueue.main.async {
            let textToAppend = self.accumulatedText.isEmpty ? text : " " + text
            self.accumulatedText += textToAppend
            self.logger.info("🧪 DEBUG: Manually appended text: '\(text)'")
        }
    }

    func sendTestPrompt() {
        logger.info("🧪 DEBUG: Manually sending accumulated text via Test AI button.")
        Task {
            await processAccumulatedText(self.accumulatedText)
        }
    }

    // MARK: - Emotional Analysis Snapshot Builder
    /// Combines accumulated session text with any current live partial (recent speech) and trims to a max length.
    private func emotionalAnalysisSnapshot(maxLength: Int = 1000) -> String {
        // Combine distinct components
        let parts = [accumulatedText, livePartial]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        let combined = parts.joined(separator: " ")
        if combined.count <= maxLength { return combined }
        // Keep the most recent portion (suffix) to reflect current emotional state
        let truncated = String(combined.suffix(maxLength))
        return truncated
    }

    // MARK: - Emotional Countdown Helpers
    private func startEmotionalCountdown() {
        emotionalCountdownTimer?.invalidate()
        emotionalCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateEmotionalCountdown()
        }
        updateEmotionalCountdown()
    }
    private func updateEmotionalCountdown() {
        guard let last = lastEmotionalAnalysisAt else {
            timeUntilNextEmotionalAnalysis = 0
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = emotionalAnalysisInterval - elapsed
        timeUntilNextEmotionalAnalysis = max(0, remaining)
    }

    // MARK: - Emotion Scoring
    private func score(for emotion: String) -> Double {
        let key = emotion.lowercased()
        let mapping: [String: Double] = [
            "ecstatic": 1.0,
            "happy": 0.8,
            "confident": 0.6,
            "calm": 0.4,
            "neutral": 0.0,
            "logical": 0.1,
            "analytical": 0.1,
            "emotional": 0.0,
            "stressed": -0.3,
            "anxious": -0.5,
            "sad": -0.6,
            "heartbroken": -0.8,
            "depressed": -0.9
        ]
        return mapping[key] ?? 0.0
    }
    
    // MARK: - Therapy Chat State
    @Published var therapyMessages: [ChatMessage] = []
    @Published var isTherapyLoading: Bool = false
    
    // Build emotional trend summary for therapy context
    private func buildEmotionalTrendSummary(last: Int = 12) -> String {
        if emotionalTrend.isEmpty { return "(no emotional snapshots yet)" }
        let slice = emotionalTrend.suffix(last)
        let parts = slice.map { point in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: point.date)): \(point.emotion) \(point.emoji)"
        }
        return parts.joined(separator: ", ")
    }
    
    // Build pattern summaries for therapy context
    private func buildPatternSummaries() -> String {
        if dailyPatterns.isEmpty { return "(no patterns identified yet)" }
        return dailyPatterns.map { p in "- \(p.title): \(p.summary)" }.joined(separator: "\n")
    }
    
    // MARK: - Transcript Context for Therapy Chat
    /// Returns a trimmed transcript (most recent N characters) for therapy chat context.
    func therapyTranscriptContext(maxChars: Int = 6000) -> String {
        let full = [accumulatedText, livePartial]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard full.count > maxChars else { return full }
        return String(full.suffix(maxChars))
    }
    
    /// Returns patterns as a compact JSON-like string for injection.
    func therapyPatternsContext() -> String {
        guard !dailyPatterns.isEmpty else { return "[]" }
        let dicts: [[String: String]] = dailyPatterns.map { p in
            [
                "title": p.title,
                "summary": p.summary,
                "emoji": p.emoji,
                "evidence": p.evidenceSnippet
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dicts, options: []) {
            return String(data: data, encoding: .utf8) ?? "[]"
        }
        return "[]"
    }
    
    func sendTherapyMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isTherapyLoading else { return }
        let userMsg = ChatMessage(text: trimmed, role: .user)
        therapyMessages.append(userMsg)
        isTherapyLoading = true
        Task { [weak self] in
            guard let self = self else { return }
            let emotionalSummary = self.buildEmotionalTrendSummary()
            let patternSummary = self.buildPatternSummaries()
            let transcriptCtx = self.therapyTranscriptContext()
            let patternsJSON = self.therapyPatternsContext()
            do {
                let reply = try await self.apiService.generateTherapyResponse(
                    userMessage: trimmed,
                    emotionalTrendSummary: emotionalSummary,
                    patternSummaries: patternSummary,
                    transcriptContext: transcriptCtx,
                    patternsJSON: patternsJSON,
                    priorTherapyTurns: self.therapyMessages
                )
                await MainActor.run {
                    self.therapyMessages.append(ChatMessage(text: reply, role: .ai))
                    self.isTherapyLoading = false
                }
            } catch {
                await MainActor.run {
                    self.therapyMessages.append(ChatMessage(text: "I'm having trouble formulating a response right now. Could you rephrase or try again in a moment?", role: .ai))
                    self.isTherapyLoading = false
                }
            }
        }
    }
}