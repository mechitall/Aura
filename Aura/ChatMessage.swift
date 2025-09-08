//
//  ChatMessage.swift
//  Aura
//
//  Created on 9/8/25.
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let role: MessageRole
    let timestamp: Date
    
    init(text: String, role: MessageRole) {
        self.text = text
        self.role = role
        self.timestamp = Date()
    }
    
    enum MessageRole {
        case user
        case ai
    }
}

// MARK: - Extensions for UI
extension ChatMessage.MessageRole {
    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .ai:
            return "Aura"
        }
    }
    
    var isUser: Bool {
        return self == .user
    }
}