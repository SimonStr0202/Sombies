import Combine
import CoreLocation
import Foundation
import MultipeerConnectivity
import extendedSyntax
import OSLog
import SwiftUI
import GameCenterKit

enum GameSignal: Codable {
    case playerLocation(id: String, lat: Double, lon: Double)
    case zombieSpawned(id: UUID, lat: Double, lon: Double)
    case zombieKilled(id: UUID)
    case gameStateChanged(GameState, mode: Int)
    case setTargetLocation(lat: Double, lon: Double)
    case partyAction(action: PartyAction)
    case ping(t: TimeInterval)
}

enum PartyAction: Codable {
    case join, leave, start
}

enum GameState: String, Codable {
    case waiting, active, paused, gameOver, win
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()
    private let serviceType = "sombies-hunt"
    var currentPeerID: MCPeerID {
        let currentName = UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name
        
        if let data = UserDefaults.standard.data(forKey: "savedPeerID"),
           let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            
            if decoded.displayName == currentName {
                return decoded
            }
        }
        
        let newID = MCPeerID(displayName: currentName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: newID, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "savedPeerID")
        }
        return newID
    }
    
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    
    @Published var session: MCSession
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availablePeers: [MCPeerID] = []
    
    @Published var isHosting = false
    @Published var isScanning = false
    @Published var gameState: GameState = .waiting
    @Published var gameMode: Int = 0
    
    @Published var peerLocations: [MCPeerID: CLLocationCoordinate2D] = [:]
    @Published var syncedZombies: [UUID: CLLocationCoordinate2D] = [:]
    @Published var targetLocation: CLLocationCoordinate2D?
    
    @Published var health = 100.0
    @Published var lastPing: Double = 0
    @Published var lastPingReceivedAt: Date = Date()
    @Published var closestZombieDistance: Double?
    @Published var fullyConnected: Bool = false
    @Published var localItems: [LocalItem] = []
    
    private var lastBroadcastedLocation: CLLocationCoordinate2D?
    
    override init() {
        let initialName = UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name
        let initialPeerID = MCPeerID(displayName: initialName)
        self.session = MCSession(peer: initialPeerID, securityIdentity: nil, encryptionPreference: .none)
        
        super.init()
        
        self.session = MCSession(peer: self.currentPeerID, securityIdentity: nil, encryptionPreference: .none)
        self.session.delegate = self
    }
    func sendSignal(_ signal: GameSignal, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(signal)
            try session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            Logger.network.error("Sende-Fehler: \(error.localizedDescription)")
        }
    }
    
    func broadcastLocation(_ coord: CLLocationCoordinate2D, spd: Double) {
        if let last = lastBroadcastedLocation {
            let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist < 1.0 { return }
        }
        lastBroadcastedLocation = coord
        sendSignal(.playerLocation(id: self.currentPeerID.displayName, lat: coord.latitude, lon: coord.longitude), reliable: false)
        if spd > 3 {
            self.resumeGame()
        }
    }
    
    func broadcastZombieSpawn(id: UUID, coord: CLLocationCoordinate2D) {
        if !syncedZombies.keys.contains(id) {
            syncedZombies[id] = coord
        }
        sendSignal(.zombieSpawned(id: id, lat: coord.latitude, lon: coord.longitude))
    }
    
    func sendPing() {
        sendSignal(.ping(t: Date().timeIntervalSince1970), reliable: false)
    }
    func leaveParty() {
        sendSignal(.partyAction(action: .leave))
        session.disconnect()
        stopAll()
    }
    
    func terminateParty() {
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
        session.disconnect()
        stopAll()
    }
    
    func triggerGameOver() {
        gameState = .gameOver
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
    }
    func hostParty() {
        stopAll()
        isHosting = true
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: self.currentPeerID, discoveryInfo: nil, serviceType: serviceType)
        serviceAdvertiser?.delegate = self
        serviceAdvertiser?.startAdvertisingPeer()
    }
    
    func lookForParties() {
        stopAll()
        session.disconnect()
        isScanning = true
        availablePeers.removeAll()
        serviceBrowser = MCNearbyServiceBrowser(peer: self.currentPeerID, serviceType: serviceType)
        serviceBrowser?.delegate = self
        serviceBrowser?.startBrowsingForPeers()
    }
    
    func stopAll() {
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceBrowser?.stopBrowsingForPeers()
        isHosting = false
        isScanning = false
    }
    
    func invitePeer(_ peerID: MCPeerID) {
        serviceBrowser?.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    func checkWinCondition(myLocation: CLLocationCoordinate2D) {
        guard let target = targetLocation, gameState == .active else { return }
        let dist = CLLocation(latitude: myLocation.latitude, longitude: myLocation.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        
        if dist < 15 {
            gameState = .win
            sendSignal(.gameStateChanged(.win, mode: gameMode))
        }
    }
    
    func checkItems(myLocation: CLLocationCoordinate2D) {
        let myLoc = CLLocation(latitude: myLocation.latitude, longitude: myLocation.longitude)
        for (index, item) in localItems.enumerated() {
            let itemLoc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
            let distance = myLoc.distance(from: itemLoc)
            if distance < 10 {
                applyItemEffect(item.type)
                localItems.remove(at: index)
                break
            }
        }
    }

    private func applyItemEffect(_ type: ItemType) {
        switch type {
        case .medkit:
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "medkits") + 1, forKey: "medkits")
        case .navigator:
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "navigators") + 1, forKey: "navigators")
        case .cash:
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "Coins") + Int.random(in: 3...7), forKey: "Coins")
        }
    }
    
    func checkZombieCollisions(myLocation: CLLocationCoordinate2D) {
        guard gameState == .active else { return }
        let myLoc = CLLocation(latitude: myLocation.latitude, longitude: myLocation.longitude)
        var minDistance = Double.infinity
        let spd = LocationManager.shared.speedInKmh
        
        for (_, coord) in syncedZombies {
            let zLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let d = myLoc.distance(from: zLoc)
            
            if d < minDistance { minDistance = d }
            
            if d < 5 {
                health = Math.clamp(health - 5, min: 0, max: 100)
                if health <= 0 {
                    triggerGameOver()
                }
                break
            }
            
            if d < 7 && d > 5 && spd > 8 {
                Task {
                    do {
                        try? await GameCenterKit.shared.submitAchievement(identifier: "Sombies.Achievements.PowerShot", percent: 100, showsCompletionBanner: true)
                    }
                }
            }
        }
        closestZombieDistance = minDistance == .infinity ? nil : minDistance
    }
    
    func updateZombieAI(hostLocation: CLLocationCoordinate2D, multiplier: Double) {
        guard isHosting, gameState == .active else { return }
        var allPlayerLocations = Array(peerLocations.values)
        allPlayerLocations.append(hostLocation)
        
        for (id, coord) in syncedZombies {
            let closestPlayer = allPlayerLocations.min(by: {
                let distA = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                let distB = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
                return distA < distB
            })
            
            if let target = closestPlayer {
                let moveDistance = 3 * multiplier
                let newCoord = coord.moveTowards(target: target, meters: moveDistance)
                syncedZombies[id] = newCoord
                broadcastZombieSpawn(id: id, coord: newCoord)
            }
        }
    }
    
    func startGame(mode: Int) {
        self.gameState = .active
        self.gameMode = mode
        self.health = 100.0
        self.syncedZombies.removeAll()
        sendSignal(.gameStateChanged(.active, mode: mode))
    }
    
    func setExtractionPoint(near coordinate: CLLocationCoordinate2D) {
        self.targetLocation = coordinate
        sendSignal(.setTargetLocation(lat: coordinate.latitude, lon: coordinate.longitude))
        if let target = self.targetLocation {
            let seed = UInt64(abs(target.latitude * 100000) + abs(target.longitude * 100000))
            self.generateLocalItems(seed: seed, center: target)
        }
    }
    func togglePause() {
        if gameState == .active {
            gameState = .paused
            sendSignal(.gameStateChanged(.paused, mode: gameMode))
        } else if gameState == .paused {
            resumeGame()
        }
    }

    func resumeGame() {
        guard gameState == .paused else { return }
        gameState = .active
        sendSignal(.gameStateChanged(.active, mode: gameMode))
    }
    func generateLocalItems(seed: UInt64, center: CLLocationCoordinate2D) {
        var generator = SeededGenerator(seed: seed)
        var items: [LocalItem] = []
        
        for _ in 0..<30 {
            let randomDist = Double.random(in: 10...1000, using: &generator)
            let randomBearing = Double.random(in: 0..<360, using: &generator) * .pi / 180
            
            let earthRadius: Double = 6_378_137
            let distRatio = randomDist / earthRadius
            let lat1 = center.latitude * .pi / 180
            let lon1 = center.longitude * .pi / 180
            
            let lat2 = asin(sin(lat1) * cos(distRatio) + cos(lat1) * sin(distRatio) * cos(randomBearing))
            let lon2 = lon1 + atan2(sin(randomBearing) * sin(distRatio) * cos(lat1), cos(distRatio) - sin(lat1) * sin(lat2))
            
            let coord = CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
            let type = ItemType.allCases.randomElement(using: &generator) ?? .medkit
            
            items.append(LocalItem(type: type, coordinate: coord))
        }
        
        DispatchQueue.main.async {
            self.localItems = items
        }
    }
}

