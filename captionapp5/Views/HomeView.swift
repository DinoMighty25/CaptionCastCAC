//
//  HomeView.swift
//  captionapp5
//
//

import SwiftUI


enum HomeViewSheet: Identifiable {
    case createRoom
    case joinRoom
    case settings
    
    var id: Int {
        switch self {
        case .createRoom: return 0
        case .joinRoom: return 1
        case .settings: return 2
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var roomState: RoomState
    @State private var activeSheet: HomeViewSheet?
    
    var body: some View {
        VStack(spacing: Constants.Spacing.large) {
            VStack(spacing: Constants.Spacing.medium) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 80))
                    .foregroundColor(Constants.Colors.primary)
                
                Text("CaptionCast")
                    .font(Constants.Fonts.title)
                    .foregroundColor(.primary)
                
                Text("Real-time transcription with AR overlay")
                    .font(Constants.Fonts.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Constants.Spacing.extraLarge)
            
            Spacer()
            
            //main buttons
            VStack(spacing: Constants.Spacing.medium) {
                Button(action: {
                    activeSheet = .createRoom
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Room")
                    }
                    .font(Constants.Fonts.subtitle)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Constants.Colors.primary)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    activeSheet = .joinRoom
                }) {
                    HStack {
                        Image(systemName: "person.2.circle.fill")
                        Text("Join Room")
                    }
                    .font(Constants.Fonts.subtitle)
                    .foregroundColor(Constants.Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Constants.Colors.primary, lineWidth: 2)
                    )
                }
            }
            .padding(.horizontal, Constants.Spacing.large)
            
            Spacer()
            
            VStack(spacing: Constants.Spacing.small) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.secondary)
                    Text("Connect up to \(Constants.maxParticipants) devices")
                        .font(Constants.Fonts.captionSmall)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.secondary)
                    Text("Real-time speech recognition")
                        .font(Constants.Fonts.captionSmall)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "arkit")
                        .foregroundColor(.secondary)
                    Text("AR caption overlay")
                        .font(Constants.Fonts.captionSmall)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, Constants.Spacing.large)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    activeSheet = .settings
                }) {
                    
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createRoom:
                CreateRoomView()
            case .joinRoom:
                JoinRoomView()
            case .settings:
                SettingsView()
                
            }
        }
        .fullScreenCover(item: $roomState.currentRoom) { room in
            NavigationView {
                ChatRoomView()
                    .environmentObject(roomState)
            }
            .navigationViewStyle(.stack)
            
        }
    }
}

#Preview {
    NavigationView {
        let roomState = RoomState()
        HomeView()
            .environmentObject(roomState)
    }
}
