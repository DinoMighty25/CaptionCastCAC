//
//  PermissionManager.swift
//  captionapp5
//

import Foundation
import AVFoundation
import Speech
import UIKit
import SwiftUI
import Combine

//determine if permissions for microphone, camera, local network, etc. are granted
class PermissionManager: ObservableObject {
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var speechRecognitionPermission: PermissionStatus = .notDetermined
    @Published var cameraPermission: PermissionStatus = .notDetermined
    
    enum PermissionStatus {
        case notDetermined
        case granted
        case denied
        case restricted
    }
    
    init() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        microphonePermission = checkMicrophonePermission()
        speechRecognitionPermission = checkSpeechRecognitionPermission()
        cameraPermission = checkCameraPermission()
    }
    
    private func checkMicrophonePermission() -> PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    private func checkSpeechRecognitionPermission() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    private func checkCameraPermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.microphonePermission = granted ? .granted : .denied
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized:
                        self.speechRecognitionPermission = .granted
                        continuation.resume(returning: true)
                    case .denied, .restricted, .notDetermined:
                        self.speechRecognitionPermission = .denied
                        continuation.resume(returning: false)
                    @unknown default:
                        self.speechRecognitionPermission = .denied
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    func requestCameraPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermission = granted ? .granted : .denied
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    var allPermissionsGranted: Bool {
        return microphonePermission == .granted && 
               speechRecognitionPermission == .granted && 
               cameraPermission == .granted
    }
    
    var hasRequiredPermissions: Bool {
        return microphonePermission == .granted && speechRecognitionPermission == .granted
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}
