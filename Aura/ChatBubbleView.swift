//
//  ChatBubbleView.swift
//  Aura
//
//  Created on 9/8/25.
//

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var isAnimating = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.role.isUser {
                Spacer(minLength: 60)
            } else {
                // AI Avatar for Aura
                AuraAvatarView()
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.8).delay(0.1),
                        value: isAnimating
                    )
            }
            
            VStack(alignment: message.role.isUser ? .trailing : .leading, spacing: 8) {
                // Enhanced message bubble
                HStack {
                    if message.role.isUser { Spacer(minLength: 0) }
                    
                    Text(message.text)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(message.role.isUser ? .white : .primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background {
                            if message.role.isUser {
                                // User message with gradient
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.4, green: 0.2, blue: 0.8),
                                                Color(red: 0.5, green: 0.3, blue: 0.9)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.clear
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    }
                            } else {
                                // AI message with glass effect
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.2),
                                                        Color.clear
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    }
                            }
                        }
                    
                    if !message.role.isUser { Spacer(minLength: 0) }
                }
                
                // Enhanced timestamp
                HStack(spacing: 4) {
                    if !message.role.isUser {
                        Text("Aura")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.4, green: 0.2, blue: 0.8),
                                        Color(red: 0.6, green: 0.3, blue: 0.9)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if message.role.isUser {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            if !message.role.isUser {
                Spacer(minLength: 60)
            } else {
                // User avatar placeholder
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.3, blue: 0.3),
                                Color(red: 0.5, green: 0.5, blue: 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.8).delay(0.1),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
}

// MARK: - Aura Avatar View
struct AuraAvatarView: View {
    @State private var isGlowing = false
    
    var body: some View {
        ZStack {
            // Soft glow effect
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.3),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .scaleEffect(isGlowing ? 1.2 : 1.0)
                .opacity(isGlowing ? 0.7 : 0.4)
                .animation(
                    .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: isGlowing
                )
            
            // Main avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.3, blue: 0.9),
                            Color(red: 0.3, green: 0.1, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .onAppear {
            isGlowing = true
        }
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