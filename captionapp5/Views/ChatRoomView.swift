//
//  ChatRoomView.swift
//  captionapp5
//
// 

import SwiftUI
import MultipeerConnectivity
import Combine


enum ChatRoomSheet: Identifiable {
    case arMode
    case settings
    case participants
    
    var id: Int {
        switch self {
        case .arMode: return 0
        case .settings: return 1
        case .participants: return 2
        }
    }
}

struct ChatRoomView: View {
    @EnvironmentObject var roomState: RoomState
    @StateObject private var multipeerService = MultipeerService()
    @StateObject private var speechService = SpeechRecognitionService()
    @State private var activeSheet: ChatRoomSheet?
    @State private var liveByUser: [UUID: CaptionMessage] = [:]
    @State private var lastUpdatedUserID: UUID?
    @State private var lastNetworkSendTime: [UUID: Date] = [:]
    
    //updates UI
    private var combinedLiveText: String {
        roomState.participants
            .compactMap { liveByUser[$0.id]?.text }
            .joined()
    }
    
    private let networkThrottleInterval: TimeInterval = 0.1
    
    var body: some View {
        VStack(spacing: 0) {
            //shows the status like participants + connection
            ConnectionStatusBar(
                status: roomState.connectionStatus,
                participantCount: roomState.participants.count
            )
            
            //the chatbox area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Constants.Spacing.medium) {
                        ForEach(roomState.participants) { user in
                            LiveTranscriptView(
                                user: user,
                                liveMessage: getLiveMessage(for: user.id)
                            )
                            .id(user.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: combinedLiveText) {
                    if let userID = lastUpdatedUserID {
                        withAnimation(.spring()) {
                            proxy.scrollTo(userID, anchor: .bottom)
                        }
                    }
                }
            }
            
            //record button
            RecordingControlsView(
                isRecording: $roomState.isRecording,
                speechService: speechService
            )
            
            
            BottomControlsView(
                onShowARMode: { activeSheet = .arMode },
                onShowSettings: { activeSheet = .settings },
                onShowParticipants: { activeSheet = .participants }
            )
        }
        .navigationTitle(roomState.currentRoom?.name ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    if roomState.isHost {
                        Button(action: {
                            endRoomForAll()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("End Room")
                            }
                        }
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                    } else {
                        Button("Leave") {
                            leaveRoom()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    activeSheet = .participants
                }) {
                    Image(systemName: "person.2.fill")
                }
            }
        }
            .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .arMode:
                ARCaptionView()
                    .environmentObject(multipeerService)
            case .settings:
                SettingsView()
            case .participants:
                ParticipantsView(participants: roomState.participants)
            }
        }
        .onAppear {
            setupServices()
        }
        .onDisappear {
            cleanupServices()
            liveByUser.removeAll()
        }
    }
    
    private func setupServices() {
        if roomState.isHost, let room = roomState.currentRoom {
            multipeerService.startHosting(
                roomName: room.name,
                userName: roomState.currentUser?.name ?? "Host",
                isPrivate: room.isPrivate,
                password: room.password
            )
        } else {
            multipeerService.startBrowsing()
            
            //have users join the room
            if let room = roomState.currentRoom {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    multipeerService.joinRoom(room, password: room.password)
                }
            }
        }
        
        speechService.onTranscriptionResult = { text, isFinal, confidence in
            guard let currentUser = roomState.currentUser else { return }

            let msg = CaptionMessage(
                userId: currentUser.id,
                userName: currentUser.name,
                userColor: currentUser.color,
                text: text,
                isFinal: isFinal,
                confidence: confidence
            )
            
            DispatchQueue.main.async {
                self.liveByUser[currentUser.id] = msg
                self.lastUpdatedUserID = currentUser.id
                roomState.addOrUpdateMessage(msg)
                
                if isFinal {
                    self.lastNetworkSendTime.removeValue(forKey: currentUser.id)
                    multipeerService.sendMessage(msg)
                    HapticManager.shared.impact(.light)
                } else {
                    let now = Date()
                    let lastSend = self.lastNetworkSendTime[currentUser.id] ?? .distantPast
                    
                    if now.timeIntervalSince(lastSend) >= self.networkThrottleInterval {
                        multipeerService.sendMessage(msg)
                        self.lastNetworkSendTime[currentUser.id] = now
                    }
                }
            }
        }
        
        multipeerService.onReceivedMessage = { [weak roomState] message in
            DispatchQueue.main.async {
                if message.isFinal {
                    roomState?.addOrUpdateMessage(message)
                    self.liveByUser.removeValue(forKey: message.userId)
                } else {
                    self.liveByUser[message.userId] = message
                    roomState?.addOrUpdateMessage(message)
                    self.lastUpdatedUserID = message.userId
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let currentUser = roomState.currentUser {
                multipeerService.sendUserProfile(currentUser)
            }
        }
        
        multipeerService.onPeerConnected = { peer in
            print("Peer connected: \(peer.displayName)")
            HapticManager.shared.simpleSuccess()
            
            if let currentUser = roomState.currentUser {
                multipeerService.sendUserProfile(currentUser)
            }
        }
        
        multipeerService.onReceivedUserProfile = { user in
            print("Received user profile: \(user.name)")
            roomState.addParticipant(user)
        }
        
        multipeerService.onPeerDisconnected = { peer in
            print("Peer disconnected: \(peer.displayName)")
            
            if let userToRemove = roomState.participants.first(where: { $0.name == peer.displayName }) {
                let userId = userToRemove.id
                
                roomState.removeParticipant(userId)
                self.liveByUser.removeValue(forKey: userId)
                roomState.messages.removeAll { $0.userId == userId }
                self.lastNetworkSendTime.removeValue(forKey: userId)
                
            }
        }
        
        multipeerService.onRoomEnded = {
           
            self.leaveRoom()
        }
    }
    
    private func cleanupServices() {
        speechService.stopRecording()
        multipeerService.disconnect()
        lastNetworkSendTime.removeAll()
    }   
    
    private func leaveRoom() {
        speechService.stopRecording()
        multipeerService.disconnect()
        
        liveByUser.removeAll()
        lastNetworkSendTime.removeAll()
        
        roomState.currentRoom = nil
        roomState.participants.removeAll()
        roomState.messages.removeAll()
        roomState.isConnected = false
        roomState.isHost = false
        roomState.connectionStatus = .disconnected
        
    }
    
    private func endRoomForAll() {
        multipeerService.broadcastEndRoom()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.leaveRoom()
        }
    }
    
    private func getLiveMessage(for userId: UUID) -> String {
        if let live = liveByUser[userId] {
            return live.text
        }
        
        if let last = roomState.messages.first(where: { $0.userId == userId }) {
            return last.text
        }
        
        return ""
    }
   
}

