import UIKit
import CoreHaptics

class HapticManager {
    static let shared = HapticManager()
    
    private var hapticEngine: CHHapticEngine?
    private var zombieRadarPlayer: CHHapticAdvancedPatternPlayer?
    
    private init() {
        createEngine()
    }
    
    private func createEngine() {
        guard #available(iOS 13.0, *), CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
        } catch {}
    }
    
    func trigger(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    func triggerNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    
    func playRisingAndPloppPattern() {
        guard #available(iOS 13.0, *), CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = hapticEngine else { return }
        
        try? engine.start()
        
        let continuousEvent = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0.0,
            duration: 0.25
        )
        
        let intensityControlPoints = [
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.0, value: 0.0),
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.25, value: 1.0)
        ]
        
        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: intensityControlPoints,
            relativeTime: 0.0
        )
        
        let transientEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ],
            relativeTime: 0.3
        )
        
        do {
            let pattern = try CHHapticPattern(
                events: [continuousEvent, transientEvent],
                parameterCurves: [intensityCurve]
            )
            
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {}
    }
}

