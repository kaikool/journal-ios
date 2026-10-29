import Foundation

public enum AIReflectionAction: String, Codable, Sendable {
    case ask = "ask"
    case critique = "critique"
    case recap = "recap"
}

public struct AIReflectionResponse: Codable, Sendable {
    public let action: String
    public let reflection: String
    
    public init(action: String, reflection: String) {
        self.action = action
        self.reflection = reflection
    }
}

// MARK: - Multi-Turn Conversational Coaching Message
public struct AICoachMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let role: String // "user" or "assistant"
    public let content: String
    public let timestamp: Date
    
    public init(id: String = UUID().uuidString, role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
