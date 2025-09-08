import Foundation
import os.log

class ThetaAPIService {
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "ThetaAPIService")
    
    private let apiKey = "sk-b65eu3mkh669b7a4ppl2s25b7yf0b0c9c339a3"
    private let baseURL = "https://ondemand.thetaedgecloud.com/infer_request/llama_3_1_70b/completions"
    
    enum APIError: Error {
        case invalidURL
        case invalidResponse
        case noResponse
        case decodingError(Error)
        case networkError(Error)
    }
    
    func generateAIInsight(messages: [ChatMessage]) async throws -> String {
        logger.info("💬 Starting AI insight generation with \(messages.count) messages in history")
        
        guard let url = URL(string: baseURL) else {
            logger.error("❌ Invalid URL for Theta EdgeCloud API")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemMessage = ThetaMessage(
            role: "system",
            content: """
            You are Aura, a premium AI companion designed to provide thoughtful, personalized coaching and support. 
            
            Your personality:
            - Warm, empathetic, and genuinely caring
            - Wise and insightful, offering deep perspective
            - Encouraging yet honest, providing balanced feedback
            - Sophisticated but approachable communication style
            
            Your responses should:
            - Be concise yet meaningful (2-3 sentences ideal)
            - Focus on practical insights and emotional support
            - Ask thoughtful follow-up questions when appropriate
            - Maintain a premium, polished tone
            - Show genuine interest in the user's growth and wellbeing
            
            Remember: You're not just answering questions, you're building a meaningful relationship and helping someone become their best self.
            """
        )
        
        var apiMessages = [systemMessage]
        
        for message in messages {
            apiMessages.append(ThetaMessage(
                role: message.role.isUser ? "user" : "assistant",
                content: message.text
            ))
        }
        
        let requestBody = ThetaRequest(
            messages: apiMessages,
            max_tokens: 500,
            temperature: 0.7,
            stream: true
        )
        
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            
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
    let messages: [ThetaMessage]
    let max_tokens: Int
    let temperature: Double
    let stream: Bool
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
