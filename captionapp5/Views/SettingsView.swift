//
//  SettingsView.swift
//  captionapp5
//
//

import SwiftUI

//user settings
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var userName = ""
    @State private var selectedColor: UserColor = .blue
    @State private var captionFontSize: Double = 16
    @State private var autoScrollEnabled = true
    @State private var audioThreshold: Double = -30.0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Profile") {
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
                
                Section("Display") {
                    VStack(alignment: .leading) {
                        Text("Caption Font Size")
                        Slider(value: $captionFontSize, in: 12...24, step: 1)
                        Text("\(Int(captionFontSize))pt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Auto-scroll Messages", isOn: $autoScrollEnabled)
                }
                
                Section("Audio Sensitivity") {
                    VStack(alignment: .leading) {
                        Text("Voice Detection Threshold")
                        Slider(value: $audioThreshold, in: -100...(-10), step: 5)
                        HStack {
                            Text("Lower = more sensitive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(audioThreshold)) dB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Permissions") {
                    PermissionStatusRow(
                        title: "Microphone",
                        status: permissionManager.microphonePermission,
                        icon: "mic.fill"
                    )
                    
                    PermissionStatusRow(
                        title: "Speech Recognition",
                        status: permissionManager.speechRecognitionPermission,
                        icon: "waveform"
                    )
                    
                    PermissionStatusRow(
                        title: "Camera",
                        status: permissionManager.cameraPermission,
                        icon: "camera.fill"
                    )
                    
                    Button("Open Settings") {
                        permissionManager.openSettings()
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Constants.version)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text(Constants.appName)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Data") {
                    Button("Reset All Settings") {
                        resetSettings()
                    }
                    .foregroundColor(Constants.Colors.error)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        userName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userName) ?? "User"
        captionFontSize = Double(UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.captionFontSize))
        if captionFontSize == 0 { captionFontSize = 16 }
        
        autoScrollEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.autoScrollEnabled) as? Bool ?? true
        
        let savedThreshold = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.audioThreshold)
        audioThreshold = savedThreshold != 0 ? savedThreshold : Double(Constants.defaultAudioThreshold)
        
        if let colorString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userColor),
           let color = UserColor(rawValue: colorString) {
            selectedColor = color
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(userName, forKey: Constants.UserDefaultsKeys.userName)
        UserDefaults.standard.set(selectedColor.rawValue, forKey: Constants.UserDefaultsKeys.userColor)
        UserDefaults.standard.set(Int(captionFontSize), forKey: Constants.UserDefaultsKeys.captionFontSize)
        UserDefaults.standard.set(autoScrollEnabled, forKey: Constants.UserDefaultsKeys.autoScrollEnabled)
        UserDefaults.standard.set(audioThreshold, forKey: Constants.UserDefaultsKeys.audioThreshold)
    }
    
    private func resetSettings() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userName)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userColor)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.captionFontSize)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.autoScrollEnabled)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.audioThreshold)
        
        loadSettings()
    }
}

struct PermissionStatusRow: View {
    let title: String
    let status: PermissionManager.PermissionStatus
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            Text(statusText)
                .foregroundColor(statusColor)
                .font(.caption)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .granted:
            return Constants.Colors.success
        case .denied, .restricted:
            return Constants.Colors.error
        case .notDetermined:
            return Constants.Colors.warning
        }
    }
    
    private var statusText: String {
        switch status {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Set"
        }
    }
}

#Preview {
    let permissionManager = PermissionManager()
    return SettingsView()
        .environmentObject(permissionManager)
}
