import Foundation
import Combine
import os.log

// Helper extension to identify emoji characters
extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

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
            // Ensure UI updates even on failure by defaulting to Neutral
            DispatchQueue.main.async {
                self.analysis = EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
            }
        }
    }
    
    private func parseAnalysis(_ response: String) {
        logger.info("🧠 Parsing emotional analysis response: '\(response)'")
        // Try multiple parsing strategies to be tolerant of varying LLM outputs.

        // 1) Standard Emotion:Emoji format (use last colon as separator)
        if let colonRange = response.range(of: ":", options: .backwards) {
            let emotionPart = response[..<colonRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let emojiPart = response[colonRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

            // The emotion might have leading text, e.g., "The emotion is Happy". Take the last word.
            let emotion = String(emotionPart.split(separator: " ").last ?? "")
            // Extract the first sequence of emoji characters from the second part.
            let emoji = String(emojiPart.prefix { $0.isEmoji })

            if !emotion.isEmpty && !emoji.isEmpty {
                logger.info("✅ Successfully parsed emotion: '\(emotion)', emoji: '\(emoji)'")
                DispatchQueue.main.async {
                    self.analysis = EmotionalAnalysis(emotion: emotion, emoji: emoji)
                }
                return
            }
        }

        // 2) If no colon found, attempt to find an emoji and surrounding emotion word.
        if let firstEmoji = response.first(where: { $0.isEmoji }) {
            // Split into lines and search for the line containing the emoji
            let lines = response.components(separatedBy: .newlines)
            for line in lines {
                if line.contains(firstEmoji) {
                    let cleaned = line.replacingOccurrences(of: String(firstEmoji), with: "")
                    let emotionCandidate = String(cleaned.split(separator: " ").last ?? "").trimmingCharacters(in: .punctuationCharacters)
                    if !emotionCandidate.isEmpty {
                        let emojiStr = String(firstEmoji)
                        logger.info("✅ Parsed emotion (fallback): '\(emotionCandidate)', emoji: '\(emojiStr)'")
                        DispatchQueue.main.async {
                            self.analysis = EmotionalAnalysis(emotion: emotionCandidate, emoji: emojiStr)
                        }
                        return
                    }
                }
            }
        }

        // 3) Try a small whitelist of emotion words inside the response
        let candidates = ["Happy","Anxious","Sad","Depressed","Ecstatic","Heartbroken","Logical","Analytical","Emotional","Neutral","Stressed","Calm","Confident"]
        for candidate in candidates {
            if response.range(of: candidate, options: .caseInsensitive) != nil {
                let emojiNear = response.first(where: { $0.isEmoji })
                let emojiStr = emojiNear.map { String($0) } ?? "😐"
                logger.info("✅ Parsed emotion (whitelist): '\(candidate)', emoji: '\(emojiStr)'")
                DispatchQueue.main.async {
                    self.analysis = EmotionalAnalysis(emotion: candidate, emoji: emojiStr)
                }
                return
            }
        }

        // If everything fails, default to Neutral.
        logger.warning("⚠️ Failed to parse emotional analysis from response: '\(response)'. Defaulting to Neutral.")
        DispatchQueue.main.async {
            self.analysis = EmotionalAnalysis(emotion: "Neutral", emoji: "😐")
        }
    }
}
