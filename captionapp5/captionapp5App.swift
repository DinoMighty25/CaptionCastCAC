//
//  captionapp5App.swift
//  captionapp5
//
//

import SwiftUI
import AVFoundation

@main
struct captionapp5App: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var roomState = RoomState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(permissionManager)
                .environmentObject(roomState)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // Configure audio session for recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
        // Set up user defaults
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.isFirstLaunch) == nil {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.isFirstLaunch)
            UserDefaults.standard.set("User", forKey: Constants.UserDefaultsKeys.userName)
            UserDefaults.standard.set(UserColor.blue.rawValue, forKey: Constants.UserDefaultsKeys.userColor)
        }
    }
}
