//
//  Room.swift
//  captionapp5
//

//

import Foundation
import SwiftUI
import Combine

//mpc room struct
struct Room: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let hostId: UUID
    let hostName: String
    let createdAt: Date
    let isPrivate: Bool
    let password: String?
    let maxParticipants: Int
    var currentParticipants: Int
    
    init(id: UUID = UUID(), name: String, hostId: UUID, hostName: String, isPrivate: Bool = false, password: String? = nil, maxParticipants: Int = 8, currentParticipants: Int = 1) {
        self.id = id
        self.name = name
        self.hostId = hostId
        self.hostName = hostName
        self.createdAt = Date()
        self.isPrivate = isPrivate
        self.password = password
        self.maxParticipants = maxParticipants
        self.currentParticipants = currentParticipants
    }
}

//class to track active sessions
class RoomState: ObservableObject {
    @Published var currentRoom: Room?
    @Published var participants: [User] = []
    @Published var messages: [CaptionMessage] = []
    @Published var isConnected: Bool = false
    @Published var isHost: Bool = false
    @Published var isRecording: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var arParticipantStates: [UUID: ARParticipantState] = [:]
    
    var currentUser: User? {
        return participants.first { $0.isHost == isHost }
    }
    
    
    func addMessage(_ message: CaptionMessage) {
        messages.insert(message, at: 0)
        
        //keep only 100 messages
        if messages.count > 100 {
            messages.removeLast(messages.count - 100)
        }
    }
    
    //simple: add or replace the caption without duplicate filtering
    func addOrUpdateMessage(_ message: CaptionMessage) {
        if message.isFinal {
            //isFinal means the user finished; clear their live line
            messages.removeAll { $0.userId == message.userId && !$0.isFinal }
            //skip empty finals
            if message.text.isEmpty {
                return
            }
            addMessage(message)
        } else {
            //this means the person is still talking so update accordingly
            if let whereTheirMessageIs = messages.firstIndex(where: { $0.userId == message.userId && !$0.isFinal }) {
                messages[whereTheirMessageIs] = message
            } else {
                //else add it as a new live message
                messages.insert(message, at: 0)
            }
        }
    }
    
    //other functions for room logistics
    func clearMessages() {
        messages.removeAll()
    }
    
    func addParticipant(_ user: User) {
        if !participants.contains(where: { $0.id == user.id }) {
            participants.append(user)
            updateParticipantCount(participants.count)
        }
    }
    
    func removeParticipant(_ userId: UUID) {
        participants.removeAll { $0.id == userId }
        updateParticipantCount(participants.count)
    }
    
    func updateParticipantCount(_ count: Int) {
        guard var room = currentRoom else { return }
        room.currentParticipants = count
        currentRoom = room
    }

    func updateARState(for userId: UUID, isActive: Bool, isRecording: Bool, sessionId: UUID, timestamp: Date = Date()) {
        let state = ARParticipantState(isActive: isActive, isRecording: isRecording, sessionId: sessionId, updatedAt: timestamp)
        arParticipantStates[userId] = state
    }

    func participantARState(for userId: UUID) -> ARParticipantState? {
        return arParticipantStates[userId]
    }

    func isParticipantARActive(_ userId: UUID) -> Bool {
        return arParticipantStates[userId]?.isActive ?? false
    }

    var activeARParticipantIds: Set<UUID> {
        Set(arParticipantStates.compactMap { $0.value.isActive ? $0.key : nil })
    }

    var inactiveARParticipants: [User] {
        participants.filter { !(arParticipantStates[$0.id]?.isActive ?? false) }
    }
}

//struct for user connection status
struct ARParticipantState: Equatable {
    var isActive: Bool
    var isRecording: Bool
    var sessionId: UUID
    var updatedAt: Date
}
//enum for user connection status
enum ConnectionStatus: String, CaseIterable {
    case disconnected = "disconnected"
    case searching = "searching"
    case connecting = "connecting"
    case connected = "connected"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .searching: return "Searching..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Connection Error"
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected: return "wifi.slash"
        case .searching: return "wifi"
        case .connecting: return "wifi"
        case .connected: return "wifi"
        case .error: return "exclamationmark.triangle"
        }
    }
}
