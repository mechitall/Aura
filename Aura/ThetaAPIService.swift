import Foundation
import os.log

class ThetaAPIService {
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ThetaAPIService")
    
    private let apiKey = Config.shared.thetaAPIKey
    private let baseURL = "https://ondemand.thetaedgecloud.com/infer_request/llama_3_1_70b/completions"
    
    // MARK: - API Data Models (for Theta EdgeCloud)
    
    // This struct matches the nested "input" object required by the API
    struct ThetaRequestInput: Codable {
        let messages: [ThetaMessage]
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
        let frequency_penalty: Double
        let top_p: Double
    }
    
    // This is the top-level request object
    struct ThetaRequest: Codable {
        let input: ThetaRequestInput
    }
    
    struct ThetaMessage: Codable {
        let role: String
        let content: String
    }
    
    // The response from the on-demand API is different from the analysis one
    struct ThetaResponse: Codable {
        let status: String
        let body: ThetaBody
    }
    
    struct ThetaBody: Codable {
        let infer_requests: [InferenceRequest]
    }
    
    struct InferenceRequest: Codable {
        let id: String
        let output: InferenceOutput?
    }
    
    struct InferenceOutput: Codable {
        let message: String
    }
    
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
    
    /// Generates an AI response for the accumulated conversation.
    /// Added `useStreaming` flag so we can disable streaming easily while debugging missing responses.
    /// When streaming is disabled the API is asked for a single JSON response which is easier to parse / log.
    func generateAIInsight(messages: [ChatMessage], useStreaming: Bool = false) async throws -> String {
        logger.info("💬 Starting AI insight generation (stream=\(useStreaming)) with \(messages.count) messages in history")
        
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
        // Use Bearer token authorization as required by the on-demand endpoint
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfig)
        
        let apiMessages = manageContext(messages)
        
        if let lastUser = messages.last(where: { $0.role.isUser }) {
            let preview = String(lastUser.text.prefix(120))
            logger.info("📌 Last user message going into request: len=\(lastUser.text.count) preview='\(preview)'")
        } else {
            logger.warning("⚠️ No user message found when preparing request body")
        }
        
        // Create the nested input object
        let requestInput = ThetaRequestInput(
            messages: apiMessages,
            stream: useStreaming,
            temperature: 0.75,
            max_tokens: 400,
            frequency_penalty: 0.1,
            top_p: 0.9 // A standard value for top_p
        )
        
        // Wrap the input object in the main request body
        let requestBody = ThetaRequest(input: requestInput)
        
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger.info("📤 Request JSON: \(jsonString)")
            }
            logger.info("📊 Sending \(apiMessages.count) total messages to API")
            
            logger.info("🚀 Making request to Theta EdgeCloud API (timeout=30s)")
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Invalid response type from Theta EdgeCloud")
                throw APIError.invalidResponse
            }
            
            logger.info("📥 AI insight response status: \(httpResponse.statusCode)")
            
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            logger.info("📄 Raw AI response body: \(rawBody)")

            if httpResponse.statusCode != 200 {
                logger.error("💥 Theta EdgeCloud API error status=\(httpResponse.statusCode) body='\(rawBody.prefix(500))'")
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    logger.error("🔐 Authentication / authorization failure. Verify API key is valid & not expired.")
                } else if httpResponse.statusCode == 404 {
                    logger.error("❓ Endpoint not found – confirm model path /infer_request/deepseek_r1/completions is correct for current Theta deployment.")
                } else if httpResponse.statusCode >= 500 {
                    logger.error("🛠️ Server-side error – may retry after delay.")
                }
                throw APIError.networkError(NSError(domain: "ThetaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: rawBody]))
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            logger.info("📄 Raw AI response (first 500 chars): \(String(responseString.prefix(500)))")
            logger.info("📊 Response data size: \(data.count) bytes")
            
            // If streaming disabled just parse as normal JSON directly
            if !useStreaming {
                do {
                    let thetaResponse = try JSONDecoder().decode(ThetaResponse.self, from: data)
                    
                    guard let firstRequest = thetaResponse.body.infer_requests.first,
                          let output = firstRequest.output else {
                        logger.error("💥 Could not find inference output in response")
                        throw APIError.noResponse
                    }
                    
                    return output.message
                } catch {
                    logger.error("💥 JSON parsing failed: \(error)")
                    if let responseBody = String(data: data, encoding: .utf8) {
                        logger.error("💥 Full response data that failed to parse: '\(responseBody)'")
                    }
                    throw APIError.decodingError(error)
                }
            } else {
                return try parseStreamingResponse(responseString: responseString)
            }
            
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
                        
                        if let message = streamResponse.body.infer_requests.first?.output?.message {
                            fullResponse += message
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
                
                if let firstRequest = response.body.infer_requests.first,
                   let output = firstRequest.output {
                    logger.info("✅ Theta EdgeCloud insight successful (JSON): \(output.message.prefix(100))...")
                    return output.message
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

    // MARK: - One-Off Analysis (Bypasses conversation context & rate limit)
    /// Performs a single analysis request with explicit system + user prompts, ignoring stored conversation context.
    /// Useful for large aggregate analyses (e.g. daily pattern mining) so it doesn't pollute regular chat context.
    func oneOffAnalysis(systemPrompt: String, userPrompt: String, temperature: Double = 0.6, maxTokens: Int = 800) async throws -> String {
        guard let url = URL(string: baseURL) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // We intentionally DO NOT call checkRateLimit() here to allow back-to-back manual analyses.
        // Still update the timestamp to avoid overlapping generateAIInsight soon after.
        updateRequestTime()

        let messages: [ThetaMessage] = [
            ThetaMessage(role: "system", content: systemPrompt),
            ThetaMessage(role: "user", content: userPrompt)
        ]

        let input = ThetaRequestInput(
            messages: messages,
            stream: false,
            temperature: temperature,
            max_tokens: maxTokens,
            frequency_penalty: 0.1,
            top_p: 0.9
        )
        let body = ThetaRequest(input: input)
        request.httpBody = try JSONEncoder().encode(body)
        logger.info("🚀 One-off analysis request (messages=\(messages.count), userChars=\(userPrompt.count))")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            logger.info("📥 One-off status=\(http.statusCode) size=\(data.count)")
            if http.statusCode != 200 {
                logger.error("💥 One-off non-200 status=\(http.statusCode) body='\(raw.prefix(400))'")
                throw APIError.invalidResponse
            }
            // Parse like normal non-streaming response
            do {
                let thetaResponse = try JSONDecoder().decode(ThetaResponse.self, from: data)
                guard let first = thetaResponse.body.infer_requests.first, let output = first.output else {
                    throw APIError.noResponse
                }
                return output.message
            } catch {
                logger.error("💥 One-off decode failed: \(error)")
                throw APIError.decodingError(error)
            }
        } catch let apiErr as APIError {
            throw apiErr
        } catch {
            logger.error("💥 One-off network failure: \(error)")
            throw APIError.networkError(error)
        }
    }
}