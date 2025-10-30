//
//  ContentView.swift
//  captionapp5
//
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var roomState: RoomState
    
    var body: some View {
        NavigationView {
            Group {
                if permissionManager.allPermissionsGranted {
                    HomeView()
                } else {
                    PermissionRequestView()
                }
            }
            .navigationTitle(Constants.appName)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    let permissionManager = PermissionManager()
    let roomState = RoomState()
    return ContentView()
        .environmentObject(permissionManager)
        .environmentObject(roomState)
}
