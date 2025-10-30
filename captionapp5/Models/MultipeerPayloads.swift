//
//  MultipeerPayloads.swift
//  captionapp5
//
//

import Foundation
//this file creates the structure for sending messages across devices
enum MessageEnvelopeType: String, Codable {
    case caption
    case userProfile
    case arState
    case faceAssignment
}

struct MessageEnvelopeBase: Codable {
    let type: MessageEnvelopeType
}

struct MessageEnvelope<T: Codable>: Codable {
    let id: UUID
    let type: MessageEnvelopeType
    let payload: T
    let timestamp: Date

    init(id: UUID = UUID(), type: MessageEnvelopeType, payload: T, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }
}

struct ARStateMessage: Codable {
    let userId: UUID
    let isActive: Bool
    let isRecording: Bool
    let sessionId: UUID
    let timestamp: Date
    
    init(userId: UUID, isActive: Bool, isRecording: Bool, sessionId: UUID, timestamp: Date = Date()) {
        self.userId = userId
        self.isActive = isActive
        self.isRecording = isRecording
        self.sessionId = sessionId
        self.timestamp = timestamp
    }
}

struct FaceAssignmentMessage: Codable {
    let faceId: UUID
    let userId: UUID
}

