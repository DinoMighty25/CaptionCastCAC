//
//  ARCaptionService.swift
//  captionapp5
//
//
import Foundation
import ARKit
import Vision
import SwiftUI
import AVFoundation
import Combine
//class for AR caption feature
class ARCaptionService: NSObject, ObservableObject {
    //configure AR
    var session = ARSession()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest
    
    
    @Published var detectedFaces: [DetectedFace] = []
    @Published var activeCaptions: [ARCaption] = []
    @Published private(set) var liveCaptionsByUser: [UUID: ARCaption] = [:]
    @Published private(set) var finalCaptionsByUser: [UUID: ARCaption] = [:]
    @Published var isSessionRunning = false
    @Published var error: Error?
    
    private let maxDetectedFaces = Constants.maxDetectedFaces
    private let captionDisplayDuration = Constants.captionDisplayDuration
    
    //variables for face tracking
    private var faceObservations: [UUID: VNFaceObservation] = [:]
    private var lastFaceUpdateTime: [UUID: Date] = [:]
    private var lastFacePosition: [UUID: CGRect] = [:]
    private var bindings: [UUID: UUID] = [:]
    
    //determine how strict to make tracking
    private let faceMatchingThreshold: CGFloat = 0.3 //30% of screen before it may be a different face
    private let faceStaleTimeout: TimeInterval = 2.0 //forget faces after 2 seconds of not seeing them
    
