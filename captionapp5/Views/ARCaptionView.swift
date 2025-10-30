//
//  ARCaptionView.swift
//  captionapp5
//
//

import SwiftUI
import ARKit
import UIKit
import MultipeerConnectivity

struct ARCaptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var roomState: RoomState
    @StateObject private var arService = ARCaptionService()
    @EnvironmentObject var multipeerService: MultipeerService
    @StateObject private var speechService = SpeechRecognitionService()
    @State private var isRecording = false
    @State private var arSessionId = UUID()
    @State private var arStateUpdateTimer: Timer?
    @State private var showingControls = true
    @State private var showingAssignmentSheet = false
    @State private var selectedFaceId: UUID?
    @State private var isFrontCamera = true

  
    @State private var prevOnReceivedMessage: ((CaptionMessage) -> Void)?
    @State private var prevOnReceivedUserProfile: ((User) -> Void)?
    @State private var prevOnReceivedARState: ((ARStateMessage) -> Void)?
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                //AR camera view
                ARViewContainer(arService: arService)
                    .ignoresSafeArea()
                
                //captions
                ForEach(arService.activeCaptions) { caption in
                    ARCaptionOverlay(caption: caption)
                        .position(
                            x: caption.screenPosition.x * geometry.size.width,
                            y: (caption.screenPosition.y + caption.verticalOffset) * geometry.size.height
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: caption.screenPosition)
                        .animation(.spring(), value: caption.verticalOffset)
                }
                
                //face detection indicators
                if !arService.detectedFaces.isEmpty {
                    ForEach(arService.detectedFaces) { face in
                        FaceIndicator(
                            face: face,
                            geometrySize: geometry.size,
                            assignedUser: arService.userId(for: face.id).flatMap { userId in
                                roomState.participants.first { $0.id == userId }
                            }
                        )
                        .position(
                            x: face.boundingBox.midX * geometry.size.width,
                            y: (1.0 - face.boundingBox.midY) * geometry.size.height
                        )
                        .onTapGesture {
                            guard !showingAssignmentSheet else { return }
                            selectedFaceId = face.id
                            showingAssignmentSheet = true
                        }
                    }
                }
                
                //controls bar
                if showingControls {
                    ARControlsOverlay(
                        isRecording: $isRecording,
                        detectedFacesCount: arService.detectedFaces.count,
                        activeCaptionsCount: arService.activeCaptions.count,
                        onToggleRecording: toggleRecording,
                        onDismiss: { dismiss() },
                        onFlipCamera: flipCamera
                    )
                }
                
                //error in case camera doesn't work
                if let error = arService.error {
                    ErrorOverlay(error: error) {
                        arService.error = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showingAssignmentSheet) {
            if let faceId = selectedFaceId {
                AssignParticipantSheet(participants: roomState.participants) { user in
                    arService.assign(userId: user.id, to: faceId)
                    selectedFaceId = nil
                }
            }
        }
        .onAppear {
            setupServices()
            arService.startARSession()
            sendARState(isActive: true, isRecording: false)
            startARStateTimer()
        }
        .onDisappear {
            if isRecording {
                speechService.stopRecording()
                isRecording = false
            }
            
            cleanupServices()
            arService.stopARSession()
            stopARStateTimer()
            sendARState(isActive: false, isRecording: false)

            restoreMultipeerCallbacks()
        }
        .onTapGesture {
            withAnimation {
                showingControls.toggle()
            }
        }
    }
    
    private func setupServices() {
        prevOnReceivedMessage = multipeerService.onReceivedMessage
        prevOnReceivedUserProfile = multipeerService.onReceivedUserProfile
        prevOnReceivedARState = multipeerService.onReceivedARState
        

        speechService.onTranscriptionResult = { [weak arService] text, isFinal, confidence in
            guard let arService = arService,
                  let currentUser = roomState.currentUser else { return }

            let message = CaptionMessage(
                userId: currentUser.id,
                userName: currentUser.name,
                userColor: currentUser.color,
                text: text,
                isFinal: isFinal,
                confidence: confidence
            )

            DispatchQueue.main.async {
                arService.addOrUpdateCaption(message)
                multipeerService.sendMessage(message)
            }
        }

        multipeerService.onReceivedMessage = { [weak arService] message in
            DispatchQueue.main.async {
                arService?.addOrUpdateCaption(message)
            }
        }

        multipeerService.onReceivedARState = { [weak roomState] state in
            DispatchQueue.main.async {
                roomState?.updateARState(for: state.userId, isActive: state.isActive, isRecording: state.isRecording, sessionId: state.sessionId, timestamp: state.timestamp)
            }
        }
        
        

        multipeerService.onPeerConnected = { _ in
            sendARState(isActive: true, isRecording: isRecording)
        }
        multipeerService.onReceivedUserProfile = { [weak roomState] user in
            DispatchQueue.main.async {
                roomState?.addParticipant(user)
            }
        }
        
        
    }
    
    private func cleanupServices() {
        speechService.stopRecording()
        arService.resetState()
    }

    private func restoreMultipeerCallbacks() {
        multipeerService.onReceivedMessage = prevOnReceivedMessage
        multipeerService.onReceivedUserProfile = prevOnReceivedUserProfile
        multipeerService.onReceivedARState = prevOnReceivedARState
        
    }
    
    private func toggleRecording() {
        if isRecording {
            speechService.stopRecording()
            arService.handleRecordingStopped()
            sendARState(isActive: true, isRecording: false)
        } else {
            arSessionId = UUID()
            arService.handleRecordingStarted()
            speechService.startRecording()
            sendARState(isActive: true, isRecording: true)
        }
        isRecording.toggle()
    }

    private func sendARState(isActive: Bool, isRecording: Bool) {
        guard let currentUser = roomState.currentUser else { return }
        let state = ARStateMessage(userId: currentUser.id, isActive: isActive, isRecording: isRecording, sessionId: arSessionId)
        multipeerService.broadcastARState(state)
        roomState.updateARState(for: currentUser.id, isActive: isActive, isRecording: isRecording, sessionId: arSessionId)
    }

    private func startARStateTimer() {
        arStateUpdateTimer?.invalidate()
        arStateUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            sendARState(isActive: true, isRecording: isRecording)
        }
    }

    private func stopARStateTimer() {
        arStateUpdateTimer?.invalidate()
        arStateUpdateTimer = nil
    }
    
    private func flipCamera() {
        isFrontCamera.toggle()
        arService.flipCamera(toFront: isFrontCamera)
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arService: ARCaptionService
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.session = arService.session
        arView.automaticallyUpdatesLighting = true
        arView.antialiasingMode = .multisampling4X
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        
    }
}

