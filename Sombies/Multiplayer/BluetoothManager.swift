import Combine
import CoreLocation
import Foundation
import CoreBluetooth
import extendedSyntax
import OSLog
import SwiftUI
import GameCenterKit
import ActivityKit

struct GamePeer: Hashable, Identifiable {
    let id: UUID
    let displayName: String
}

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
    private let serviceUUID = CBUUID(string: "A7B10001-5A4B-4D4F-9C2A-534F4D424945")
    private let writeUUID = CBUUID(string: "A7B10002-5A4B-4D4F-9C2A-534F4D424945")
    private let notifyUUID = CBUUID(string: "A7B10003-5A4B-4D4F-9C2A-534F4D424945")
    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var subscribedCentrals: [UUID: CBCentral] = [:]
    private var peerNames: [UUID: String] = [:]
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var heartbeatTimer: Timer?
    private var lastBroadcastedLocation: CLLocationCoordinate2D?
    var currentActivity: Activity<SombiesWidgetsAttributes>? = nil

    var currentPeerID: GamePeer {
        let name = UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name
        return GamePeer(id: UUID(uuidString: UserDefaults.standard.string(forKey: "sombiesBLEPeerID") ?? "") ?? {
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: "sombiesBLEPeerID")
            return id
        }(), displayName: name)
    }

    @Published var connectedPeers: [GamePeer] = []
    @Published var availablePeers: [GamePeer] = []

    @Published var isHosting = false
    @Published var isScanning = false
    @Published var gameState: GameState = .waiting
    @Published var gameMode: Int = 0
    
    @Published var peerLocations: [GamePeer: CLLocationCoordinate2D] = [:]
    @Published var syncedZombies: [UUID: CLLocationCoordinate2D] = [:]
    @Published var targetLocation: CLLocationCoordinate2D?
    
    @Published var health = 100.0
    @Published var lastPing: Double = 0
    @Published var lastPingReceivedAt: Date = Date()
    @Published var closestZombieDistance: Double?
    @Published var fullyConnected: Bool = false
    @Published var localItems: [LocalItem] = []
    
    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = SombiesWidgetsAttributes(gameName: "Zombie Jagd")
        
        let initialState = SombiesWidgetsAttributes.ContentState(
            ping: Int(lastPing),
            health: self.health
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            
            self.currentActivity = activity
            print("Live-Aktivität erfolgreich gestartet ID: \(activity.id)")
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
        
        let contentState = SombiesWidgetsAttributes.ContentState(
            ping: Int(self.lastPing),
            health: self.health
        )
        
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
        
        let finalContent = SombiesWidgetsAttributes.ContentState(
            ping: 0,
            health: self.health
        )
        
        Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalContent, staleDate: nil),
                dismissalPolicy: .immediate
            )
            self.currentActivity = nil
        }
    }
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    private struct Packet: Codable {
        let peerID: UUID
        let displayName: String
        let signal: GameSignal
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.isHosting {
                    self.sendSignal(.ping(t: Date().timeIntervalSince1970), reliable: false)
                } else if self.fullyConnected && Date().timeIntervalSince(self.lastPingReceivedAt) > 8 {
                    self.gameState = .gameOver
                    self.stopAll()
                    self.stopAll()
                }
            }
        }
    }

    func sendSignal(_ signal: GameSignal, reliable: Bool = true) {
        guard let data = try? JSONEncoder().encode(Packet(peerID: currentPeerID.id, displayName: currentPeerID.displayName, signal: signal)) else { return }
        if isHosting {
            guard let characteristic = notifyCharacteristic else { return }
            _ = peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: Array(subscribedCentrals.values))
        } else if let peripheral = discoveredPeripherals.values.first(where: { $0.state == .connected }), let characteristic = writeCharacteristic {
            peripheral.writeValue(data, for: characteristic, type: reliable ? .withResponse : .withoutResponse)
        }
    }

    func broadcastLocation(_ coord: CLLocationCoordinate2D, spd: Double) {
        if let last = lastBroadcastedLocation {
            let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist < 1.0 { return }
        }
        lastBroadcastedLocation = coord
        sendSignal(.playerLocation(id: currentPeerID.displayName, lat: coord.latitude, lon: coord.longitude), reliable: false)
        if spd > 3 { resumeGame() }
    }

    func broadcastZombieSpawn(id: UUID, coord: CLLocationCoordinate2D) {
        if !syncedZombies.keys.contains(id) { syncedZombies[id] = coord }
        sendSignal(.zombieSpawned(id: id, lat: coord.latitude, lon: coord.longitude))
    }

    func sendPing() { sendSignal(.ping(t: Date().timeIntervalSince1970), reliable: false) }

    func leaveParty() {
        sendSignal(.partyAction(action: .leave))
        if isHosting {
            peripheralManager.removeAllServices()
            subscribedCentrals.removeAll()
        } else {
            centralManager.stopScan()
            for peripheral in discoveredPeripherals.values { centralManager.cancelPeripheralConnection(peripheral) }
        }
        stopAll()
    }

    func terminateParty() {
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
        gameState = .gameOver
        leaveParty()
    }

    func triggerGameOver() {
        gameState = .gameOver
        sendSignal(.gameStateChanged(.gameOver, mode: gameMode))
    }

    func hostParty() {
        stopAll()
        isHosting = true
        isScanning = false
        if peripheralManager.state == .poweredOn { configureAndAdvertise() }
        startHeartbeat()
    }

    private func configureAndAdvertise() {
        peripheralManager.removeAllServices()
        let write = CBMutableCharacteristic(type: writeUUID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let notify = CBMutableCharacteristic(type: notifyUUID, properties: [.notify], value: nil, permissions: [.readable])
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [write, notify]
        notifyCharacteristic = notify
        peripheralManager.add(service)
    }

    func lookForParties() {
        stopAll()
        isHosting = false
        isScanning = true
        availablePeers.removeAll()
        discoveredPeripherals.removeAll()
        if centralManager.state == .poweredOn { centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        startHeartbeat()
    }

    func stopAll() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        peripheralManager?.stopAdvertising()
        centralManager?.stopScan()
        isHosting = false
        isScanning = false
    }

    func invitePeer(_ peerID: GamePeer) {
        guard let peripheral = discoveredPeripherals[peerID.id] else { return }
        centralManager.connect(peripheral, options: nil)
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
}

extension BluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Spieler"
        let peer = GamePeer(id: peripheral.identifier, displayName: name)
        if !availablePeers.contains(peer) { availablePeers.append(peer) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        fullyConnected = true
        lastPingReceivedAt = Date()
        if !isHosting {
            let host = GamePeer(id: peripheral.identifier, displayName: peripheral.name ?? "Host")
            connectedPeers = [host]
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if !isHosting && fullyConnected {
            fullyConnected = false
            connectedPeers.removeAll()
            gameState = .gameOver
            stopAll()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == writeUUID { writeCharacteristic = characteristic }
            if characteristic.uuid == notifyUUID { peripheral.setNotifyValue(true, for: characteristic) }
        }
        if let writeCharacteristic {
            let packet = Packet(peerID: currentPeerID.id, displayName: currentPeerID.displayName, signal: .partyAction(action: .join))
            if let data = try? JSONEncoder().encode(packet) { peripheral.writeValue(data, for: writeCharacteristic, type: .withResponse) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        receivePacket(data, from: nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil { fullyConnected = false }
    }
}

extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        guard manager.state == .poweredOn else { return }
        if isHosting { configureAndAdvertise() }
        if isScanning, centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil, isHosting else { return }
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: currentPeerID.displayName])
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard subscribedCentrals.count < 3 || subscribedCentrals[central.identifier] != nil else {
            return
        }
        subscribedCentrals[central.identifier] = central
        peerNames[central.identifier] = peerNames[central.identifier] ?? "Spieler"
        if subscribedCentrals.count >= 3 { manager.stopAdvertising() }
        connectedPeers = subscribedCentrals.keys.map { GamePeer(id: $0, displayName: peerNames[$0] ?? "Spieler") }
        fullyConnected = !connectedPeers.isEmpty
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeValue(forKey: central.identifier)
        peerNames.removeValue(forKey: central.identifier)
        connectedPeers.removeAll { $0.id == central.identifier }
        fullyConnected = !connectedPeers.isEmpty
        if isHosting { manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: currentPeerID.displayName]) }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                receivePacket(data, from: request.central)
            }
            manager.respond(to: request, withResult: .success)
        }
    }
}

