import Foundation
import Combine
import os.log

struct EmotionalAnalysis {
    let emotion: String
    let emoji: String
}

class EmotionalAnalysisService: ObservableObject {
    @Published var analysis: EmotionalAnalysis?
    
    private let logger = Logger(subsystem: "com.yourcompany.Aura", category: "EmotionalAnalysisService")
    private let thetaAPIService = ThetaAPIService()
    
    func analyzeText(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async {
                self.analysis = EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
            }
            return
        }
        
        let prompt = """
        Analyze the emotional content of the following text. The text is a transcript of a user's spoken words from the last 30 seconds. Consider the textual context, semantics, and punctuation.
        
        Respond with the single most appropriate word to describe the user's emotional state (e.g., Happy, Anxious, Sad, Depressed, Ecstatic, Heartbroken, Logical, Analytical, Emotional) and an appropriate emoji.
        
        If no strong emotional content is found, respond with "Neutral" and the 😐 emoji.
        
        Format your response as: Emotion:Emoji
        
        Text to analyze: "\(text)"
        """
        
        let messages = [ChatMessage(text: prompt, role: .user)]
        
        do {
            let response = try await thetaAPIService.generateAIInsight(messages: messages)
            parseAnalysis(response)
        } catch {
            logger.error("Error analyzing emotional content: \(error.localizedDescription)")
        }
    }
    
    private func parseAnalysis(_ response: String) {
        let parts = response.split(separator: ":").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2 {
            let emotion = parts[0]
            let emoji = String(parts[1])
            DispatchQueue.main.async {
                self.analysis = EmotionalAnalysis(emotion: emotion, emoji: emoji)
            }
        } else {
            DispatchQueue.main.async {
                self.analysis = EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
            }
        }
    }
}
