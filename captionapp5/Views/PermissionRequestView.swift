//
//  PermissionRequestView.swift
//  captionapp5
//
//

import SwiftUI

//just to get permissions from user at the very start
struct PermissionRequestView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var isRequestingPermissions = false
    
    var body: some View {
        VStack(spacing: Constants.Spacing.large) {
            // Header
            VStack(spacing: Constants.Spacing.medium) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(Constants.Colors.warning)
                
                Text("Permissions Required")
                    .font(Constants.Fonts.title)
                    .foregroundColor(.primary)
                
                Text("Live Caption needs access to your microphone and speech recognition to provide real-time transcription.")
                    .font(Constants.Fonts.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Constants.Spacing.extraLarge)
            
            Spacer()
            
            // Permission Status List
            VStack(spacing: Constants.Spacing.medium) {
                PermissionRow(
                    title: "Microphone",
                    description: "Required for audio capture",
                    status: permissionManager.microphonePermission,
                    icon: "mic.fill"
                )
                
                PermissionRow(
                    title: "Speech Recognition",
                    description: "Required for transcription",
                    status: permissionManager.speechRecognitionPermission,
                    icon: "waveform"
                )
                
                PermissionRow(
                    title: "Camera",
                    description: "Required for AR mode",
                    status: permissionManager.cameraPermission,
                    icon: "camera.fill"
                )
            }
            .padding(.horizontal, Constants.Spacing.large)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: Constants.Spacing.medium) {
                if permissionManager.hasRequiredPermissions {
                    Button(action: {
                        // Permissions are sufficient, app will automatically navigate
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Continue")
                        }
                        .font(Constants.Fonts.subtitle)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.success)
                        .cornerRadius(12)
                    }
                } else {
                    Button(action: {
                        requestAllPermissions()
                    }) {
                        HStack {
                            if isRequestingPermissions {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "gear")
                            }
                            Text(isRequestingPermissions ? "Requesting..." : "Grant Permissions")
                        }
                        .font(Constants.Fonts.subtitle)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Constants.Colors.primary)
                        .cornerRadius(12)
                    }
                    .disabled(isRequestingPermissions)
                }
                
                Button(action: {
                    permissionManager.openSettings()
                }) {
                    Text("Open Settings")
                        .font(Constants.Fonts.body)
                        .foregroundColor(Constants.Colors.primary)
                }
            }
            .padding(.horizontal, Constants.Spacing.large)
            .padding(.bottom, Constants.Spacing.large)
        }
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }
    
    private func requestAllPermissions() {
        isRequestingPermissions = true
        
        Task {
            _ = await permissionManager.requestMicrophonePermission()
            _ = await permissionManager.requestSpeechRecognitionPermission()
            _ = await permissionManager.requestCameraPermission()
            
            DispatchQueue.main.async {
                isRequestingPermissions = false
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let status: PermissionManager.PermissionStatus
    let icon: String
    
    var body: some View {
        HStack(spacing: Constants.Spacing.medium) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Constants.Fonts.body)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(Constants.Fonts.captionSmall)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundColor(statusColor)
        }
        .padding()
        .background(Constants.Colors.secondaryBackground)
        .cornerRadius(12)
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
    
    private var statusIcon: String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        }
    }
}

#Preview {
    let pm = PermissionManager()
    return PermissionRequestView()
        .environmentObject(pm)
}
