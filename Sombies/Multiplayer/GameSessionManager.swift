import Foundation
import CoreLocation
import Combine
import MultipeerConnectivity

enum NetworkMode: String, Codable {
    case bluetooth
    case supabase
}

@MainActor
class GameSessionManager: ObservableObject {
    static let shared = GameSessionManager()
    
    @Published var selectedMode: NetworkMode = .supabase
    
    // Greift auf die jeweilige Instanz zu
    var bluetooth: BluetoothManager { BluetoothManager.shared }
    var supabase: SupabaseGameManager { SupabaseGameManager.shared }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Leitet Änderungen der Unter-Manager an SwiftUI weiter
        bluetooth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
            
        supabase.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    // MARK: - Unified State Properties
    
    var isHosting: Bool {
        get { selectedMode == .bluetooth ? bluetooth.isHosting : supabase.isHosting }
        set {
            if selectedMode == .bluetooth { bluetooth.isHosting = newValue }
            else { supabase.isHosting = newValue }
        }
    }
    
    var isScanning: Bool {
        selectedMode == .bluetooth ? bluetooth.isScanning : supabase.isScanning
    }
    
    var gameState: GameState {
        get { selectedMode == .bluetooth ? bluetooth.gameState : supabase.gameState }
        set {
            if selectedMode == .bluetooth { bluetooth.gameState = newValue }
            else { supabase.gameState = newValue }
        }
    }
    
    var gameMode: Int {
        get { selectedMode == .bluetooth ? bluetooth.gameMode : supabase.gameMode }
        set {
            if selectedMode == .bluetooth { bluetooth.gameMode = newValue }
            else { supabase.gameMode = newValue }
        }
    }
    
    var fullyConnected: Bool {
        selectedMode == .bluetooth ? bluetooth.fullyConnected : supabase.fullyConnected
    }
    
    var connectedPlayerNames: [String] {
        if selectedMode == .bluetooth {
            return bluetooth.connectedPeers.map { $0.displayName }
        } else {
            return supabase.connectedPeers
        }
    }
    
    var peerLocationsList: [CLLocationCoordinate2D] {
        if selectedMode == .bluetooth {
            return Array(bluetooth.peerLocations.values)
        } else {
            return Array(supabase.peerLocations.values)
        }
    }
    
    var peerDisplayLocations: [(id: String, coordinate: CLLocationCoordinate2D)] {
        if selectedMode == .bluetooth {
            return bluetooth.peerLocations.map { (id: $0.key.displayName, coordinate: $0.value) }
        } else {
            return supabase.peerLocations.map { (id: $0.key, coordinate: $0.value) }
        }
    }
    
    var syncedZombies: [UUID: CLLocationCoordinate2D] {
        selectedMode == .bluetooth ? bluetooth.syncedZombies : supabase.syncedZombies
    }
    
    var targetLocation: CLLocationCoordinate2D? {
        selectedMode == .bluetooth ? bluetooth.targetLocation : supabase.targetLocation
    }
    
    var health: Double {
        get { selectedMode == .bluetooth ? bluetooth.health : supabase.health }
        set {
            if selectedMode == .bluetooth { bluetooth.health = newValue }
            else { supabase.health = newValue }
        }
    }
    
    var lastPing: Double {
        selectedMode == .bluetooth ? bluetooth.lastPing : supabase.lastPing
    }
    
    var lastPingReceivedAt: Date {
        selectedMode == .bluetooth ? bluetooth.lastPingReceivedAt : supabase.lastPingReceivedAt
    }
    
    var closestZombieDistance: Double? {
        selectedMode == .bluetooth ? bluetooth.closestZombieDistance : supabase.closestZombieDistance
    }
    
    var localItems: [LocalItem] {
        selectedMode == .bluetooth ? bluetooth.localItems : supabase.localItems
    }
    
    // MARK: - Unified Interfacing
    
    func hostParty(roomId: String, password: String) async {
        switch selectedMode {
        case .bluetooth:
            bluetooth.hostParty()
        case .supabase:
            await supabase.hostParty(roomId: roomId, password: password)
        }
    }
    
    func joinParty(roomId: String, password: String) async {
        switch selectedMode {
        case .bluetooth:
            bluetooth.lookForParties()
        case .supabase:
            await supabase.joinParty(roomId: roomId, password: password)
        }
    }
    
