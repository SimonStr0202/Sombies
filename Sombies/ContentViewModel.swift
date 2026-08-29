import SwiftUI
import MapKit
import Combine
import HealthKit
import OSLog
import os
import GameKit
import LocalAuthentication
import WidgetKit

@MainActor
class ContentViewModel: ObservableObject {
    static let shared = ContentViewModel()
    var scenePhase: ScenePhase = .active
    var colorScheme: ColorScheme = .light
    let btManager: BluetoothManager
    let locManager: LocationManager
    
    init(btManager: BluetoothManager, locManager: LocationManager) {
        self.btManager = btManager
        self.locManager = locManager
    }

    convenience init() {
        self.init(btManager: BluetoothManager.shared, locManager: LocationManager.shared)
    }
    @Published var context = LAContext()
    @Published var mapPos = MapCameraPosition.userLocation(fallback: .automatic)
    @Published var goalMapPos = MapCameraPosition.userLocation(fallback: .automatic)
    @Published var hostingView = false
    @Published var hostPlayersAmount = 1
    @Published var showCancelHostAlert = false
    @AppStorage("userName") var userName = UIDevice.current.name
    @Namespace var presentationCoordinator
    
    @Published var warningType = 0
    @Published var warningShown = false
    @AppStorage("lastWarning") var lastWarning: Date?
    
    @AppStorage("Coins") var coins = 0.0
    @AppStorage("AccountLevel") var accountLevel: Int = 1
    @AppStorage("XPPoints") var xpPoints = 0.0
    @AppStorage("logHealthMode") var logHealthMode = 0
    @Published var addToHealthVisible = true
    @AppStorage("hud_show_distance") var showDistance = true
    @AppStorage("hud_show_ramUsage") var showRam = false
    @AppStorage("hud_show_cpuUsage") var showCpu = false
    @AppStorage("hud_show_thermalState") var showThermal = false
    
    @Published var currentThermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var currentRAM: Double = 0.0
    @Published var currentCPU: Double = 0.0
    @Published var maxAvailableRAM: Double = 0.0
    
    @AppStorage("CurrentSeason") var currentSeason: Int = 0
    @AppStorage("LastSeasonPass") var lastPremiumSeasonPass: Int = 0
    @AppStorage("SeasonXPPoints") var seasonXPPoints: Double = 0
    @AppStorage("SeasonPassLevel") var seasonPassLevel: Int = 1
    @AppStorage("LastClaimedSeasonPassReward") var lastClaimedSeasonPassReward: Int = 0
    @AppStorage("LastClaimedSeasonPassPremiumReward") var lastClaimedSeasonPassPremiumReward: Int = 0
    let xpPerSeasonLevel: Double = 10.0
    
    
    @Published var joiningView = false
    @Published var inGame = false
    
    @Published var gameRunning = false
    @Published var gameTimr = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Published var mediumTimr = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @Published var longTimr = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    @Published var pickLocation = false
    @Published var newGoal: CLLocationCoordinate2D?
    @Published var featureScreen = false
    @Published var selectedObj: MapFeature?
    
    @Published var overviewShown = false
    
    @Published var runStartDate: Date?
    @Published var runEndDate: Date?
    @Published var gameStopwatch: TimeInterval = 0.0
    
    @Published var gameMode = 0
    @Published var antiCheatLimit = 10.0
    @Published var antiCheatLoad = 0.0
    
    @Published var profileShown = false
    @Published var nameAlert = false
    @Published var newName = ""
    @Published var runHistoryShown = false
    
    @Published var inGameTab = 0
    @Published var runLog: [CLLocation] = []
    @AppStorage("showRunLog") var showRunLog = false
    @AppStorage("precisePingNumbers") var precisePingNumbers = true
    @Published var navigatedRoute: MKRoute?
    @AppStorage("satellite") var mapSatellite: Bool = false
    @Published var appCurrentlyLocked = false
    
    // Einstellungen
    @AppStorage("hideSlowMode") var hideSlowMode: Bool = true
    @AppStorage("wayToAutheticate") var wayToAutheticate: Int = 0
    @AppStorage("AppLocked") var appLocked: Bool = false
    @AppStorage("RunsLocked") var runsLocked: Bool = false
    
    // Inventar
    @AppStorage("medkits") var medkits: Int = 0
    @AppStorage("navigators") var navigators: Int = 0
    
