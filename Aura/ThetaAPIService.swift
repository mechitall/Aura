import Foundation
import os.log

class ThetaAPIService {
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ThetaAPIService")
    
    private let apiKey = "332zr94npjc8rvfwsnitytwbz05acxb5y6tc8pbrpaiur2c5t0s1tx5s7whfxbsd"
    private let baseURL = "https://ondemand.thetaedgecloud.com/infer_request/llama_3_1_70b/completions"
    
    // MARK: - Context Management
    private var conversationContext: [ThetaMessage] = []
    private var lastRequestTime: Date?
    private let cooldownPeriod: TimeInterval = 2.0 // Minimum 2 seconds between requests
    private let maxContextMessages: Int = 20 // Keep last 20 messages for context
    private let maxTokensPerMessage: Int = 300 // Reasonable token limit per message
    
    enum APIError: Error {
        case invalidURL
        case invalidResponse
        case noResponse
        case decodingError(Error)
        case networkError(Error)
        case rateLimited
        case contextTooLarge
    }
    
    // MARK: - Rate Limiting & Context Management
    private func checkRateLimit() -> Bool {
        guard let lastTime = lastRequestTime else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= cooldownPeriod
    }
    
    private func updateRequestTime() {
        lastRequestTime = Date()
    }
    
    private func manageContext(_ messages: [ChatMessage]) -> [ThetaMessage] {
        // Create system message with enhanced context awareness
        let systemMessage = ThetaMessage(
            role: "system",
            content: """
            You are Aura, a premium AI companion designed to provide thoughtful, personalized coaching and support.
            
            IMPORTANT: You are receiving continuous speech input from the user. The user speaks naturally and you should:
            - Respond to their current thoughts and emotional state
            - Reference previous parts of the conversation when relevant
            - Provide concise but meaningful responses (1-3 sentences typically)
            - Ask thoughtful follow-up questions to encourage deeper reflection
            - Notice patterns and themes in what they're sharing
            
            Your personality:
            - Warm, empathetic, and genuinely caring
            - Wise and insightful, offering deep perspective
            - Encouraging yet honest, providing balanced feedback
            - Sophisticated but approachable communication style
            
            Remember: You're building a continuous relationship. The user may pause, think out loud, or share stream-of-consciousness thoughts. Respond naturally and helpfully to support their growth and wellbeing.
            """
        )
        
        var apiMessages = [systemMessage]
        
        // Add existing conversation context
        apiMessages.append(contentsOf: conversationContext)
        
        // Filter and add recent messages
        let validMessages = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let recentMessages = Array(validMessages.suffix(maxContextMessages))
        
        for message in recentMessages {
            let trimmedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                // Truncate very long messages to prevent token limits
                let truncatedText = String(trimmedText.prefix(maxTokensPerMessage * 4)) // Rough character estimate
                apiMessages.append(ThetaMessage(
                    role: message.role.isUser ? "user" : "assistant",
                    content: truncatedText
                ))
            }
        }
        
        // Update conversation context (keep recent messages)
        let conversationMessages = apiMessages.filter { $0.role != "system" }
        conversationContext = Array(conversationMessages.suffix(maxContextMessages))
        
