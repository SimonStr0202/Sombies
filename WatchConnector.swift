import Foundation
import WatchConnectivity
import Combine

class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnector()
    
    @Published var lastReceivedZombieDistance: Double = 0.0
    @Published var isWatchReachable = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    private func updateUI(with context: [String : Any]) {
        DispatchQueue.main.async {
            if let dist = context["dist"] as? Double {
                self.lastReceivedZombieDistance = dist
                print("Watch empfing Distanz: \(dist)")
            }
        }
    }
    func sendZombieUpdate(distance: Double) {
        let session = WCSession.default
        if session.isReachable {
            try? session.updateApplicationContext(["dist": distance])
        }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            if let dist = applicationContext["dist"] as? Double {
                self.lastReceivedZombieDistance = dist
            }
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            updateUI(with: session.receivedApplicationContext)
        }
        
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
