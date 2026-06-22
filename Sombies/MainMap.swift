import SwiftUI
import MapKit
import extendedSyntax
import MultipeerConnectivity
import CoreLocation
import OSLog
import GameCenterKit

struct MainMap: View {
    @Environment(\.scenePhase) var scenePhase
    @Namespace var mapScope
    @ObservedObject var vm: ContentViewModel
    @StateObject var locManager = LocationManager.shared
    @ObservedObject var btManager: BluetoothManager
    
    var deviceIconName: String {
        let device = UIDevice.current.userInterfaceIdiom
        switch device {
        case .phone:
            return "iphone"
        case .pad:
            return "ipad"
        case .mac:
            return "macmini"
        default:
            return "questionmark.device.fixed"
        }
    }
    var body: some View {
        Map(position: $vm.mapPos, selection: $vm.selectedObj, scope: mapScope, content: {
            MainMapContents(vm: vm, btManager: btManager)
        })
        .animation(.linear(duration: 1), value: btManager.syncedZombies.values.description)
        .animation(.linear(duration: 1), value: btManager.peerLocations.values.description)
        .onAppear {
            locManager.startUpdating()
            Task {
                await GameCenterKit.shared.authenticate()
            }
            if vm.appLocked {
                vm.appCurrentlyLocked = true
                Task {
                    do {
                        try await vm.authenticateUser()
                        withAnimation {
                            vm.appCurrentlyLocked = false
                        }
                    } catch {}
                }
            } else {
                vm.appCurrentlyLocked = false
            }
        }
        .onChange(of: vm.coins) {
            vm.saveWidgetData()
        }
        .onChange(of: vm.selectedObj) {
            if btManager.gameState == .waiting {
                if vm.selectedObj != nil {
                    vm.featureScreen = true
                } else {
                    vm.featureScreen = false
                }
            } else {
                vm.selectedObj = nil
            }
        }
        .onChange(of: vm.featureScreen) {
            if vm.featureScreen == false {
                vm.selectedObj = nil
            }
        }
        .sheet(isPresented: $vm.featureScreen) {
            FeatureScreen(vm: vm)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                if btManager.gameState != .active {
                    locManager.stopUpdating()
                }
            } else if scenePhase == .active {
                if btManager.gameState != .active {
                    locManager.startUpdating()
                }
            }
        }
        .mapStyle(vm.mapSatellite ? .imagery : .standard)
        .safeAreaInset(edge: .top, content: {
            HStack {
                Image(systemName: deviceIconName)
                Text(vm.userName)
                Image(systemName: "brain.fill")
                    .padding(.leading)
                Text("\(Int(vm.coins))")
                Image(systemName: "sparkles")
                    .padding(.leading)
                Text("\(Int(vm.xpPoints))")
                Spacer()
                if vm.appLocked && btManager.gameState != .active {
                    Button("App sperren", systemImage: "lock.fill") {
                        withAnimation {
                            vm.appCurrentlyLocked = true
                        }
                    }
                    .labelStyle(.iconOnly)
                }
                Button(vm.mapSatellite ? "Normal" : "Satellitenkarte", systemImage: vm.mapSatellite ? "globe.europe.africa" : "map.fill") {
                    withAnimation {
                        vm.mapSatellite.toggle()
                    }
                }
                .labelStyle(.iconOnly)
            }
            .padding(10)
            .glassEffect(.regular.interactive())
            .padding()
        })
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onChange(of: locManager.lastLocation) {
            guard let coord = locManager.lastLocation?.coordinate else { return }
            btManager.broadcastLocation(coord, spd: locManager.speedInKmh)
            Logger.network.info("Sent Location")
            if btManager.gameState == .active && locManager.lastLocation != nil {
                vm.runLog.append(locManager.lastLocation!)
            }
        }
        .onChange(of: btManager.gameState) { old, new in
            if old != .paused {
                stateChange()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            vm.handleAppTermination(btManager: btManager)
        }
        .onReceive(vm.gameTimr) { _ in
            gameTimr()
            vm.updateDeviceInfo()
        }
        .onReceive(vm.mediumTimr) { _ in
            ZombieActivityManager.shared.update(distance: btManager.closestZombieDistance ?? 0, ping: Int(btManager.lastPing))
        }
        .onReceive(vm.longTimr) { _ in
            if btManager.syncedZombies.count < 15 {
                var allPositions = Array(btManager.peerLocations.values)
                if let myLoc = LocationManager.shared.lastLocation?.coordinate {
                    allPositions.append(myLoc)
                }
                
                if let randomPlayerCoord = allPositions.randomElement() {
                    let zombieCoord = randomPlayerCoord.shiftedBy(meters: 100)
                    if btManager.isHosting {
                        btManager.broadcastZombieSpawn(id: UUID(), coord: zombieCoord)
                    }
                }
            }
        }
    }
    func stateChange() {
        if btManager.gameState == .active {
            vm.joiningView = false
            vm.gameRunning = true
            vm.gameStopwatch = 0
            vm.runStartDate = Date()
            if !btManager.isHosting {
                switch btManager.gameMode {
                case -1:
                    vm.antiCheatLimit = 5
                    vm.gameMode = -1
                case 0:
                    vm.antiCheatLimit = 10
                    vm.gameMode = 0
                case 1:
                    vm.antiCheatLimit = 15
                    vm.gameMode = 1
                case 2:
                    vm.antiCheatLimit = 30
                    vm.gameMode = 2
                default:
                    vm.antiCheatLimit = 10
                }
            }
            UIApplication.shared.isIdleTimerDisabled = true
            locManager.manager.allowsBackgroundLocationUpdates = true
            locManager.manager.pausesLocationUpdatesAutomatically = false
        } else if btManager.gameState == .gameOver || btManager.gameState == .win {
            vm.overviewShown = true
            btManager.localItems.removeAll()
            btManager.stopAll()
            ZombieActivityManager.shared.stopActivity()
            vm.inGame = false
            vm.gameRunning = false
            vm.runEndDate = Date()
            locManager.manager.allowsBackgroundLocationUpdates = false
            locManager.manager.pausesLocationUpdatesAutomatically = true
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    func gameTimr() {
        if let lastLoc = locManager.lastLocation {
            let coord = lastLoc.coordinate
            btManager.broadcastLocation(coord, spd: locManager.speedInKmh)
            btManager.checkItems(myLocation: coord)
            btManager.checkWinCondition(myLocation: coord)
            btManager.checkZombieCollisions(myLocation: coord)
        }

        if btManager.gameState == .active {
            vm.gameStopwatch += 1
            
            if locManager.speedInKmh <= 0.5 {
                let newHealth = btManager.health + 1
                btManager.health = Math.clamp(newHealth, min: 0, max: 100)
            }
            
            if btManager.isHosting {
                if let hostCoord = locManager.lastLocation?.coordinate {
                    let multiplier = 0.5 * (vm.antiCheatLimit * 0.1)
                    btManager.updateZombieAI(hostLocation: hostCoord, multiplier: multiplier)
                }
                btManager.sendPing()
            }
        }
    }
}

struct MainMapContents: MapContent {
    @ObservedObject var vm: ContentViewModel
    @StateObject var locManager = LocationManager.shared
    @ObservedObject var btManager: BluetoothManager
    var body: some MapContent {
        UserAnnotation()
        ForEach(Array(btManager.syncedZombies), id: \.key) { (id, coordinate) in
            MapCircle(center: coordinate, radius: 5)
                .foregroundStyle(.red.opacity(0.4))
                .stroke(.red)
            MapCircle(center: coordinate, radius: 2)
                .foregroundStyle(.red.opacity(0.8))
        }
        if vm.selectedObj != nil && btManager.gameState == .waiting {
            MapCircle(center: vm.selectedObj!.coordinate, radius: 15)
                .foregroundStyle(.green.opacity(0.5))
                .stroke(.green, style: StrokeStyle(lineWidth: 1))
        }
        ForEach(Array(btManager.peerLocations), id: \.key) { (id, coordinate) in
            Annotation("\(id.displayName)", coordinate: coordinate) {
                ZStack {
                    Circle().fill(.green).frame(width: 15, height: 15)
                        .opacity(0.4)
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
            }
        }
        ForEach(btManager.localItems) { item in
            MapCircle(center: item.coordinate, radius: 10)
                .foregroundStyle(.blue.opacity(0.4))
                .stroke(.blue, style: StrokeStyle(dashPhase: 3))
            Annotation("Item", coordinate: item.coordinate, content: {
                Image(systemName: "bag.fill")
            })
                .annotationTitles(.hidden)
        }
        if btManager.targetLocation != nil {
            MapCircle(center: btManager.targetLocation!, radius: 15)
                .foregroundStyle(.green.opacity(0.4))
                .stroke(.green, style: StrokeStyle(dashPhase: 3))
            Annotation("Ziel", coordinate: btManager.targetLocation!, content: {
                Image(systemName: "flag.pattern.checkered")
            })
        }
        if btManager.gameState == .active && vm.showRunLog {
            MapPolyline(coordinates: vm.runLog.map { $0.coordinate })
                .stroke(.red, lineWidth: 5)
        }
        if btManager.gameState == .active && vm.navigatedRoute != nil {
            MapPolyline(vm.navigatedRoute!)
                .stroke(.blue, lineWidth: 10)
        }
    }
}