    func broadcastLocation(_ coord: CLLocationCoordinate2D, spd: Double) {
        switch selectedMode {
        case .bluetooth:
            bluetooth.broadcastLocation(coord, spd: spd)
        case .supabase:
            supabase.broadcastLocation(coord, spd: spd)
        }
    }
    
    func startGame(mode: Int) {
        switch selectedMode {
        case .bluetooth: bluetooth.startGame(mode: mode)
        case .supabase: supabase.startGame(mode: mode)
        }
    }
    
    func setExtractionPoint(near coordinate: CLLocationCoordinate2D) {
        switch selectedMode {
        case .bluetooth: bluetooth.setExtractionPoint(near: coordinate)
        case .supabase: supabase.setExtractionPoint(near: coordinate)
        }
    }
    
    func togglePause() {
        switch selectedMode {
        case .bluetooth: bluetooth.togglePause()
        case .supabase: supabase.togglePause()
        }
    }
    
    func resumeGame() {
        switch selectedMode {
        case .bluetooth: bluetooth.resumeGame()
        case .supabase: supabase.resumeGame()
        }
    }
    
    func triggerGameOver() {
        switch selectedMode {
        case .bluetooth: bluetooth.triggerGameOver()
        case .supabase: supabase.triggerGameOver()
        }
    }
    
    func sendPing() {
        switch selectedMode {
        case .bluetooth: bluetooth.sendPing()
        case .supabase: supabase.sendPing()
        }
    }
    
    func checkItems(myLocation: CLLocationCoordinate2D) {
        switch selectedMode {
        case .bluetooth: bluetooth.checkItems(myLocation: myLocation)
        case .supabase: supabase.checkItems(myLocation: myLocation)
        }
    }
    
    func checkWinCondition(myLocation: CLLocationCoordinate2D) {
        switch selectedMode {
        case .bluetooth: bluetooth.checkWinCondition(myLocation: myLocation)
        case .supabase: supabase.checkWinCondition(myLocation: myLocation)
        }
    }
    
    func checkZombieCollisions(myLocation: CLLocationCoordinate2D) {
        switch selectedMode {
        case .bluetooth: bluetooth.checkZombieCollisions(myLocation: myLocation)
        case .supabase: supabase.checkZombieCollisions(myLocation: myLocation)
        }
    }
    
    func updateZombieAI(hostLocation: CLLocationCoordinate2D, multiplier: Double) {
        switch selectedMode {
        case .bluetooth: bluetooth.updateZombieAI(hostLocation: hostLocation, multiplier: multiplier)
        case .supabase: supabase.updateZombieAI(hostLocation: hostLocation, multiplier: multiplier)
        }
    }
    
    func broadcastZombieSpawn(id: UUID, coord: CLLocationCoordinate2D) {
        switch selectedMode {
        case .bluetooth: bluetooth.broadcastZombieSpawn(id: id, coord: coord)
        case .supabase: supabase.broadcastZombieSpawn(id: id, coord: coord)
        }
    }
    
    func leaveParty() {
        switch selectedMode {
        case .bluetooth:
            bluetooth.leaveParty()
        case .supabase:
            supabase.leaveParty()
        }
    }
    
    func stopAll() {
        switch selectedMode {
        case .bluetooth: bluetooth.stopAll()
        case .supabase: supabase.stopAll()
        }
    }
    
    func terminateParty() {
        switch selectedMode {
        case .bluetooth: bluetooth.terminateParty()
        case .supabase: supabase.terminateParty()
        }
    }
    
    func startLiveActivity() {
        switch selectedMode {
        case .bluetooth: bluetooth.startLiveActivity()
        case .supabase: supabase.startLiveActivity()
        }
    }
    
    func updateLiveActivity(statusMessage: String, showAlert: Bool = false) {
        switch selectedMode {
        case .bluetooth: bluetooth.updateLiveActivity(statusMessage: statusMessage, showAlert: showAlert)
        case .supabase: supabase.updateLiveActivity(statusMessage: statusMessage, showAlert: showAlert)
        }
    }
    
    func endLiveActivity(finalMessage: String) {
        switch selectedMode {
        case .bluetooth: bluetooth.endLiveActivity(finalMessage: finalMessage)
        case .supabase: supabase.endLiveActivity(finalMessage: finalMessage)
        }
    }
}