        return apiMessages
    }
    
    func generateAIInsight(messages: [ChatMessage]) async throws -> String {
        logger.info("💬 Starting AI insight generation with \(messages.count) messages in history")
        
        // Check rate limiting
        guard checkRateLimit() else {
            logger.warning("⏱️ Rate limited - too soon since last request")
            throw APIError.rateLimited
        }
        
        // Validate that we have actual user messages with content
        let userMessages = messages.filter { $0.role.isUser && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !userMessages.isEmpty else {
            logger.error("❌ No valid user messages found - skipping API call")
            throw APIError.noResponse
        }
        
        logger.info("📊 Found \(userMessages.count) valid user messages")
        
        // Update request time immediately to prevent concurrent requests
        updateRequestTime()
        
        guard let url = URL(string: baseURL) else {
            logger.error("❌ Invalid URL for Theta EdgeCloud API")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use enhanced context management
        let apiMessages = manageContext(messages)
        
        let requestBody = ThetaRequest(
            input: ThetaRequestInput(
                messages: apiMessages,
                max_tokens: 400, // Slightly reduced for more focused responses
                temperature: 0.75, // Slightly higher for more natural conversation
                stream: true,
                top_p: 0.9, // Add nucleus sampling for better quality
                frequency_penalty: 0.1 // Reduce repetition
            )
        )
        
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            
            // Debug: Log the actual request being sent
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger.info("📤 Request JSON: \(jsonString)")
            }
            logger.info("📊 Sending \(apiMessages.count) total messages to API")
            
            logger.info("🚀 Making request to Theta EdgeCloud API")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Invalid response type from Theta EdgeCloud")
                throw APIError.invalidResponse
            }
            
            logger.info("📥 AI insight response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("💥 Theta EdgeCloud API error (\(httpResponse.statusCode)): \(errorMessage)")
                throw APIError.networkError(NSError(domain: "ThetaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            logger.info("📄 Raw AI response (first 500 chars): \(String(responseString.prefix(500)))")
            logger.info("📊 Response data size: \(data.count) bytes")
            
            return try parseStreamingResponse(responseString: responseString)
            
        } catch let error as APIError {
            throw error
        } catch {
            logger.error("💥 Network error during AI insight generation: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Context Management Methods
    func clearContext() {
        conversationContext.removeAll()
        logger.info("🧠 Conversation context cleared")
    }
    
    func getContextSize() -> Int {
        return conversationContext.count
    }
    
    var timeUntilNextRequest: TimeInterval {
        guard let lastTime = lastRequestTime else { return 0 }
        let elapsed = Date().timeIntervalSince(lastTime)
        return max(0, cooldownPeriod - elapsed)
    }
    
    private func parseStreamingResponse(responseString: String) throws -> String {
        logger.info("🔍 Starting response parsing")
        
        // Check if this is Server-Sent Events format (SSE)
        if responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("data:") {
            logger.info("🔄 Detected streaming response format")
            
            let responseLines = responseString.components(separatedBy: "\n")
            var fullResponse = ""
            
            for line in responseLines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.hasPrefix("data: ") {
                    let jsonString = String(trimmedLine.dropFirst(6)) // Remove "data: " prefix
                    
                    if jsonString == "[DONE]" {
                        break
                    }
                    
                    guard let jsonData = jsonString.data(using: .utf8) else { continue }
                    
                    do {
                        let streamResponse = try JSONDecoder().decode(ThetaResponse.self, from: jsonData)
                        
                        if let firstChoice = streamResponse.choices.first {
                            if let delta = firstChoice.delta {
                                fullResponse += delta.content
                            } else if let message = firstChoice.message {
                                fullResponse += message.content
                            }
                        }
                    } catch {
                        logger.error("💥 Failed to parse streaming JSON chunk: \(error)")
                        continue
                    }
                }
            }
            
            guard !fullResponse.isEmpty else {
                logger.error("❌ No response content received from streaming")
                throw APIError.noResponse
            }
            
            logger.info("✅ Theta EdgeCloud streaming insight successful: \(fullResponse.prefix(100))...")
            return fullResponse
            
        } else {
            // Try parsing as regular JSON
            logger.info("🔄 Attempting regular JSON parsing")
            
            guard let data = responseString.data(using: .utf8) else {
                logger.error("💥 Could not convert response to data")
                throw APIError.invalidResponse
            }
            
            do {
                let response = try JSONDecoder().decode(ThetaResponse.self, from: data)
                
                if let firstChoice = response.choices.first {
                    let message = firstChoice.message ?? ThetaResponseMessage(content: "")
                    logger.info("✅ Theta EdgeCloud insight successful (JSON): \(message.content.prefix(100))...")
                    return message.content
                } else {
                    logger.error("❌ No response choices received from Theta EdgeCloud")
                    throw APIError.noResponse
                }
            } catch {
                logger.error("💥 JSON parsing failed: \(error)")
                logger.error("💥 Full response data that failed to parse: '\(responseString)'")
                throw APIError.decodingError(error)
            }
        }
    }
}

// MARK: - Request/Response Models
struct ThetaRequest: Codable {
    let input: ThetaRequestInput
}

struct ThetaRequestInput: Codable {
    let messages: [ThetaMessage]
    let max_tokens: Int
    let temperature: Double
    let stream: Bool
    let top_p: Double?
    let frequency_penalty: Double?
    
    init(messages: [ThetaMessage], max_tokens: Int, temperature: Double, stream: Bool, top_p: Double? = nil, frequency_penalty: Double? = nil) {
        self.messages = messages
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.stream = stream
        self.top_p = top_p
        self.frequency_penalty = frequency_penalty
    }
}

struct ThetaMessage: Codable {
    let role: String
    let content: String
}

struct ThetaResponse: Codable {
    let choices: [ThetaChoice]
}

struct ThetaChoice: Codable {
    let index: Int?
    let message: ThetaResponseMessage?
    let delta: ThetaResponseMessage?
}

struct ThetaResponseMessage: Codable {
    let content: String
}