extension BluetoothManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.connectedPeers = session.connectedPeers
            if state == .notConnected && self.gameState == .active {
                if self.isHosting { self.hostParty() } else { self.lookForParties() }
            }
            if state == .connected {
                self.fullyConnected = true
            } else {
                self.fullyConnected = false
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let signal = try? JSONDecoder().decode(GameSignal.self, from: data) {
            DispatchQueue.main.async {
                switch signal {
                case .playerLocation(_, let lat, let lon):
                    self.peerLocations[peerID] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                case .zombieSpawned(let id, let lat, let lon):
                    self.syncedZombies[id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                case .zombieKilled(let id):
                    self.syncedZombies.removeValue(forKey: id)
                case .gameStateChanged(let state, let mode):
                    self.gameState = state
                    self.gameMode = mode
                case .setTargetLocation(let lat, let lon):
                    self.targetLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    if let target = self.targetLocation {
                        let seed = UInt64(abs(target.latitude * 100000) + abs(target.longitude * 100000))
                        self.generateLocalItems(seed: seed, center: target)
                    }
                case .ping(let t):
                    self.lastPing = (Date().timeIntervalSince1970 - t) * 1000
                    self.lastPingReceivedAt = Date()
                case .partyAction(let action):
                    if action == .leave { self.session.disconnect() }
                }
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension BluetoothManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            invitationHandler(true, self.session)
        }
    }
}

extension BluetoothManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if !availablePeers.contains(peerID) {
            self.objectWillChange.send()
            availablePeers.append(peerID)
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser) {}
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        availablePeers.removeAll { $0 == peerID }
    }
}

