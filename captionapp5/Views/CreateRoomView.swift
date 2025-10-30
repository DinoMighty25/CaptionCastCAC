//
//  CreateRoomView.swift
//  captionapp5
//
//

import SwiftUI

struct CreateRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var roomState: RoomState
    @State private var roomName = ""
    @State private var isPrivate = false
    @State private var password = ""
    @State private var userName = ""
    @State private var selectedColor: UserColor = .blue
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Room Details") {
                    TextField("Room Name", text: $roomName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Toggle("Private Room", isOn: $isPrivate)
                    
                    if isPrivate {
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
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
                
                Section("Room Settings") {
                    HStack {
                        Text("Max Participants")
                        Spacer()
                        Text("\(Constants.maxParticipants)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Create Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createRoom()
                    }
                    .disabled(roomName.isEmpty || userName.isEmpty || isCreating)
                }
            }
        }
        .onAppear {
            loadUserDefaults()
        }
    }
    
    private func loadUserDefaults() {
        userName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userName) ?? "User"
        if let colorString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userColor),
           let color = UserColor(rawValue: colorString) {
            selectedColor = color
        }
    }
    
    private func createRoom() {
        guard !roomName.isEmpty && !userName.isEmpty else { return }
        
        isCreating = true
        
        
        UserDefaults.standard.set(userName, forKey: Constants.UserDefaultsKeys.userName)
        UserDefaults.standard.set(selectedColor.rawValue, forKey: Constants.UserDefaultsKeys.userColor)
        UserDefaults.standard.set(roomName, forKey: Constants.UserDefaultsKeys.lastRoomName)
        
        //make user instance
        let user = User(
            name: userName,
            color: selectedColor,
            isHost: true
        )
        
        //make room instance
        let room = Room(
            name: roomName,
            hostId: user.id,
            hostName: userName,
            isPrivate: isPrivate,
            password: isPrivate ? password : nil
        )
        
       
        roomState.currentRoom = room
        roomState.participants = [user]
        roomState.isHost = true
        roomState.isConnected = true
        roomState.connectionStatus = .connected
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

#Preview {
    let roomState = RoomState()
    return CreateRoomView()
        .environmentObject(roomState)
}
