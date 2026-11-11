import Combine
import CoreLocation
import Foundation
import extendedSyntax
import OSLog
import SwiftUI
import GameCenterKit
import ActivityKit
import Supabase

@MainActor
class SupabaseGameManager: ObservableObject {
    static let shared = SupabaseGameManager()
    let session = ContentViewModel.shared.session
    
    // Supabase Realtime Channel
    private var channel: RealtimeChannelV2?
    
    // Aktive Verbindungs-Daten
    @Published var connectedPeers: [String] = []
    
    @Published var isHosting = false
    @Published var isScanning = false
    @Published var gameState: GameState = .waiting
    @Published var gameMode: Int = 0
    
    @Published var peerLocations: [String: CLLocationCoordinate2D] = [:]
    @Published var syncedZombies: [UUID: CLLocationCoordinate2D] = [:]
    @Published var targetLocation: CLLocationCoordinate2D?
    
    @Published var health = 100.0
    @Published var lastPing: Double = 0
    @Published var lastPingReceivedAt: Date = Date()
    @Published var closestZombieDistance: Double?
    @Published var fullyConnected: Bool = false
    @Published var localItems: [LocalItem] = []
    
    private var lastBroadcastedLocation: CLLocationCoordinate2D?
    var currentActivity: Activity<SombiesWidgetsAttributes>? = nil
    
    var currentDisplayName: String {
        UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name
    }
    
    init() {}
    
    // MARK: - Room Management (Online via Supabase)
    
    func hostParty(roomId: String, password: String) async {
        stopAll()
        isHosting = true
        
        guard validateRoomInput(roomCode: roomId, password: password) else {
            stopAll()
            print("Ungültiger Code")
            return
        }
        
        do {
            let roomUUID: UUID = try await session
                .rpc("game_create_room_v1", params: [
                    "p_room_code": AnyJSON.string(roomId),
                    "p_password": AnyJSON.string(password)
                ])
                .execute()
                .value
            print("Erfolgreich Raum-Code \(AnyJSON.string(roomId)) erstellt, beitreten...")
            await joinChannel(roomUUID: roomUUID)
            print("Erfolgreich Raum-Code \(AnyJSON.string(roomId)) beigetreten")
        } catch {
            print("Fehler beim Erstellen des Raums: \(error)")
            stopAll()
        }
    }
    
    func joinParty(roomId: String, password: String) async {
        stopAll()
        isScanning = true
        
        guard validateRoomInput(roomCode: roomId, password: password) else {
            stopAll()
            return
        }
        
        do {
            let roomUUID: UUID? = try await session
                .rpc("game_join_room_v1", params: [
                    "p_room_code": AnyJSON.string(roomId),
                    "p_password": AnyJSON.string(password)
                ])
                .execute()
                .value
            print("Erfolgreich Raum-Code \(AnyJSON.string(roomId)) beigetreten")
            guard let roomUUID = roomUUID else {
                print("Raumbeitritt fehlgeschlagen: Code/Passwort ungültig, Raum abgelaufen oder Versuchslimit erreicht.")
                stopAll()
                return
            }
            
            await joinChannel(roomUUID: roomUUID)
        } catch {
            print("Fehler beim Beitreten des Raums: \(error)")
            stopAll()
        }
    }
    
    private func validateRoomInput(roomCode: String, password: String) -> Bool {
        let roomCodeRegex = "^[A-Za-z0-9-]{4,32}$"
        let isRoomCodeValid = roomCode.range(of: roomCodeRegex, options: .regularExpression) != nil
        let isPasswordValid = (8...128).contains(password.count)
        return isRoomCodeValid && isPasswordValid
    }
    
    private func joinChannel(roomUUID: UUID) async {
        let topic = "game:room:\(roomUUID.uuidString.lowercased())"
        let channel = session.channel(topic) {
            $0.broadcast.acknowledgeBroadcasts = true
        }
        self.channel = channel
        
        // 1. Broadcast Stream aufsetzen (VOR subscribe)
        let stream = channel.broadcastStream(event: "game_signal")
        Task { @MainActor in
            for await message in stream {
                do {
                    let container = try message.decode(as: GameSignalContainer.self)
                    print("Signal empfangen: \(container.signal)")
                    self.handleIncomingSignal(container.signal)
                } catch {
                    print("Signal-Dekodierungsfehler: \(error)")
                }
            }
        }
        
        // 2. Presence Listener aufsetzen (VOR subscribe)
        let presenceStream = channel.presenceChange()
        Task { @MainActor in
            for await presenceAction in presenceStream {
                // Verarbeitungs-Logik für beitretende Spieler
                for (_, presence) in presenceAction.joins {
                    if let jsonValue = presence.state["username"],
                       case .string(let username) = jsonValue {
                        // Sich selbst filtern, nur fremde Spieler aufnehmen
                        if username != self.currentDisplayName && !self.connectedPeers.contains(username) {
                            self.connectedPeers.append(username)
                        }
                    }
                }
                
                // Verarbeitungs-Logik für verlassende Spieler
                for (_, presence) in presenceAction.leaves {
                    if let jsonValue = presence.state["username"],
                       case .string(let username) = jsonValue {
                        self.connectedPeers.removeAll { $0 == username }
                    }
                }
                
                // Verbindungsstatus aktualisieren
                if self.isHosting {
                    self.fullyConnected = !self.connectedPeers.isEmpty
                }
            }
        }
        
        // 3. Channel abonnieren
        do {
            try await channel.subscribeWithError()
        } catch {
            print("Fehler beim Abonnieren des Kanals: \(error)")
        }
        
        // 4. Eigene Presence tracken
        try? await channel.track(["username": currentDisplayName])
        
        self.isScanning = false
        
        // Sobald wir dem Channel beigetreten sind, gilt die Verbindung als hergestellt
        self.fullyConnected = true
    }


