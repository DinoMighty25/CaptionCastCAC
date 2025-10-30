//
//  MultipeerService.swift
//  captionapp5
//
//

import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit
import Combine

class MultipeerService: NSObject, ObservableObject {
    private let serviceType = Constants.serviceType
    private let myPeerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availableRooms: [Room] = []
    @Published var roomPeers: [UUID: MCPeerID] = [:] // Map room IDs to peer IDs
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String?
    
    // Error recovery
    private var advertisingRetryCount = 0
    private let maxRetryAttempts = 3
    
    // Callbacks
    var onReceivedMessage: ((CaptionMessage) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    var onRoomDiscovered: ((Room) -> Void)?
    var onReceivedUserProfile: ((User) -> Void)?
    var onReceivedARState: ((ARStateMessage) -> Void)?
    var onReceivedFaceAssignment: ((FaceAssignmentMessage) -> Void)?
    var onRoomEnded: (() -> Void)?
    
    override init() {
        // Create peer ID with device name
        let deviceName = UIDevice.current.name
        self.myPeerId = MCPeerID(displayName: deviceName)
        
        // Create session
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        
        super.init()
        
        // Set session delegate
        self.session.delegate = self
    }
    
    // MARK: - Hosting
    
    func startHosting(roomName: String, userName: String, isPrivate: Bool = false, password: String? = nil) {
        stopAllServices()
        
        let hostId = UUID() // Separate host ID
        let roomId = UUID() // Unique room ID
        
        let room = Room(
            id: roomId,
            name: roomName,
            hostId: hostId,
            hostName: userName,
            isPrivate: isPrivate,
            password: password
        )
        
        // Store the room ID for this peer
        roomPeers[room.id] = myPeerId
        
        // Create advertiser
        let discoveryInfo = [
            "roomId": roomId.uuidString,
            "hostId": hostId.uuidString, // Include separate host ID
            "roomName": roomName,
            "hostName": userName,
            "isPrivate": String(isPrivate),
            "password": password ?? ""
        ]
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser?.delegate = self
        
        isHosting = true
        connectionStatus = .searching
        advertiser?.startAdvertisingPeer()
        
        print("Started hosting room: \(roomName) (Room ID: \(roomId), Host ID: \(hostId))")
    }
    
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isHosting = false
        
        if !isBrowsing {
            connectionStatus = .disconnected
        }
        
        print("Stopped hosting")
    }
    
    // MARK: - Browsing
    
    func startBrowsing() {
        stopAllServices()
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
        
        isBrowsing = true
        connectionStatus = .searching
        browser?.startBrowsingForPeers()
        
        print("Started browsing for rooms")
    }
    
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        
        if !isHosting {
            connectionStatus = .disconnected
        }
        
