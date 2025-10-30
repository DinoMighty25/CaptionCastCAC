//
//  JoinRoomView.swift
//  captionapp5
//
//

import SwiftUI

struct JoinRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var roomState: RoomState
    @StateObject private var multipeerService = MultipeerService()
    @State private var userName = ""
    @State private var selectedColor: UserColor = .blue
    @State private var isSearching = false
    @State private var availableRooms: [Room] = []
    @State private var selectedRoom: Room?
    @State private var password = ""
    @State private var showingPasswordPrompt = false
    @State private var discoveryTimeout: Timer?
    
    var body: some View {
        NavigationView {
            VStack {
                if isSearching {
                    searchingView
                } else if availableRooms.isEmpty {
                    emptyStateView
                } else {
                    roomsListView
                }
            }
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        searchForRooms()
                    }
                    .disabled(isSearching)
                }
            }
            .onAppear {
                loadUserDefaults()
                searchForRooms()
            }
            .alert("Enter Password", isPresented: $showingPasswordPrompt) {
                SecureField("Password", text: $password)
                Button("Join") {
                    joinSelectedRoom()
                }
                Button("Cancel", role: .cancel) {
                    password = ""
                }
            } message: {
                Text("This room requires a password to join.")
            }
        }
    }
    
    private var searchingView: some View {
        VStack(spacing: Constants.Spacing.large) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching for rooms...")
                .font(Constants.Fonts.subtitle)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Constants.Spacing.large) {
            Spacer()
            
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No rooms found")
                .font(Constants.Fonts.subtitle)
                .foregroundColor(.primary)
            
            Text("Make sure you're on the same network as the room host and try refreshing.")
                .font(Constants.Fonts.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.Spacing.large)
            
            Spacer()
        }
    }
    
    private var roomsListView: some View {
        VStack {
    
            Form {
                Section("Your Profile") {
                    TextField("Your Name", text: $userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Color", selection: $selectedColor) {
                        ForEach(UserColor.allCases, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 20, height: 20)
                                Text(color.displayName)
                            }
                            .tag(color)
                        }
                    }
                }
                
                Section("Available Rooms") {
                    ForEach(availableRooms) { room in
                        RoomRow(room: room) {
                            selectedRoom = room
                            if room.isPrivate {
                                showingPasswordPrompt = true
                            } else {
                                joinSelectedRoom()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func loadUserDefaults() {
        userName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userName) ?? "User"
        if let colorString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userColor),
           let color = UserColor(rawValue: colorString) {
            selectedColor = color
        }
    }
    
    private func searchForRooms() {
        guard !userName.isEmpty else { return }
        
        isSearching = true
        availableRooms.removeAll()
        multipeerService.startBrowsing()
        
        multipeerService.onRoomDiscovered = { room in
            DispatchQueue.main.async {
                if !availableRooms.contains(where: { $0.id == room.id }) {
                    availableRooms.append(room)
                }
            }
        }
        //timeout if room isn't found
        discoveryTimeout?.invalidate()
        discoveryTimeout = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            DispatchQueue.main.async {
                isSearching = false
                multipeerService.stopBrowsing()
            }
        }
    }
    
    private func joinSelectedRoom() {
        guard let room = selectedRoom, !userName.isEmpty else { return }
        
        //saves user data
        UserDefaults.standard.set(userName, forKey: Constants.UserDefaultsKeys.userName)
        UserDefaults.standard.set(selectedColor.rawValue, forKey: Constants.UserDefaultsKeys.userColor)
        
        //user instance
        let user = User(
            name: userName,
            color: selectedColor,
            isHost: false
        )
        
        
        roomState.currentRoom = room
        roomState.participants = [user]
        roomState.isHost = false
        roomState.isConnected = true
        roomState.connectionStatus = .connected
        
        multipeerService.joinRoom(room, password: password.isEmpty ? nil : password)
        discoveryTimeout?.invalidate()
        multipeerService.stopBrowsing()
        
        dismiss()
    }
}

struct RoomRow: View {
    let room: Room
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(Constants.Fonts.body)
                        .foregroundColor(.primary)
                    
                    Text("Host: \(room.hostName)")
                        .font(Constants.Fonts.captionSmall)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if room.isPrivate {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(room.currentParticipants)/\(room.maxParticipants)")
                        .font(Constants.Fonts.captionSmall)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let roomState = RoomState()
    return JoinRoomView()
        .environmentObject(roomState)
}
