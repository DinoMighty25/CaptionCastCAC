import Foundation
import UIKit

class HapticManager {
    static let shared = HapticManager()
    private init() {}

    func simpleSuccess() {
        #if targetEnvironment(simulator)
        // Silently skip haptics in simulator to avoid console spam
        return
        #else
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        #if targetEnvironment(simulator)
        // Silently skip haptics in simulator to avoid console spam
        return
        #else
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if targetEnvironment(simulator)
        // Silently skip haptics in simulator to avoid console spam
        return
        #else
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        #endif
    }
}