    // Computed Properties
    var xpForNextAccountLevel: Double {
        let currentLvl = max(1, accountLevel)
        return Double(currentLvl) * 10.0
    }
    var accountLevelProgress: Double {
        guard xpForNextAccountLevel > 0 else { return 0.0 }
        return min(1.0, max(0.0, xpPoints / xpForNextAccountLevel))
    }
    var seasonPassProgress: Double {
        return min(1.0, max(0.0, seasonXPPoints / xpPerSeasonLevel))
    }
    var totalAccountXPEarned: Double {
        let currentLvl = max(1, accountLevel)
        if currentLvl == 1 { return xpPoints }
        let n = Double(currentLvl - 1)
        let completedLevelsXP = (n * (n + 1) / 2.0) * 10.0
        
        return completedLevelsXP + xpPoints
    }
    
    var totalSeasonXPEarned: Double {
        let currentSeasonLvl = max(1, seasonPassLevel)
        let completedPassLevelsXP = Double(currentSeasonLvl - 1) * xpPerSeasonLevel
        
        return completedPassLevelsXP + seasonXPPoints
    }
    
    var distanceToTarget: String? {
        guard let myLoc = LocationManager.shared.lastLocation,
              let targetCoord = btManager.targetLocation else { return nil }
        
        let targetLoc = CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude)
        let distance = myLoc.distance(from: targetLoc)
        
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    var thermalStateDescription: (text: String, icon: String, color: Color) {
        switch currentThermal {
        case .nominal:
            return ("Normal", "thermometer.sun", .green)
        case .fair:
            return ("Warm", "thermometer.sun.fill", .yellow)
        case .serious:
            return ("Heiß (Drosselung)", "thermometer.high", .orange)
        case .critical:
            return ("Kritisch (Gefahr!)", "exclamationmark.triangle.fill", .red)
        @unknown default:
            return ("Unbekannt", "questionmark.circle", .gray)
        }
    }
    
