import SwiftUI
import MapKit
import MultipeerConnectivity

struct HostingView: View {
    @ObservedObject var vm: ContentViewModel
    @StateObject var locManager = LocationManager.shared
    @ObservedObject var btManager: BluetoothManager
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section("Verbundene Spieler") {
                        ForEach(1...vm.hostPlayersAmount, id: \.self) { idx in
                            if idx == 1 {
                                Text("\(UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name) (Du)")
                            } else {
                                let peerIndex = idx - 2
                                if btManager.connectedPeers.indices.contains(peerIndex) {
                                    Text(btManager.connectedPeers[peerIndex].displayName)
                                } else {
                                    HStack {
                                        Image(systemName: "wifi")
                                            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous))
                                        Text("Auf Spieler warten...")
                                    }
                                }
                            }
                        }
                        .id(btManager.connectedPeers.count)
                    }
                }
                .safeAreaInset(edge: .bottom, content: {
                    VStack {
                        Stepper("Spielerzahl: \(vm.hostPlayersAmount)", value: $vm.hostPlayersAmount, in: (btManager.isHosting ? 2 : 1)...8)
                            .animation(.linear, value: vm.hostPlayersAmount)
                            .contentTransition(.numericText())
                            .disabled(!btManager.isHosting)
                        Picker("Spielmodus", selection: $vm.gameMode, content: {
                            if !vm.hideSlowMode {
                                Text("Langsam").tag(-1)
                            }
                            Text("Normal").tag(0)
                            Text("Joggen").tag(1)
                            Text("Fahrrad").tag(2)
                        })
                        .pickerStyle(.segmented)
                        .onChange(of: vm.gameMode) {
                            switch vm.gameMode {
                            case -1:
                                vm.antiCheatLimit = 5
                            case 0:
                                vm.antiCheatLimit = 10
                            case 1:
                                vm.antiCheatLimit = 15
                            case 2:
                                vm.antiCheatLimit = 30
                            default:
                                vm.antiCheatLimit = 10
                            }
                        }
                        HStack {
                            Button("Sichtbar werden") {
                                btManager.hostParty()
                                vm.hostPlayersAmount = 2
                            }
                            .disabled(btManager.isHosting)
                            Spacer()
                            Button("Los", systemImage: "play.fill") {
                                vm.hostingView = false
                                vm.gameRunning = true
                                btManager.isHosting = true
                                btManager.startGame(mode: vm.gameMode)
                                btManager.setExtractionPoint(near: vm.newGoal!)
                                if btManager.isHosting {
                                    for _ in 0...3 {
                                        var allPositions = Array(btManager.peerLocations.values)
                                        if let myLoc = LocationManager.shared.lastLocation?.coordinate {
                                            allPositions.append(myLoc)
                                        }
                                        
                                        if let randomPlayerCoord = allPositions.randomElement() {
                                            let zombieCoord = randomPlayerCoord.shiftedBy(meters: 100)
                                            btManager.broadcastZombieSpawn(id: UUID(), coord: zombieCoord)
                                        }
                                    }
                                }
                            }
                            .font(.largeTitle.bold())
                            .disabled(vm.newGoal == nil)
                        }
                    }
                    .padding()
                    .glassEffect(.regular, in: ContainerRelativeShape())
                    .padding()
                })
                
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled()
            .navigationTitle("Hosten")
            .toolbar {
                ToolbarItem(placement: .topBarLeading, content: {
                    NavigationLink(destination: {
                        MapReader { proxy in
                            Map(position: $vm.goalMapPos, content: {
                                UserAnnotation()
                                if vm.newGoal != nil {
                                    Marker("Ziel", systemImage: "flag.fill", coordinate: vm.newGoal!)
                                        .tint(.cyan)
                                    MapCircle(center: vm.newGoal!, radius: 15)
                                        .foregroundStyle(.green.opacity(0.5))
                                        .stroke(Color.green, lineWidth: 1)
                                }
                            })
                            .onTapGesture { loc in
                                vm.newGoal = proxy.convert(loc, from: .local)
                            }
                            .mapControls {
                                MapUserLocationButton()
                            }
                        }
                    }, label: {
                        Label("Standort wählen", systemImage: "mappin")
                    })
                })
                ToolbarItem(placement: .topBarTrailing, content: {
                    Button("Schließen", systemImage: "xmark") {
                        if btManager.isHosting {
                            vm.showCancelHostAlert = true
                        } else {
                            vm.hostingView = false
                        }
                    }
                    .confirmationDialog("Hosten beenden?", isPresented: $vm.showCancelHostAlert, actions: {
                        Button("Beenden", role: .destructive, action: {
                            btManager.terminateParty()
                            btManager.stopAll()
                            vm.hostingView = false
                            vm.hostPlayersAmount = 1
                        })
                    }, message: {
                        Text("Das Spiel wird für alle beendet")
                    })
                })
            }
        }
        .ignoresSafeArea(.container)
    }
}