        print("Stopped browsing")
    }
    
    // MARK: - Connection
    
    func joinRoom(_ room: Room, password: String? = nil) {
        guard let browser = browser else { return }

        // Find the peer hosting this room from the available rooms
        guard let hostingRoom = availableRooms.first(where: { $0.id == room.id }),
              let peerId = roomPeers[room.id] else {
            print("Room not found in available rooms")
            return
        }

        connectionStatus = .connecting
        
        // Actually invite the peer
        let context = password?.data(using: .utf8)
        browser.invitePeer(peerId, to: session, withContext: context, timeout: 30)

        print("Attempting to join room: \(room.name) hosted by \(hostingRoom.hostName)")
    }
    
    func disconnect() {
        session.disconnect()
        stopAllServices()
        connectedPeers.removeAll()
        connectionStatus = .disconnected
        
        print("Disconnected from all peers")
    }
    
    // MARK: - Messaging
    
    func sendMessage(_ message: CaptionMessage) {
        sendEnvelope(type: .caption, payload: message)
    }
    
    
    
    func sendUserProfile(_ user: User) {
        sendEnvelope(type: .userProfile, payload: UserProfileMessage(user: user))
    }

    func broadcastARState(_ state: ARStateMessage) {
        sendEnvelope(type: .arState, payload: state)
    }

    func broadcastFaceAssignment(_ assignment: FaceAssignmentMessage) {
        sendEnvelope(type: .faceAssignment, payload: assignment)
    }
    
    func broadcastEndRoom() {
        guard !connectedPeers.isEmpty else {
            print("No connected peers to notify")
            return
        }
        
        let endRoomMessage = SystemMessage(type: .connection, text: "HOST_END_ROOM")
        if let encoded = try? JSONEncoder().encode(endRoomMessage) {
            do {
                try session.send(encoded, toPeers: connectedPeers, with: .reliable)
                print("Sent end room message to \(connectedPeers.count) peers")
            } catch {
                print("Failed to send end room message: \(error)")
            }
        }
    }

    private func sendEnvelope<T: Codable>(type: MessageEnvelopeType, payload: T) {
        guard !connectedPeers.isEmpty else {
            print("No connected peers to send envelope")
            return
        }
        
        do {
            let envelope = MessageEnvelope(type: type, payload: payload)
            let data = try JSONEncoder().encode(envelope)
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            print("Sent envelope type \(type.rawValue) to \(connectedPeers.count) peers")
        } catch {
            print("Failed to send envelope: \(error)")
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func stopAllServices() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        isHosting = false
        isBrowsing = false
    }
    
    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        do {
            let decoder = JSONDecoder()
            let base = try decoder.decode(MessageEnvelopeBase.self, from: data)
            switch base.type {
            case .caption:
                let envelope = try decoder.decode(MessageEnvelope<CaptionMessage>.self, from: data)
                let message = envelope.payload
                print("Received message from \(peer.displayName): \(message.text)")
                DispatchQueue.main.async { self.onReceivedMessage?(message) }
            case .userProfile:
                let envelope = try decoder.decode(MessageEnvelope<UserProfileMessage>.self, from: data)
                let profileMessage = envelope.payload
                print("Received user profile from \(peer.displayName): \(profileMessage.user.name)")
                DispatchQueue.main.async { self.onReceivedUserProfile?(profileMessage.user) }
            case .arState:
                let envelope = try decoder.decode(MessageEnvelope<ARStateMessage>.self, from: data)
                DispatchQueue.main.async { self.onReceivedARState?(envelope.payload) }
            case .faceAssignment:
                let envelope = try decoder.decode(MessageEnvelope<FaceAssignmentMessage>.self, from: data)
                DispatchQueue.main.async { self.onReceivedFaceAssignment?(envelope.payload) }
            }
        } catch {
            print("Failed to decode data from \(peer.displayName): \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.connectionStatus = .connected
                self.onPeerConnected?(peerID)
                print("Peer connected: \(peerID.displayName) - Total peers: \(self.connectedPeers.count)")
                
            case .connecting:
                self.connectionStatus = .connecting
                print("Connecting to peer: \(peerID.displayName)")
                
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.onPeerDisconnected?(peerID)
                
                if self.connectedPeers.isEmpty {
                    self.connectionStatus = .disconnected
                }
                print("Peer disconnected: \(peerID.displayName) - Remaining peers: \(self.connectedPeers.count)")
                
            @unknown default:
                print("Unknown session state")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check if it's a system message for ending the room
        if let systemMessage = try? JSONDecoder().decode(SystemMessage.self, from: data),
           systemMessage.text == "HOST_END_ROOM" {
            DispatchQueue.main.async {
                print("Host ended the room")
                self.onRoomEnded?()
            }
            return
        }
        
        handleReceivedData(data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from: \(peerID.displayName)")
        
        // Auto-accept invitations for now
        // In a production app, you might want to show a confirmation dialog
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let nsError = error as NSError
        print("Failed to start advertising: \(error.localizedDescription)")
        print("   Error code: \(nsError.code), domain: \(nsError.domain)")
        
        DispatchQueue.main.async {
            self.errorMessage = "Advertising failed (code: \(nsError.code))"
            self.connectionStatus = .error
        }
        
        // Retry with exponential backoff
        if advertisingRetryCount < maxRetryAttempts && nsError.code != -72008 {
            let delay = pow(2.0, Double(advertisingRetryCount))
            print("Retrying advertising in \(delay) seconds...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.advertisingRetryCount += 1
                self?.advertiser?.startAdvertisingPeer()
            }
        } else if nsError.code == -72008 {
            print("Bonjour error -72008 (simulator/permissions issue) - may not affect functionality")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let info = info,
              let roomIdString = info["roomId"],
              let roomId = UUID(uuidString: roomIdString),
              let hostIdString = info["hostId"], // Get separate host ID
              let hostId = UUID(uuidString: hostIdString),
              let roomName = info["roomName"],
              let hostName = info["hostName"] else { 
            print("Invalid discovery info from peer: \(peerID.displayName)")
            return 
        }
        
        let isPrivate = info["isPrivate"] == "true"
        let password = info["password"]?.isEmpty == false ? info["password"] : nil
        
        let room = Room(
            id: roomId,
            name: roomName,
            hostId: hostId, // Use proper host ID
            hostName: hostName,
            isPrivate: isPrivate,
            password: password
        )
        
        // Store the mapping between room and peer
        roomPeers[room.id] = peerID
        
        DispatchQueue.main.async {
            if !self.availableRooms.contains(where: { $0.id == room.id }) {
                self.availableRooms.append(room)
                self.onRoomDiscovered?(room)
                print("Found room: \(roomName) (Host: \(hostName))")
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            // Remove rooms associated with this peer
            let roomsToRemove = self.roomPeers.compactMap { (roomId, peer) in
                peer == peerID ? roomId : nil
            }
            
            for roomId in roomsToRemove {
                self.roomPeers.removeValue(forKey: roomId)
                self.availableRooms.removeAll { $0.id == roomId }
            }
        }
        print("Lost peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Failed to start browsing: \(error.localizedDescription)"
            self.connectionStatus = .error
        }
        print("Failed to start browsing: \(error)")
    }
}

// MARK: - Message Types

struct UserProfileMessage: Codable {
    let type: String
    let user: User
    
    init(type: String = "userProfile", user: User) {
        self.type = type
        self.user = user
    }
}