private extension BluetoothManager {
    func receivePacket(_ data: Data, from central: CBCentral?) {
        guard let packet = try? JSONDecoder().decode(Packet.self, from: data) else { return }
        if let central {
            peerNames[central.identifier] = packet.displayName
            if !connectedPeers.contains(where: { $0.id == central.identifier }) {
                connectedPeers.append(GamePeer(id: central.identifier, displayName: packet.displayName))
            }
            fullyConnected = true
        }
        DispatchQueue.main.async {
            self.lastPingReceivedAt = Date()
            if central != nil {
                switch packet.signal {
                case .playerLocation, .ping, .partyAction:
                    break
                default:
                    return
                }
            }
            switch packet.signal {
            case .playerLocation(_, let lat, let lon):
                let id = GamePeer(id: packet.peerID, displayName: packet.displayName)
                self.peerLocations[id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if self.isHosting, let characteristic = self.notifyCharacteristic {
                    _ = self.peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: Array(self.subscribedCentrals.values))
                }
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
                if action == .leave, let central {
                    self.subscribedCentrals.removeValue(forKey: central.identifier)
                    self.connectedPeers.removeAll { $0.id == central.identifier }
                    self.peerLocations.removeValue(forKey: GamePeer(id: packet.peerID, displayName: packet.displayName))
                }
            }
        }
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

