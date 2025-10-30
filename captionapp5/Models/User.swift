//
//  User.swift
//  captionapp5
//
//

import Foundation
import SwiftUI

//user struct
struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: UserColor
    let isHost: Bool
    let isConnected: Bool
    let lastSeen: Date
    
    init(id: UUID = UUID(), name: String, color: UserColor = .blue, isHost: Bool = false, isConnected: Bool = true) {
        self.id = id
        self.name = name
        self.color = color
        self.isHost = isHost
        self.isConnected = isConnected
        self.lastSeen = Date()
    }
}
//other user attributes
enum UserColor: String, CaseIterable, Codable {
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case purple = "purple"
    case red = "red"
    case yellow = "yellow"
    case pink = "pink"
    case teal = "teal"
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .yellow: return .yellow
        case .pink: return .pink
        case .teal: return .teal
        }
    }
    
    var displayName: String {
        return rawValue.capitalized
    }
}