    // Functions
    func updateDeviceInfo() {
        currentThermal = ProcessInfo.processInfo.thermalState
        
        maxAvailableRAM = Double(os_proc_available_memory()) / 1024.0 / 1024.0
        
        var ramInfo = mach_task_basic_info()
        var ramCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let ramResult = withUnsafeMutablePointer(to: &ramInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(ramCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &ramCount)
            }
        }
        if ramResult == KERN_SUCCESS {
            currentRAM = Double(ramInfo.resident_size) / 1024.0 / 1024.0
        }
        
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let cpuResult = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if cpuResult == KERN_SUCCESS, let threads = threadList {
            defer {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount * mach_msg_type_number_t(MemoryLayout<thread_t>.size)))
            }
            
            var totalCPU: Double = 0.0
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let threadResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                        thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                if threadResult == KERN_SUCCESS {
                    if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                        totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }
            }
            currentCPU = totalCPU
        }
    }
    
    func saveWidgetData() {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.simonstr.sombies") {
            sharedDefaults.set(coins, forKey: "widgetCoins")
            sharedDefaults.set(xpPoints, forKey: "widgetXP")
            sharedDefaults.set(xpForNextAccountLevel, forKey: "widgetNextLevel")
            sharedDefaults.set(accountLevel, forKey: "widgetLevel")
            sharedDefaults.set(accountLevelProgress, forKey: "widgetAccountProgress")
            sharedDefaults.set(medkits, forKey: "widgetMedkits")
            sharedDefaults.set(navigators, forKey: "widgetNavigators")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func addXP(baseXP: Double, questXP: Double = 0.0) {
        if accountLevel < 1 { accountLevel = 1 }
        if seasonPassLevel < 1 { seasonPassLevel = 1 }
        
        xpPoints += baseXP
        
        while xpPoints >= xpForNextAccountLevel {
            xpPoints -= xpForNextAccountLevel
            accountLevel += 1
            Logger.ui.info("Permanentes Level-Up! Neues Level: \(self.accountLevel)")
        }
        
        let levelBonus = 1.0 + (Double(accountLevel) * 0.01)
        let finalSeasonXP = questXP * levelBonus
        
        seasonXPPoints += finalSeasonXP
        
        while seasonXPPoints >= xpPerSeasonLevel {
            seasonXPPoints -= xpPerSeasonLevel
            seasonPassLevel += 1
            Logger.ui.info("Season Pass Stufe freigeschaltet! Stufe: \(self.seasonPassLevel)")
        }
    }
    
    func formatDurationR(from start: Date, to end: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: start, to: end) ?? "0s"
    }
    
    func authenticateUser() async throws {
        var way: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        switch wayToAutheticate {
        case 0:
            way = .deviceOwnerAuthentication
        case 1:
            way = .deviceOwnerAuthenticationWithBiometrics
        default:
            way = .deviceOwnerAuthenticationWithBiometrics
        }
        context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(way, error: &error) else {
            throw AuthError.biometricsNotAvailable
        }
        let reason = "Verwendung einer gesperrten Funktion."
        let success = try await context.evaluatePolicy(way, localizedReason: reason)
        if !success {
            throw AuthError.failed
        }
    }
    
    func handleAppTermination(btManager: BluetoothManager) {
        if btManager.isHosting {
            btManager.terminateParty()
        } else {
            btManager.leaveParty()
        }
    }
    func formatDuration(start: Date, end: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        let duration = end.timeIntervalSince(start)
        return formatter.string(from: duration) ?? "0:00"
    }
    func saveRunningWorkout(startDate: Date, endDate: Date, distanceInMeters: Double, locations: [CLLocation], type: HKWorkoutActivityType) async {
        let healthStore = HKHealthStore()
        
        let typesToShare: Set = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType.quantityType(forIdentifier: type == .cycling ? .distanceCycling : .distanceWalkingRunning)!
        ]
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: [])
            guard HKHealthStore.isHealthDataAvailable() else {
                Logger.system.warning("HealthKit ist auf diesem Gerät nicht verfügbar.")
                return
            }
        } catch {
            Logger.system.error("Berechtigungsanfrage fehlgeschlagen: \(error.localizedDescription)")
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .outdoor
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.beginCollection(withStart: startDate) { success, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceInMeters)
            let sample = HKQuantitySample(type: distanceType, quantity: distanceQuantity, start: startDate, end: endDate)
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.add([sample]) { success, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.endCollection(withEnd: endDate) { success, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            
            let workout = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout?, Error>) in
                builder.finishWorkout { workout, error in
                    if let error = error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: workout) }
                }
            }
            
            if let finalWorkout = workout, !locations.isEmpty {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                try await routeBuilder.insertRouteData(locations)
                try await routeBuilder.finishRoute(with: finalWorkout, metadata: nil)
            }
            
            Logger.system.info("Training erfolgreich gespeichert!")
            
        } catch {
            Logger.system.error("Error: \(error.localizedDescription)")
        }
    }
    private func saveRoute(locations: [CLLocation], for workout: HKWorkout, healthStore: HKHealthStore) {
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        
        routeBuilder.insertRouteData(locations) { success, error in
            guard success else { return }
            
            routeBuilder.finishRoute(with: workout, metadata: nil) { route, error in
                if route != nil {
                    Logger.system.info("Lauftraining und Route erfolgreich in Health gespeichert!")
                }
            }
        }
    }
    func calculateRoute(from start: CLLocationCoordinate2D,
                        to destination: CLLocationCoordinate2D,
                        type: MKDirectionsTransportType) async -> MKRoute? {
        
        let request = MKDirections.Request()
        let sourceLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        request.source = MKMapItem(location: sourceLocation, address: nil)
        request.destination = MKMapItem(location: destinationLocation, address: nil)
        request.transportType = type
        
        let directions = MKDirections(request: request)
        
        do {
            let response = try await directions.calculate()
            return response.routes.first
        } catch {
            Logger.calculation.error("Fehler bei der Routenberechnung: \(error.localizedDescription)")
            return nil
        }
    }
    func calculateDistance(from locations: [CLLocation]) -> Double {
        var totalDistance: Double = 0.0
        for i in 0..<locations.count - 1 {
            let startPoint = locations[i]
            let endPoint = locations[i+1]
            
            let distance = startPoint.distance(from: endPoint)
            totalDistance += distance
        }
        
        return totalDistance
    }
    func modeColor() -> Color {
        if colorScheme == .dark {
            return .white
        } else {
            return .black
        }
    }
}

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let ui = Logger(subsystem: subsystem, category: "UI-State")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let system = Logger(subsystem: subsystem, category: "System")
    static let calculation = Logger(subsystem: subsystem, category: "Calculation")
}

enum AuthError: LocalizedError {
    case biometricsNotAvailable
    case failed
    
    var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable:
            return "Biometrische Authentifizierung ist auf diesem Gerät nicht verfügbar oder eingerichtet."
        case .failed:
            return "Authentifizierung fehlgeschlagen oder vom Nutzer abgebrochen."
        }
    }
}