struct ARCaptionOverlay: View {
    @State private var currentPosition: CGPoint
    let caption: ARCaption
    
    init(caption: ARCaption) {
        self.caption = caption
        _currentPosition = State(initialValue: caption.screenPosition)
    }

    var body: some View {
        VStack(spacing: 4) {
            //user name
            Text(caption.message.userName)
                .font(.caption)
                .foregroundColor(caption.message.userColor.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
            
            //caption text
            Text(caption.message.displayText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Constants.Colors.captionBackground)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: currentPosition)
        .onAppear {
            currentPosition = caption.targetPosition
        }
        .onChange(of: caption.targetPosition) { oldPos, newPos in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                currentPosition = newPos
            }
        }
    }
}

struct FaceIndicator: View {
    let face: DetectedFace
    let geometrySize: CGSize
    var assignedUser: User?
    
    var body: some View {
        VStack(spacing: 6) {
            if let user = assignedUser {
                //dot for face indicator
                Circle()
                    .fill(user.color.color)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2)
            } else {
                //assign button
                 VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Tap to Assign")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                 }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.9))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.4), radius: 5)
            }
        }
    }
}

struct ARControlsOverlay: View {
    @Binding var isRecording: Bool
    let detectedFacesCount: Int
    let activeCaptionsCount: Int
    let onToggleRecording: () -> Void
    let onDismiss: () -> Void
    let onFlipCamera: () -> Void
    
    var body: some View {
        VStack {
            //top controls
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack {
                    Text("AR Caption Mode")
                        .font(.headline)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                    
                    Text("\(detectedFacesCount) faces, \(activeCaptionsCount) captions")
                        .font(.caption)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                }
                
                Spacer()
                
                Button(action: onFlipCamera) {
                    Image(systemName: "camera.rotate.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding()
            
            Spacer()
            
            //bottom controls
            HStack(spacing: 40) {
                //record button
                Button(action: onToggleRecording) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(isRecording ? .red : .white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                
      
                VStack {
                    Text("Tap to speak")
                        .font(.caption)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                    
                    Text("Captions will appear near detected faces")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black, radius: 2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 50)
        }
    }
}

struct ErrorOverlay: View {
    let error: Error
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text("AR Error")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Dismiss") {
                    onDismiss()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .padding()
            
            Spacer()
        }
    }
}

#Preview {
    let roomState = RoomState()
    let multipeer = MultipeerService()
    return ARCaptionView()
        .environmentObject(roomState)
        .environmentObject(multipeer)
}