    private struct PixelBufferBox: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }
    
    //frame throttling to imporve performance
    private var frameCounter: Int = 0
    private let frameProcessingInterval = 6
    private let visionQueue = DispatchQueue(label: "ARCaptionService.vision")
    private var isProcessingFrame = false
    private let processingLock = NSLock()
    private var droppedFrameCount = 0
    
    //change throttling based on detected face count
    private var adaptiveThrottleInterval: Int {
        let faceCount = detectedFaces.count
        switch faceCount {
        case 0...1: return 5
        case 2...3: return 8
        default: return 12
        }
    }
    
    private var finalRemovalTasks: [UUID: DispatchWorkItem] = [:]

    override init() {
        //initialize face detection request
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        super.init()
        
        setupARSession()
    }
    
    deinit {
        //cleanup
        faceObservations.removeAll()
        lastFaceUpdateTime.removeAll()
        lastFacePosition.removeAll()
        lastSmoothedPositions.removeAll()
        bindings.removeAll()
        finalRemovalTasks.values.forEach { $0.cancel() }
        finalRemovalTasks.removeAll()
    }
    
    //AR session management
    
    private func setupARSession() {
        session.delegate = self
    }
    
    func startARSession() {
        guard !isSessionRunning else {  return }

        if ARFaceTrackingConfiguration.isSupported {
            let configuration = ARFaceTrackingConfiguration()
            configuration.maximumNumberOfTrackedFaces = 1
            configuration.isLightEstimationEnabled = true
            session.run(configuration)
        } else {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.isLightEstimationEnabled = true
            session.run(configuration)
        }

        isSessionRunning = true
    }
    
    func pauseARSession() {
        session.pause()
        isSessionRunning = false
        
        //clear face data
        detectedFaces.removeAll()
        activeCaptions.removeAll()
        faceObservations.removeAll()
        lastFaceUpdateTime.removeAll()
    }
    
    func stopARSession() {
        session.pause()
        isSessionRunning = false
        
        //clear all data
        detectedFaces.removeAll()
        activeCaptions.removeAll()
        faceObservations.removeAll()
        lastFaceUpdateTime.removeAll()
    }
    
    func flipCamera(toFront: Bool) {
        
        session.pause()
        
        if toFront && ARFaceTrackingConfiguration.isSupported {
            //using front camera - front uses face tracking
            let configuration = ARFaceTrackingConfiguration()
            configuration.maximumNumberOfTrackedFaces = 1
            configuration.isLightEstimationEnabled = true
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            //using back camera - back uses world tracking
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.isLightEstimationEnabled = true
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    //caption management
    
    func addOrUpdateCaption(_ message: CaptionMessage, for faceId: UUID? = nil) {
        DispatchQueue.main.async {
            self.updateCaption(message, faceId: faceId)
        }
    }
    
    private func updateCaption(_ message: CaptionMessage, faceId: UUID?) {
        
        var caption = ARCaption(
            id: UUID(),
            message: message,
            faceId: faceId,
            screenPosition: CGPoint(x: 0.5, y: 0.5),
            createdAt: Date(),
            targetPosition: CGPoint(x: 0.5, y: 0.5)
        )
        if let faceId = faceId {
            bindings[faceId] = message.userId
            if let face = detectedFaces.first(where: { $0.id == faceId }) {
                caption.screenPosition = face.screenPosition
                caption.targetPosition = face.screenPosition
            }
        } else if let boundFaceId = bindings.first(where: { $0.value == message.userId })?.key,
                  let face = detectedFaces.first(where: { $0.id == boundFaceId }) {
            caption.faceId = boundFaceId
            caption.screenPosition = face.screenPosition
            caption.targetPosition = face.screenPosition
        } else {
            print("")
        }
        if message.isFinal {
            cancelFinalRemovalTask(for: message.userId)
            finalCaptionsByUser[message.userId] = caption
            liveCaptionsByUser[message.userId] = nil
            scheduleFinalRemoval(for: message.userId)
        } else {
            liveCaptionsByUser[message.userId] = caption
        }
        pruneExpiredFinals()
        rebuildActiveCaptions()
        rebindCaptionIfNeeded(for: message.userId)
    }

    
    
    private func pruneExpiredFinals() {
        let lifetime: TimeInterval = 5.0
        let now = Date()
        finalCaptionsByUser = finalCaptionsByUser.filter { now.timeIntervalSince($0.value.createdAt) < lifetime }
    }

    private func rebuildActiveCaptions() {
        //show captions for assigned faces only
        let locallyAssignedUserIds = Set(bindings.values)
        
        let finalCaptions = finalCaptionsByUser.values.filter { caption in
            locallyAssignedUserIds.contains(caption.message.userId)
        }
        let liveCaptions = liveCaptionsByUser.values.filter { caption in
            locallyAssignedUserIds.contains(caption.message.userId)
        }
        
        activeCaptions = Array(finalCaptions) + Array(liveCaptions)
    }
    
    //other functions to help format captions and manage the AR feature
    private func rebindCaptionIfNeeded(for userId: UUID) {
        guard let faceId = bindings.first(where: { $0.value == userId })?.key else { return }
        if let index = activeCaptions.firstIndex(where: { $0.message.userId == userId }) {
            activeCaptions[index].faceId = faceId
            if let face = detectedFaces.first(where: { $0.id == faceId }) {
                activeCaptions[index].screenPosition = face.screenPosition
                activeCaptions[index].targetPosition = face.screenPosition
            }
        }
    }

    private func scheduleFinalRemoval(for userId: UUID) {
        let lifetime: TimeInterval = 5.0
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.finalCaptionsByUser[userId] = nil
            self.finalRemovalTasks[userId] = nil
            self.rebuildActiveCaptions()
        }
        finalRemovalTasks[userId]?.cancel()
        finalRemovalTasks[userId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: workItem)
    }

    private func cancelFinalRemovalTask(for userId: UUID) {
        finalRemovalTasks[userId]?.cancel()
        finalRemovalTasks[userId] = nil
    }

    private func cancelAllFinalRemovalTasks() {
        finalRemovalTasks.values.forEach { $0.cancel() }
        finalRemovalTasks.removeAll()
    }

    func handleRecordingStarted() {
        liveCaptionsByUser.removeAll()
        pruneExpiredFinals()
        rebuildActiveCaptions()
    }

    func handleRecordingStopped() {
        liveCaptionsByUser.removeAll()
        rebuildActiveCaptions()
    }

    func resetState() {
        liveCaptionsByUser.removeAll()
        finalCaptionsByUser.removeAll()
        bindings.removeAll()
        cancelAllFinalRemovalTasks()
        activeCaptions.removeAll()
    }
    
    func updateCaptionPosition(for faceId: UUID, position: CGPoint) {
        DispatchQueue.main.async {
            for index in self.activeCaptions.indices {
                if self.activeCaptions[index].faceId == faceId {
                    self.activeCaptions[index].targetPosition = position
                }
            }
            self.avoidOverlaps()
            
        }
    }
    
    //get rid of overlapping
    private func avoidOverlaps() {
        let sortedCaptions = activeCaptions.sorted { $0.screenPosition.y < $1.screenPosition.y }
        guard sortedCaptions.count > 1 else { return }
        
        for i in 1..<sortedCaptions.count {
            guard let prevIndex = activeCaptions.firstIndex(where: { $0.id == sortedCaptions[i-1].id }),
                  let currentIndex = activeCaptions.firstIndex(where: { $0.id == sortedCaptions[i].id }) else {
                continue
            }

            let prevCaption = activeCaptions[prevIndex]
            var currentCaption = activeCaptions[currentIndex]
            
            let verticalDistance = abs((prevCaption.targetPosition.y + prevCaption.verticalOffset) - currentCaption.targetPosition.y)
            
            if verticalDistance < 0.1 {
                currentCaption.verticalOffset = prevCaption.verticalOffset + (0.1 - verticalDistance)
                activeCaptions[currentIndex] = currentCaption
            }
        }
    }

    //face tracking and detection
    
    private func cleanupStaleFaceObservations() {
        let now = Date()
        let staleThreshold: TimeInterval = 3.0
        
        let staleIds = lastFaceUpdateTime.filter { now.timeIntervalSince($0.value) > staleThreshold }.map { $0.key }
        
        guard !staleIds.isEmpty else { return }
        
        for id in staleIds {
            faceObservations.removeValue(forKey: id)
            lastFaceUpdateTime.removeValue(forKey: id)
        }
        
        
    }
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try requestHandler.perform([faceDetectionRequest])
            
            guard let observations = faceDetectionRequest.results else { return }
            
            processFaceObservations(observations)
        } catch {
            print("Face detection error: \(error)")
            DispatchQueue.main.async {
                self.error = error
            }
        }
    }
    
    //main face tracking function
    private func processFaceObservations(_ observations: [VNFaceObservation]) {
        var currentFaces: [DetectedFace] = []
        var alreadyMatchedFaces = Set<UUID>()
        let now = Date()
        
        //clear faces not seen after some time
        let oldFaces = lastFaceUpdateTime.filter { now.timeIntervalSince($0.value) > faceStaleTimeout }.map { $0.key }
        for oldFaceId in oldFaces {
            faceObservations.removeValue(forKey: oldFaceId)
            lastFaceUpdateTime.removeValue(forKey: oldFaceId)
            lastFacePosition.removeValue(forKey: oldFaceId)
        }
        
        // Try to match each new detection with a known face
        for observation in observations.prefix(maxDetectedFaces) {
            let boundingBox = observation.boundingBox
            var bestMatchId: UUID?
            var bestDistance: CGFloat = .infinity
            
            // Check all previous faces to find the closest match
            for (previousId, oldPosition) in lastFacePosition {
                if alreadyMatchedFaces.contains(previousId) { continue }
                
                let distance = distanceBetweenBoxes(boundingBox, oldPosition)
                
                if distance < faceMatchingThreshold && distance < bestDistance {
                    bestDistance = distance
                    bestMatchId = previousId
                }
            }
            
            // Use matched ID or make a new one
            let faceId = bestMatchId ?? UUID()
            alreadyMatchedFaces.insert(faceId)
            
            // Remember this face
            faceObservations[faceId] = observation
            lastFaceUpdateTime[faceId] = now
            lastFacePosition[faceId] = boundingBox
            
            // Smooth the position so captions glide instead of jump
            let rawPosition = convertToScreenCoordinates(boundingBox)
            let smoothedPosition = makePositionSmoother(rawPosition, for: faceId)
            
            let detectedFace = DetectedFace(
                id: faceId,
                boundingBox: boundingBox,
                screenPosition: smoothedPosition,
                confidence: observation.confidence,
                detectedAt: now
            )
            
            currentFaces.append(detectedFace)
            updateCaptionPosition(for: faceId, position: smoothedPosition)
        }
        
        // Update the UI
        DispatchQueue.main.async {
            self.detectedFaces = currentFaces
            self.updateAllCaptionPositions()
        }
    }
    
    // Calculate distance between two face boxes to see if they're the same face
    private func distanceBetweenBoxes(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let dx = box1.midX - box2.midX
        let dy = box1.midY - box2.midY
        let dw = box1.width - box2.width
        let dh = box1.height - box2.height
        
        return sqrt(dx*dx + dy*dy + dw*dw*0.5 + dh*dh*0.5)
    }
    
    // Smooth caption movement so they don't jump around
    private var lastSmoothedPositions: [UUID: CGPoint] = [:]
    private let smoothingFactor: CGFloat = 0.3
    
    private func makePositionSmoother(_ newPosition: CGPoint, for faceId: UUID) -> CGPoint {
        guard let lastPosition = lastSmoothedPositions[faceId] else {
            lastSmoothedPositions[faceId] = newPosition
            return newPosition
        }
        
        // Move 30% of the way to new position each frame
        let smoothedX = lastPosition.x + (newPosition.x - lastPosition.x) * smoothingFactor
        let smoothedY = lastPosition.y + (newPosition.y - lastPosition.y) * smoothingFactor
        let smoothed = CGPoint(x: smoothedX, y: smoothedY)
        
        lastSmoothedPositions[faceId] = smoothed
        return smoothed
    }
    
    // Convert face position to caption position
    private func convertToScreenCoordinates(_ boundingBox: CGRect) -> CGPoint {
        let x = boundingBox.midX
        let faceBottom = 1.0 - boundingBox.minY
        let y = faceBottom + 0.08
        
        return CGPoint(x: x, y: y)
    }
    
    //assigning faces and keeping it tracking
    
    func assign(userId: UUID, to faceId: UUID) {
        //un-assign this user from any other face first just in case
        if let oldFaceId = bindings.first(where: { $0.value == userId })?.key {
            bindings.removeValue(forKey: oldFaceId)
        }
        bindings[faceId] = userId
        rebuildActiveCaptions()
        updateAllCaptionPositions()
    }
    
    

    func unassign(faceId: UUID) {
        bindings.removeValue(forKey: faceId)
        rebuildActiveCaptions()
    }

    func userId(for faceId: UUID) -> UUID? {
        return bindings[faceId]
    }

    //method to sync all captions to their bound faces
    func updateAllCaptionPositions() {
        var captionsNeedUpdate = false
        for (userId, _) in liveCaptionsByUser {
            if let faceId = bindings.first(where: { $0.value == userId })?.key,
               let face = detectedFaces.first(where: { $0.id == faceId }) {
                liveCaptionsByUser[userId]?.targetPosition = face.screenPosition
                liveCaptionsByUser[userId]?.faceId = faceId
                captionsNeedUpdate = true
            }
        }
        for (userId, _) in finalCaptionsByUser {
            if let faceId = bindings.first(where: { $0.value == userId })?.key,
               let face = detectedFaces.first(where: { $0.id == faceId }) {
                finalCaptionsByUser[userId]?.targetPosition = face.screenPosition
                finalCaptionsByUser[userId]?.faceId = faceId
                captionsNeedUpdate = true
            }
        }

        if captionsNeedUpdate {
            rebuildActiveCaptions()
            avoidOverlaps()
        }
    }
    
    func associateCaptionWithFace(_ caption: ARCaption, faceId: UUID) {
        DispatchQueue.main.async {
            if let index = self.activeCaptions.firstIndex(where: { $0.id == caption.id }) {
                self.activeCaptions[index].faceId = faceId
                
                //update position if face is currently detected
                if let face = self.detectedFaces.first(where: { $0.id == faceId }) {
                    self.activeCaptions[index].screenPosition = face.screenPosition
                    self.activeCaptions[index].targetPosition = face.screenPosition
                }
            }
        }
    }
    
    func getNearestFace(to point: CGPoint) -> DetectedFace? {
        return detectedFaces.min { face1, face2 in
            let distance1 = distance(from: point, to: face1.screenPosition)
            let distance2 = distance(from: point, to: face2.screenPosition)
            return distance1 < distance2
        }
    }
    
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
}



