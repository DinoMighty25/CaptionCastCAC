//
//  Constants.swift
//  captionapp5
//
//
import Foundation
import SwiftUI

//putting constants in one file
struct Constants {
    
    //MARK: - App Configuration
    static let appName = "CaptionCast"
    static let version = "1.0.0"
    static let serviceType = "caption-app"
    
    //MARK: - Multipeer Configuration
    static let maxParticipants = 8
    static let connectionTimeout: TimeInterval = 30.0
    static let messageTimeout: TimeInterval = 10.0
    
    //MARK: - Speech Recognition
    static let speechRecognitionTimeout: TimeInterval = 60.0
    static let silenceThreshold: Float = 0.1
    static let maxAudioBufferSize = 1024
    static let defaultAudioThreshold: Float = -30.0
    static let minAudioThreshold: Float = -100.0
    static let maxAudioThreshold: Float = -10.0
    
    //MARK: - Speech Recognition Timing
    static let speechRecognitionRestartDelay: TimeInterval = 0.8
    static let speechSessionFinalizeDelay: TimeInterval = 0.5
    static let duplicateMessageWindow: TimeInterval = 2.0
    
    //MARK: - UI debouncing
    static let liveMessageDebounceDelay: TimeInterval = 0.15
    static let liveUserCleanupDelay: TimeInterval = 30.0
    
    //MARK: - AR configuration
    static let arFrameProcessingInterval = 6
    static let arCaptionLifetime: TimeInterval = 10.0
    static let arFaceObservationTimeout: TimeInterval = 3.0
    static let maxDetectedFaces = 5
    static let captionDisplayDuration: TimeInterval = 5.0
    
    // MARK: - Memory management
    static let maxActiveCaptions = 10
    static let maxFaceObservations = 5
    static let messageBatchSize = 100
    static let staleDataCleanupInterval: TimeInterval = 180.0
    
    // MARK: - UI Configuration
    static let maxMessagesInHistory = 100
    static let messageRetentionTime: TimeInterval = 300
    static let autoScrollDelay: TimeInterval = 0.5
    
    // MARK: - Colors
    struct Colors {
        static let primary = Color.blue
        static let secondary = Color.gray
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let captionBackground = Color.black.opacity(0.7)
        static let captionText = Color.white
    }
    
    // MARK: - Fonts
    struct Fonts {
        static let caption = Font.system(size: 16, weight: .medium)
        static let captionLarge = Font.system(size: 20, weight: .medium)
        static let captionSmall = Font.system(size: 14, weight: .regular)
        static let title = Font.system(size: 24, weight: .bold)
        static let subtitle = Font.system(size: 18, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    // MARK: - Animation
    struct Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let medium = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.8)
    }
    
    // MARK: - Error Messages
    struct ErrorMessages {
        static let microphonePermissionDenied = "Microphone access is required for live captioning. Please enable it in Settings."
        static let speechRecognitionPermissionDenied = "Speech recognition is required for transcription. Please enable it in Settings."
        static let cameraPermissionDenied = "Camera access is required for AR mode. Please enable it in Settings."
        static let connectionFailed = "Failed to connect to the room. Please try again."
        static let speechRecognitionError = "Speech recognition failed. Please try again."
        static let audioSessionError = "Audio session error. Please restart the app."
        static let networkError = "Network connection error. Please check your connection."
    }
    
    // MARK: - Success Messages
    struct SuccessMessages {
        static let roomCreated = "Room created successfully!"
        static let roomJoined = "Successfully joined the room!"
        static let messageSent = "Message sent successfully!"
        static let permissionsGranted = "All permissions granted!"
    }
    
    // MARK: - User Defaults Keys
    struct UserDefaultsKeys {
        static let userName = "userName"
        static let userColor = "userColor"
        static let lastRoomName = "lastRoomName"
        static let isFirstLaunch = "isFirstLaunch"
        static let captionFontSize = "captionFontSize"
        static let autoScrollEnabled = "autoScrollEnabled"
        static let audioThreshold = "audioThreshold"
    }
    
    // MARK: - Notification Names
    struct NotificationNames {
        static let didReceiveMessage = Notification.Name("didReceiveMessage")
        static let didConnectToPeer = Notification.Name("didConnectToPeer")
        static let didDisconnectFromPeer = Notification.Name("didDisconnectFromPeer")
        static let speechRecognitionStarted = Notification.Name("speechRecognitionStarted")
        static let speechRecognitionStopped = Notification.Name("speechRecognitionStopped")
        static let faceDetected = Notification.Name("faceDetected")
    }
}