extension CLLocationCoordinate2D {
    func moveTowards(target: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6_378_137
        let lat1 = self.latitude * .pi / 180
        let lon1 = self.longitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let lon2 = target.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)
        let distRatio = meters / earthRadius
        let newLat = asin(sin(lat1) * cos(distRatio) + cos(lat1) * sin(distRatio) * cos(bearing))
        let newLon = lon1 + atan2(sin(bearing) * sin(distRatio) * cos(lat1), cos(distRatio) - sin(lat1) * sin(newLat))
        
        return CLLocationCoordinate2D(latitude: newLat * 180 / .pi, longitude: newLon * 180 / .pi)
    }
    func shiftedBy(meters: Double) -> CLLocationCoordinate2D {
        let bearing = Double.random(in: 0..<360) * .pi / 180
        
        let earthRadius: Double = 6_378_137
        let distRatio = meters / earthRadius
        
        let lat1 = self.latitude * .pi / 180
        let lon1 = self.longitude * .pi / 180
        
        let lat2 = asin(sin(lat1) * cos(distRatio) + cos(lat1) * sin(distRatio) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(distRatio) * cos(lat1), cos(distRatio) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

enum ItemType: CaseIterable {
    case medkit, cash, navigator
}

struct LocalItem: Identifiable {
    let id = UUID()
    let type: ItemType
    let coordinate: CLLocationCoordinate2D
}
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}
