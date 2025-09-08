//
//  ChatBubbleView.swift
//  Aura
//
//  Created on 9/8/25.
//

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Text(message.text)
                    .font(.body)
                    .foregroundColor(message.role.isUser ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(message.role.isUser ? Color.blue : Color(.systemGray6))
                    )
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
            
            if !message.role.isUser {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct ChatBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ChatBubbleView(
                message: ChatMessage(
                    text: "Hello, I'm feeling a bit anxious today. Can you help me work through this?",
                    role: .user
                )
            )
            
            ChatBubbleView(
                message: ChatMessage(
                    text: "I hear that you're feeling anxious today, and I want you to know that reaching out is a really positive step. Can you tell me a bit more about what might be contributing to these feelings? Sometimes it helps to identify specific thoughts or situations that are on your mind.",
                    role: .ai
                )
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}