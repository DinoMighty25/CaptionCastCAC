//
//  CaptionMessage.swift
//  captionapp5
//
//

import Foundation
import SwiftUI

//make struct of caption message with various attributes
struct CaptionMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let userName: String
    let userColor: UserColor
    let text: String
    let timestamp: Date
    var isFinal: Bool
    let confidence: Float?
    //initialize struct with default values
    init(id: UUID = UUID(), userId: UUID, userName: String, userColor: UserColor, text: String, isFinal: Bool = false, confidence: Float? = nil) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.userColor = userColor
        self.text = text
        self.timestamp = Date()
        self.isFinal = isFinal
        self.confidence = confidence
    }
    
    
    
    //strip text in display for better formatting
    var displayText: String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    //see if message is within the 5 minutes timeframe
    var isRecent: Bool {
        return Date().timeIntervalSince(timestamp) < 300
    }
}

//types of messages
enum MessageType: String, Codable {
    case caption = "caption"
    case system = "system"
    case connection = "connection"
    case error = "error"
}

//struct for system message
struct SystemMessage: Codable, Identifiable {
    let id: UUID
    let type: MessageType
    let text: String
    let timestamp: Date
    
    init(type: MessageType, text: String) {
        self.id = UUID()
        self.type = type
        self.text = text
        self.timestamp = Date()
    }
}
