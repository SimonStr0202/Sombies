import ActivityKit
import Foundation
import OSLog
import os

@MainActor
class ZombieActivityManager {
    static let shared = ZombieActivityManager()
    private var currentActivity: Activity<SombiesWidgetsAttributes>? = nil
    func startActivity(initialDistance: Int, initialPing: Int) {
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities sind deaktiviert.")
            return
        }
        
        let attributes = SombiesWidgetsAttributes(gameName: "Sombies Hunt")
        let initialState = SombiesWidgetsAttributes.ContentState(
            distance: initialDistance,
            statusText: "Suche Zombies...",
            ping: initialPing
        )
        
        let content = ActivityContent(state: initialState, staleDate: nil)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("Live Activity gestartet: \(currentActivity?.id ?? "Unbekannt")")
        } catch {
            print("Fehler beim Starten der Live Activity: \(error.localizedDescription)")
        }
    }
    
    func update(distance: Double, ping: Int) {
        Task { @MainActor in
            let distInt = Int(distance)
            let status = distInt < 15 ? "LAUF UM DEIN LEBEN!" : "Zombies in Sichtweite"

            let updatedState = SombiesWidgetsAttributes.ContentState(
                distance: distInt,
                statusText: status,
                ping: ping
            )

            let content = ActivityContent(state: updatedState, staleDate: nil)
            await currentActivity?.update(content)
        }
    }
    
    func stopActivity() {
        Task { @MainActor in
            for activity in Activity<SombiesWidgetsAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
            print("Live Activity gestoppt.")
        }
    }
}