    // MARK: - Networking / Signal Delivery (Korrektur: broadcast)

    func sendSignal(_ signal: GameSignal, reliable: Bool = true) {
        guard let channel = channel else { return }
        Task {
            do {
                try await channel.broadcast(
                    event: "game_signal",
                    message: GameSignalContainer(signal: signal)
                )
            } catch {
                print("Fehler beim Senden des Signals (\(signal)): \(error)")
            }
        }
    }

    
    private func handleIncomingSignal(_ signal: GameSignal) {
        switch signal {
        case .playerLocation(let id, let lat, let lon):
            guard id != currentDisplayName else { return }
            self.peerLocations[id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
            if action == .leave { self.leaveParty() }
        }
    }

    func broadcastLocation(_ coord: CLLocationCoordinate2D, spd: Double) {
        if let last = lastBroadcastedLocation {
            let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist < 1.0 { return }
        }
        lastBroadcastedLocation = coord
        sendSignal(.playerLocation(id: self.currentDisplayName, lat: coord.latitude, lon: coord.longitude), reliable: false)
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
        stopAll()
    }
    
    func terminateParty() {
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
        stopAll()
    }
    
    func stopAll() {
        if let channel = channel {
            Task { await session.removeChannel(channel) }
        }
        self.channel = nil
        self.isHosting = false
        self.isScanning = false
        self.fullyConnected = false
        self.peerLocations.removeAll()
        self.connectedPeers.removeAll()
    }

    // MARK: - Game Logic & State Management
    
    func triggerGameOver() {
        gameState = .gameOver
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
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
    }
    
    func calculateClosestZombieDistance(from myLocation: CLLocationCoordinate2D) -> Double? {
        guard gameState == .active, !syncedZombies.isEmpty else {
            self.closestZombieDistance = nil
            return nil
        }
        
        let myLoc = CLLocation(latitude: myLocation.latitude, longitude: myLocation.longitude)
        var shortestDistance: Double = .infinity
        
        for (_, zombieCoord) in syncedZombies {
            let zLoc = CLLocation(latitude: zombieCoord.latitude, longitude: zombieCoord.longitude)
            let distance = myLoc.distance(from: zLoc)
            
            if distance < shortestDistance {
                shortestDistance = distance
            }
        }
        
        if shortestDistance == .infinity {
            self.closestZombieDistance = nil
            return nil
        }
        
        self.closestZombieDistance = shortestDistance
        return shortestDistance
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

    // MARK: - Live Activity Support
    
    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SombiesWidgetsAttributes(gameName: "Zombie Jagd")
        let initialState = SombiesWidgetsAttributes.ContentState(ping: Int(lastPing), health: self.health)
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            self.currentActivity = activity
        } catch {
            print("Fehler beim Starten der Live-Aktivität: \(error.localizedDescription)")
        }
    }

    func updateLiveActivity(statusMessage: String, showAlert: Bool = false) {
        guard let activity = currentActivity else { return }
        var alertConfig: AlertConfiguration? = nil
        
        if showAlert {
            alertConfig = AlertConfiguration(
                title: "Zombie-Angriff!",
                body: "Ein Zombie hat dich erwischt! Lauf schneller!",
                sound: .default
            )
        }
        
        let contentState = SombiesWidgetsAttributes.ContentState(ping: Int(self.lastPing), health: self.health)
        let staleDate = Date.now + 15
        
        Task { @MainActor in
            await activity.update(
                ActivityContent<SombiesWidgetsAttributes.ContentState>(
                    state: contentState,
                    staleDate: staleDate,
                    relevanceScore: showAlert ? 100 : 50
                ),
                alertConfiguration: alertConfig
            )
        }
    }

    func endLiveActivity(finalMessage: String) {
        guard let activity = currentActivity else { return }
        let finalContent = SombiesWidgetsAttributes.ContentState(ping: 0, health: self.health)
        
        Task { @MainActor in
            await activity.end(ActivityContent(state: finalContent, staleDate: nil), dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
    }
}
