//
//  ThetaEdgeAnalysisService.swift
//  Aura
//
//  Created on 9/10/25.
//

import Foundation
import os.log

class ThetaEdgeAnalysisService: ObservableObject {
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ThetaEdgeAnalysisService")
    
    // MARK: - Configuration
    private let apiURL = "https://llama3170bqobu7bby0a-9c97d6aa8a18a92f.tec-s20.onthetaedgecloud.com/v1/chat/completions"
    private let analysisInterval: TimeInterval = 60.0 // 1 minute
    
    // MARK: - Properties
    @Published var lastAnalysis: String = ""
    @Published var isAnalyzing: Bool = false
    @Published var analysisHistory: [AnalysisResult] = []
    
    private var analysisTimer: Timer?
    private var pendingText: String = ""
    private var lastAnalysisTime: Date?
    
    // MARK: - Data Models
    struct AnalysisResult {
        let id = UUID()
        let timestamp: Date
        let originalText: String
        let analysis: String
        let emotionalTone: String?
        let suggestions: [String]
    }
    
    struct ThetaEdgeRequest: Codable {
        let model: String
        let messages: [ThetaMessage]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
    }
    
    struct ThetaMessage: Codable {
        let role: String
        let content: String
    }
    
    struct ThetaEdgeResponse: Codable {
        let choices: [Choice]
        let usage: Usage?
        
        struct Choice: Codable {
            let message: ThetaMessage
            let finish_reason: String?
        }
        
