import SwiftUI
import MapKit
import HealthKit
import MultipeerConnectivity
import Combine
import SpriteKit
import extendedSyntax
import SlideButton
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.colorScheme) var colorScheme
    @StateObject var vm = ContentViewModel()
    @StateObject var btManager = BluetoothManager.shared
    @StateObject var storeManager = StoreManager()
    
    @StateObject var locManager = LocationManager.shared
    @StateObject var runManager = RunManager.shared
    let vibrate = UIImpactFeedbackGenerator(style: .medium)
    var body: some View {
        ZStack {
            ZStack {
                MainMap(vm: vm, btManager: btManager)
                    .safeAreaPadding(.top)
                    .padding(.top)
            }
            .safeAreaInset(edge: .bottom, content: {
                VStack {
                    if btManager.gameState != .active && btManager.gameState != .paused {
                        BottomButtons(vm: vm)
                            .padding([.horizontal, .bottom], 25)
                    } else {
                        if btManager.gameState == .active || btManager.gameState == .paused {
                            StatusBar(vm: vm, btManager: btManager)
                            InGameHUD(vm: vm, btManager: btManager)
                                .ignoresSafeArea()
                                .glassEffect(.regular.interactive(), in: ContainerRelativeShape())
                                .padding([.horizontal, .bottom])
                        }
                    }
                }
                .ignoresSafeArea()
            })
            .ignoresSafeArea(.container)
            .sheet(isPresented: $vm.profileShown) {
                ProfileView(vm: vm, shopManager: storeManager)
            }
            .sheet(isPresented: $vm.joiningView, content: {
                NavigationStack {
                    VStack {
                        if !vm.inGame {
                            List {
                                Section("Verfügbare Spieler") {
                                    ForEach(btManager.availablePeers, id: \.self) { peer in
                                        HStack {
                                            Text(peer.displayName)
                                            Spacer()
                                            Button("Beitreten") {
                                                vm.inGame = true
                                                btManager.invitePeer(peer)
                                            }
                                        }
                                    }
                                    .id(btManager.availablePeers.count)
                                }
                            }
                        } else {
                            Spacer()
                            ProgressView()
                            Text(btManager.fullyConnected ? "Auf den Start warten..." : "Verbinden...")
                                .id(btManager.fullyConnected)
                                .onChange(of: btManager.connectedPeers.count) {
                                    if btManager.connectedPeers.count == 0 {
                                        vm.inGame = false
                                    }
                                }
                            Spacer()
                        }
                    }
                    .navigationTitle("Beitreten")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing, content: {
                            Button("Schließen", systemImage: "xmark") {
                                if vm.inGame {
                                    vm.showCancelHostAlert = true
                                } else {
                                    vm.joiningView = false
                                }
                            }
                            .confirmationDialog("Suche beenden?", isPresented: $vm.showCancelHostAlert, actions: {
                                Button("Beenden", role: .destructive, action: {
                                    btManager.stopAll()
                                    btManager.leaveParty()
                                    vm.inGame = false
                                    vm.joiningView = false
                                })
                            }, message: {
                                Text("Du verlässt das aktuelle Spiel")
                            })
                        })
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
                .onAppear {
                    btManager.lookForParties()
                }
            })
            .sheet(isPresented: $vm.overviewShown, content: {
                VStack {
                    if btManager.gameState == .win {
                        Text("Gewonnen!")
                            .font(.largeTitle.bold())
                            .padding()
                    } else if btManager.gameState == .gameOver {
                        Text("Game over!")
                            .font(.largeTitle.bold())
                            .padding()
                    } else if btManager.gameState == .active {
                        Text("Aktiv")
                            .font(.largeTitle.bold())
                            .padding()
                    } else if btManager.gameState == .paused {
                        Text("Pausiert")
                            .font(.largeTitle.bold())
                            .padding()
                    } else if btManager.gameState == .waiting {
                        Text("Warten...")
                            .font(.largeTitle.bold())
                            .padding()
                    }
                    Spacer()
                    VStack {
                        HStack {
                            Image(systemName: "stopwatch")
                                .font(.largeTitle)
                                .symbolEffect(.rotate.clockwise.byLayer, options: .nonRepeating)
                            VStack {
                                Text("\(Int(vm.gameStopwatch))s")
                                    .bold()
                            }
                            Spacer()
                        }
                        .padding()
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.largeTitle)
                                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating)
                            VStack {
                                Text("\(Int(btManager.health))/100")
                                    .bold()
                            }
                            Spacer()
                        }
                        .padding()
                        HStack {
                            Image(systemName: "brain.fill")
                                .font(.largeTitle)
                                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating)
                            VStack {
                                Text("+\(Int(vm.gameStopwatch < 120 ? 0 : floor(vm.gameStopwatch / 10))) Münzen")
                                    .bold()
                            }
                            Spacer()
                        }
                        .padding()
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.largeTitle)
                                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating)
                            VStack {
                                Text("+\(Int(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 50))) XP")
                                    .bold()
                            }
                            Spacer()
                        }
                        .padding()
                    }
                    Spacer()
                    if vm.logHealthMode == 1 && vm.addToHealthVisible {
                        SlideButton(String(localized: "Zu Health hinzufügen"), action: {
                            do {
                                if vm.runStartDate != nil && vm.runEndDate != nil {
                                    await vm.saveRunningWorkout(startDate: vm.runStartDate!, endDate: vm.runEndDate!, distanceInMeters: vm.calculateDistance(from: vm.runLog), locations: vm.runLog, type: .walking)
                                    vm.addToHealthVisible = false
                                }
                            }
                        })
                        .padding(.horizontal)
                    }
                    Button("Schließen") {
                        runManager.saveRun(Run(id: UUID(), startDate: vm.runStartDate!, endDate: vm.runEndDate!, track: vm.runLog.map { $0.coordinate }))
                        btManager.gameState = .waiting
                        vm.hostPlayersAmount = 1
                        vm.overviewShown = false
                        vm.coins += Double(Int(vm.gameStopwatch < 120 ? 0 : floor(vm.gameStopwatch / 10)))
                        let XPEarned = Double(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 50))
                        vm.addXP(baseXP: XPEarned, questXP: XPEarned)
                        vm.saveWidgetData()
                        btManager.health = 100
                        vm.runLog.removeAll()
                        vm.navigatedRoute = nil
                    }
                    .onAppear {
                        vm.addToHealthVisible = true
                        if vm.logHealthMode == 2 {
                            if vm.runStartDate != nil && vm.runEndDate != nil {
                                Task {
                                    await vm.saveRunningWorkout(startDate: vm.runStartDate!, endDate: vm.runEndDate!, distanceInMeters: vm.calculateDistance(from: vm.runLog), locations: vm.runLog, type: .walking)
                                    vm.addToHealthVisible = false
                                }
                            }
                        }
                        if btManager.isHosting {
                            btManager.terminateParty()
                        } else {
                            btManager.leaveParty()
                        }
                        btManager.targetLocation = nil
                        btManager.syncedZombies.removeAll()
                        btManager.peerLocations.removeAll()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .bold()
                    .glassEffect(.regular.interactive().tint(.blue))
                    .contentShape(Rectangle())
                    .padding()
                }
                .interactiveDismissDisabled()
            })
            .sheet(isPresented: $vm.hostingView, content: {
                HostingView(vm: vm, btManager: btManager)
            })
            if vm.warningShown {
                Warning(vm: vm)
            }
        }
        .overlay(content: {
            ZStack {
                if vm.appCurrentlyLocked {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    VStack {
                        Image(systemName: "lock.fill")
                            .font(.largeTitle)
                        Text("Sombies ist gesperrt")
                            .font(.largeTitle.bold())
                            .padding()
                        Button(action: {
                            Task {
                                do {
                                    try await vm.authenticateUser()
                                    withAnimation {
                                        vm.appCurrentlyLocked = false
                                    }
                                } catch {}
                            }
                        }, label: {
                            HStack {
                                Text("Entsperren")
                                    .padding()
                                    .glassEffect(.regular.interactive())
                                    .foregroundStyle(modeColor())
                            }
                        })
                        .buttonStyle(.plain)
                    }
                }
            }
            .blur(radius: vm.appCurrentlyLocked ? 0 : 10)
            .onChange(of: scenePhase) {
                WidgetCenter.shared.reloadAllTimelines()
                if scenePhase == .background && vm.appLocked && btManager.gameState != .active {
                    vm.appCurrentlyLocked = true
                }
            }
        })
    }
    func modeColor() -> Color {
        if colorScheme == .dark {
            return .white
        } else {
            return .black
        }
    }
}

#Preview {
    ContentView(vm: ContentViewModel())
}

