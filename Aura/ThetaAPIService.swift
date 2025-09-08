//
//  ThetaAPIService.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation

class ThetaAPIService: ObservableObject {
    
    // MARK: - API Endpoints
    private let whisperEndpoint = "https://api.thetaedgecloud.com/v1/whisper"
    private let llamaEndpoint = "https://api.thetaedgecloud.com/v1/llama"
    
    // MARK: - API Key (Should be stored securely in production)
    private let apiKey = "YOUR_THETA_API_KEY_HERE" // Replace with actual API key
    
    // MARK: - Request/Response Models
    struct WhisperRequest: Codable {
        let audio: String // Base64 encoded audio
        let language: String?
        
        init(audioData: Data, language: String? = nil) {
            self.audio = audioData.base64EncodedString()
            self.language = language
        }
    }
    
    struct WhisperResponse: Codable {
        let text: String
        let language: String?
    }
    
    struct LlamaRequest: Codable {
        let model: String
        let messages: [LlamaMessage]
        let maxTokens: Int
        let temperature: Double
        
        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case maxTokens = "max_tokens"
            case temperature
        }
        
        init(messages: [LlamaMessage]) {
            self.model = "llama-3-8b-instruct"
            self.messages = messages
            self.maxTokens = 150
            self.temperature = 0.7
        }
    }
    
    struct LlamaMessage: Codable {
        let role: String
        let content: String
    }
    
    struct LlamaResponse: Codable {
        let choices: [Choice]
        
        struct Choice: Codable {
            let message: LlamaMessage
        }
    }
    
    // MARK: - System Prompt
    private let systemPrompt = """
    You are 'Aura,' an AI life coach and therapist bot. Your purpose is to listen actively and provide empathetic, non-judgmental, and insightful reflections based on Cognitive Behavioral Therapy (CBT) principles. 
    
    Your Core Directives are:
    - Empathetic Validation: Acknowledge and validate the user's feelings without judgment
    - Socratic Questioning: Ask thoughtful questions to help users explore their thoughts and feelings
    - Identifying Cognitive Distortions: Gently help users recognize unhelpful thinking patterns
    - Maintaining Strict Boundaries: Provide no direct advice or diagnoses - you are not a replacement for professional therapy
    - Brevity and Clarity: Keep responses concise, warm, and easy to understand
    
    Always respond with compassion and focus on helping the user process their thoughts and emotions.
    """
    
    // MARK: - Transcription Service
    func transcribe(audioData: Data) async throws -> String {
        let request = WhisperRequest(audioData: audioData)
        
        var urlRequest = URLRequest(url: URL(string: whisperEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw APIError.encodingError(error)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw APIError.serverError(httpResponse.statusCode)
            }
            
            let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
            return whisperResponse.text
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - AI Insight Service
    func getAIInsight(history: [ChatMessage]) async throws -> String {
        var messages: [LlamaMessage] = [
            LlamaMessage(role: "system", content: systemPrompt)
        ]
        
        // Add conversation history
        for message in history {
            let role = message.role == .user ? "user" : "assistant"
            messages.append(LlamaMessage(role: role, content: message.text))
        }
        
        let request = LlamaRequest(messages: messages)
        
        var urlRequest = URLRequest(url: URL(string: llamaEndpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw APIError.encodingError(error)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw APIError.serverError(httpResponse.statusCode)
            }
            
            let llamaResponse = try JSONDecoder().decode(LlamaResponse.self, from: data)
            
            guard let firstChoice = llamaResponse.choices.first else {
                throw APIError.noResponse
            }
            
            return firstChoice.message.content
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Error Handling
enum APIError: Error, LocalizedError {
    case invalidResponse
    case serverError(Int)
    case networkError(Error)
    case encodingError(Error)
    case decodingError(Error)
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error with code: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .noResponse:
            return "No response received from AI"
        }
    }
}