extension ARCaptionService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        guard frameCounter % frameProcessingInterval == 0 else { return }
        
        processingLock.lock()
        let isProcessing = isProcessingFrame
        processingLock.unlock()
        
        guard !isProcessing else { 
            droppedFrameCount += 1
            return 
        }
        
        processingLock.lock()
        isProcessingFrame = true
        processingLock.unlock()
        
        if frameCounter % 1800 == 0 {
            cleanupStaleFaceObservations()
        }
        
        let buffer = frame.capturedImage
        
        visionQueue.async { [weak self, buffer] in
            defer {
                DispatchQueue.main.async {
                    self?.processingLock.lock()
                    self?.isProcessingFrame = false
                    self?.processingLock.unlock()
                }
            }
            
            autoreleasepool {
                guard let self = self else { return }
                self.processFrame(buffer)
            }
        }
    }

    //debug functions
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed: \(error)")
        DispatchQueue.main.async {
            self.error = error
            self.isSessionRunning = false
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR session was interrupted")
        DispatchQueue.main.async {
            self.isSessionRunning = false
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR session interruption ended")
        DispatchQueue.main.async {
            self.isSessionRunning = true
        }
    }
}

//data models

struct DetectedFace: Identifiable {
    let id: UUID
    let boundingBox: CGRect
    let screenPosition: CGPoint
    let confidence: Float
    let detectedAt: Date
}

struct ARCaption: Identifiable {
    let id: UUID
    var message: CaptionMessage
    var faceId: UUID?
    var screenPosition: CGPoint
    let createdAt: Date
    
   
    var targetPosition: CGPoint
    

    var verticalOffset: CGFloat = 0.0

    var isAssociated: Bool {
        return faceId != nil
    }
    
    var age: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }
}