        struct Usage: Codable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let total_tokens: Int?
        }
    }
    
    enum AnalysisError: Error {
        case invalidURL
        case noResponse
        case invalidResponse
        case networkError(Error)
        case decodingError(Error)
        case emptyText
    }
    
    // MARK: - Initialization
    init() {
        logger.info("🧠 ThetaEdgeAnalysisService initialized")
        startPeriodicAnalysis()
    }
    
    deinit {
        stopPeriodicAnalysis()
    }
    
    // MARK: - Public Methods
    
    /// Add transcribed text to be analyzed
    func addTranscribedText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !self.pendingText.isEmpty {
            self.pendingText += " "
        }
        self.pendingText += cleanedText
        
        logger.info("📝 Added text for analysis: \(cleanedText.prefix(50))... (Total pending: \(self.pendingText.count) chars)")
    }
    
    /// Manually trigger analysis of pending text
    func analyzeNow() {
        guard !isAnalyzing else {
            logger.warning("⏳ Analysis already in progress, skipping manual trigger")
            return
        }
        
        Task {
            await performAnalysis()
        }
    }
    
    /// Clear all pending text
    func clearPendingText() {
        pendingText = ""
        logger.info("🗑️ Cleared pending text")
    }
    
    // MARK: - Private Methods
    
    private func startPeriodicAnalysis() {
        stopPeriodicAnalysis()
        
        analysisTimer = Timer.scheduledTimer(withTimeInterval: self.analysisInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performAnalysis()
            }
        }
        
        logger.info("⏰ Started periodic analysis timer (every \(self.analysisInterval) seconds)")
    }
    
    private func stopPeriodicAnalysis() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        logger.info("⏰ Stopped periodic analysis timer")
    }
    
    @MainActor
    private func performAnalysis() async {
        guard !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("📭 No pending text to analyze")
            return
        }
        
        guard !isAnalyzing else {
            logger.warning("⏳ Analysis already in progress")
            return
        }
        
        let textToAnalyze = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        
        isAnalyzing = true
        logger.info("🧠 Starting analysis of \(textToAnalyze.count) characters")
        
        do {
            let analysis = try await analyzeTextWithThetaEdge(textToAnalyze)
            
            let result = AnalysisResult(
                timestamp: Date(),
                originalText: textToAnalyze,
                analysis: analysis,
                emotionalTone: extractEmotionalTone(from: analysis),
                suggestions: extractSuggestions(from: analysis)
            )
            
            lastAnalysis = analysis
            analysisHistory.append(result)
            lastAnalysisTime = Date()
            
            // Keep only last 10 analyses to prevent memory issues
            if analysisHistory.count > 10 {
                analysisHistory.removeFirst()
            }
            
            logger.info("✅ Analysis completed successfully")
            
        } catch {
            logger.error("❌ Analysis failed: \(error.localizedDescription)")
        }
        
        isAnalyzing = false
    }
    
    private func analyzeTextWithThetaEdge(_ text: String) async throws -> String {
        guard let url = URL(string: apiURL) else {
            throw AnalysisError.invalidURL
        }
        
        // Create the analysis prompt
        let systemPrompt = """
        You are an expert AI coach and emotional intelligence analyst. Analyze the following transcribed speech for:
        
        1. Emotional tone and state
        2. Key themes and concerns
        3. Communication patterns
        4. Stress levels or emotional indicators
        5. Actionable insights and suggestions
        
        Provide a concise but insightful analysis in 2-3 paragraphs. Focus on being helpful and supportive.
        """
        
        let userPrompt = """
        Please analyze this transcribed speech:
        
        "\(text)"
        
        Provide insights about the speaker's emotional state, main concerns, and any coaching suggestions.
        """
        
        let request = ThetaEdgeRequest(
            model: "llama-3.1-70b-instruct",
            messages: [
                ThetaMessage(role: "system", content: systemPrompt),
                ThetaMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.7,
            max_tokens: 500,
            stream: false
        )
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(Config.shared.thetaAPIKey, forHTTPHeaderField: "x-api-key")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw AnalysisError.decodingError(error)
        }
        
        logger.info("🌐 Sending request to Theta Edge Cloud...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("📡 Received response with status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8) {
                        logger.error("❌ API Error (\(httpResponse.statusCode)): \(errorString)")
                    }
                    throw AnalysisError.invalidResponse
                }
            }
            
            let thetaResponse = try JSONDecoder().decode(ThetaEdgeResponse.self, from: data)
            
            guard let firstChoice = thetaResponse.choices.first else {
                throw AnalysisError.noResponse
            }
            
            let analysisResult = firstChoice.message.content
            logger.info("✅ Analysis received: \(analysisResult.prefix(100))...")
            
            return analysisResult
            
        } catch let error as DecodingError {
            logger.error("❌ Decoding error: \(error)")
            throw AnalysisError.decodingError(error)
        } catch {
            logger.error("❌ Network error: \(error)")
            throw AnalysisError.networkError(error)
        }
    }
    
    private func extractEmotionalTone(from analysis: String) -> String? {
        // Simple keyword extraction for emotional tone
        let lowerAnalysis = analysis.lowercased()
        
        if lowerAnalysis.contains("stressed") || lowerAnalysis.contains("anxious") || lowerAnalysis.contains("worried") {
            return "Stressed/Anxious"
        } else if lowerAnalysis.contains("positive") || lowerAnalysis.contains("optimistic") || lowerAnalysis.contains("confident") {
            return "Positive/Confident"
        } else if lowerAnalysis.contains("sad") || lowerAnalysis.contains("melancholy") || lowerAnalysis.contains("down") {
            return "Sad/Low"
        } else if lowerAnalysis.contains("neutral") || lowerAnalysis.contains("calm") {
            return "Neutral/Calm"
        }
        
        return nil
    }
    
    private func extractSuggestions(from analysis: String) -> [String] {
        // Simple extraction of suggestions - look for numbered lists or bullet points
        var suggestions: [String] = []
        
        let lines = analysis.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("suggest") || trimmed.contains("recommend") || trimmed.contains("consider") {
                if trimmed.count > 10 && trimmed.count < 200 {
                    suggestions.append(trimmed)
                }
            }
        }
        
        return Array(suggestions.prefix(3)) // Limit to 3 suggestions
    }
}