struct LiveTranscriptView: View {
    let user: User
    let liveMessage: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(user.name)
                    .font(.headline)
                    .foregroundColor(user.color.color)
                if user.isHost {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            
            Text(liveMessage)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Constants.Colors.secondaryBackground)
                .cornerRadius(12)
        }
    }
}

struct ConnectionStatusBar: View {
    let status: ConnectionStatus
    let participantCount: Int
    
    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(statusColor)
            
            Text(status.displayName)
                .font(Constants.Fonts.captionSmall)
                .foregroundColor(statusColor)
            
            Spacer()
            
            Text("\(participantCount) participant\(participantCount == 1 ? "" : "s")")
                .font(Constants.Fonts.captionSmall)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Constants.Spacing.medium)
        .padding(.vertical, Constants.Spacing.small)
        .background(Constants.Colors.secondaryBackground)
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return Constants.Colors.success
        case .connecting, .searching:
            return Constants.Colors.warning
        case .disconnected:
            return Constants.Colors.secondary
        case .error:
            return Constants.Colors.error
        }
    }
}

struct RecordingControlsView: View {
    @Binding var isRecording: Bool
    let speechService: SpeechRecognitionService
    
    var body: some View {
        HStack(spacing: Constants.Spacing.large) {
            Spacer()
            
            // Recording Button
            Button(action: {
                toggleRecording()
            }) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(isRecording ? Constants.Colors.error : Constants.Colors.primary)
            }
            
            Spacer()
        }
        .padding(.vertical, Constants.Spacing.medium)
        .background(Constants.Colors.background)
    }
    
    private func toggleRecording() {
        HapticManager.shared.impact(.medium)
        if isRecording {
            speechService.stopRecording()
        } else {
            speechService.startRecording()
        }
        isRecording.toggle()
    }
}

struct BottomControlsView: View {
    let onShowARMode: () -> Void
    let onShowSettings: () -> Void
    let onShowParticipants: () -> Void
    
    var body: some View {
        HStack(spacing: Constants.Spacing.large) {
            Button(action: onShowParticipants) {
                VStack {
                    Image(systemName: "person.2.fill")
                    Text("Participants")
                        .font(.caption)
                }
            }
            .foregroundColor(Constants.Colors.primary)
            
            Spacer()
            
            Button(action: onShowARMode) {
                VStack {
                    Image(systemName: "arkit")
                    Text("AR Mode")
                        .font(.caption)
                }
            }
            .foregroundColor(Constants.Colors.primary)
            
            Spacer()
            
            Button(action: onShowSettings) {
                VStack {
                    Image(systemName: "gear")
                    Text("Settings")
                        .font(.caption)
                }
            }
            .foregroundColor(Constants.Colors.primary)
        }
        .padding(.horizontal, Constants.Spacing.large)
        .padding(.vertical, Constants.Spacing.medium)
        .background(Constants.Colors.secondaryBackground)
    }
}

struct ParticipantsView: View {
    let participants: [User]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(participants) { participant in
                HStack {
                    Circle()
                        .fill(participant.color.color)
                        .frame(width: 20, height: 20)
                    
                    Text(participant.name)
                        .font(Constants.Fonts.body)
                    
                    Spacer()
                    
                    if participant.isHost {
                        Text("Host")
                            .font(Constants.Fonts.captionSmall)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: participant.isConnected ? "wifi" : "wifi.slash")
                        .foregroundColor(participant.isConnected ? Constants.Colors.success : Constants.Colors.error)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        let roomState = RoomState()
        let multipeer = MultipeerService()
        ChatRoomView()
            .environmentObject(roomState)
            .environmentObject(multipeer)
    }
}
