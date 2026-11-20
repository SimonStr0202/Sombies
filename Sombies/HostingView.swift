import SwiftUI
import MapKit
import MultipeerConnectivity
import SkimUI

struct HostingView: View {
    @ObservedObject var vm: ContentViewModel
    @Environment(\.presentToast) var presentToast
    @StateObject var locManager = LocationManager.shared
    @StateObject var session = GameSessionManager.shared
    
    // Für Supabase Raum-Erstellung
    @State private var hostRoomID = ""
    @State private var hostPassword = ""
    
    @State private var showPlayButtonLabel = true
    
    // Hilfsvariable für die Anzeige verbundener Spieler (unabhängig vom Netzwerk)
    var connectedPlayerNames: [String] {
        if session.selectedMode == .bluetooth {
            return session.bluetooth.connectedPeers.map { $0.displayName }
        } else {
            return session.supabase.connectedPeers
        }
    }
    
    var isHosting: Bool {
        session.selectedMode == .bluetooth ? session.bluetooth.isHosting : session.supabase.isHosting
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    if session.selectedMode == .supabase && !isHosting {
                        Section("Raum-Einstellungen (Supabase)") {
                            TextField("Raum-ID", text: $hostRoomID)
                            SecureField("Passwort", text: $hostPassword)
                        }
                    }
                    
                    Section("Verbundene Spieler") {
                        ForEach(1...vm.hostPlayersAmount, id: \.self) { idx in
                            if idx == 1 {
                                Text("\(UserDefaults.standard.string(forKey: "userName") ?? UIDevice.current.name) (Du)")
                            } else {
                                let peerIndex = idx - 2
                                if connectedPlayerNames.indices.contains(peerIndex) {
                                    Text(connectedPlayerNames[peerIndex])
                                } else {
                                    HStack {
                                        Image(systemName: "wifi")
                                            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous))
                                        Text("Auf Spieler warten...")
                                    }
                                }
                            }
                        }
                        if isHosting {
                            Stepper("Spielerzahl: \(vm.hostPlayersAmount)", value: $vm.hostPlayersAmount, in: (isHosting ? 2 : 1)...8)
                                .animation(.linear, value: vm.hostPlayersAmount)
                                .contentTransition(.numericText())
                                .disabled(!isHosting)
                        } else {
                            Button("Sichtbar werden / Hosten") {
                                Task {
                                    await session.hostParty(roomId: hostRoomID, password: hostPassword)
                                    vm.hostPlayersAmount = 2
                                }
                            }
                            .disabled(isHosting || (session.selectedMode == .supabase && hostRoomID.isEmpty))
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        Button(action: {
                            if vm.newGoal != nil {
                                vm.hostingView = false
                                vm.gameRunning = true
                                
                                session.isHosting = true
                                session.startGame(mode: vm.gameMode)
                                session.setExtractionPoint(near: vm.newGoal!)
                                
                                for _ in 0...3 {
                                    var allPositions: [CLLocationCoordinate2D] = session.peerLocationsList
                                    
                                    if let myLoc = LocationManager.shared.lastLocation?.coordinate {
                                        allPositions.append(myLoc)
                                    }
                                    
                                    if let randomPlayerCoord = allPositions.randomElement() {
                                        let zombieCoord = randomPlayerCoord.shiftedBy(meters: 100)
                                        session.broadcastZombieSpawn(id: UUID(), coord: zombieCoord)
                                    }
                                }
                            } else {
                                presentToast(ToastValue(title: "Kein Ziel ausgewählt", message: "Wähle ein Ziel mit der Stecknadel in der oberen linken Ecke aus", type: .default))
                            }
                        }, label: {
                            HStack {
                                Image(systemName: "play.fill")
                                if showPlayButtonLabel {
                                    Text("Los")
                                        .transition(.blurReplace)
                                }
                            }.padding(7)
                        })
                        .font(.largeTitle.bold())
                        .buttonStyle(.glass(.regular.interactive().tint(vm.newGoal == nil ? .gray : .blue)))
                        .padding()
                        .accessibilityHint(Text("Spiel starten"))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: {
                                withAnimation {
                                    showPlayButtonLabel = false
                                }
                            })
                        }
                    }
                }
            }
            .navigationTitle("Hosten")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Spielmodus", selection: $vm.gameMode) {
                        if !vm.hideSlowMode {
                            Text("Langsam").tag(-1)
                        }
                        Text("Normal").tag(0)
                        Text("Joggen").tag(1)
                        Text("Fahrrad").tag(2)
                    }
                    .pickerStyle(.segmented)
                    /*
                    Picker("Netzwerk", selection: $session.selectedMode) {
                        Text("Lokal").tag(NetworkMode.bluetooth)
                        Text("Internet").tag(NetworkMode.supabase)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isHosting)
                     */
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: {
                        MapReader { proxy in
                            Map(position: $vm.goalMapPos) {
                                UserAnnotation()
                                if let goal = vm.newGoal {
                                    Marker("Ziel", systemImage: "flag.fill", coordinate: goal)
                                        .tint(.cyan)
                                    MapCircle(center: goal, radius: 15)
                                        .foregroundStyle(.green.opacity(0.5))
                                        .stroke(Color.green, lineWidth: 1)
                                }
                            }
                            .onTapGesture { loc in
                                vm.newGoal = proxy.convert(loc, from: .local)
                            }
                        }
                    }) {
                        Label("Standort wählen", systemImage: "mappin")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") {
                        if isHosting {
                            vm.showCancelHostAlert = true
                        } else {
                            vm.hostingView = false
                        }
                    }
                    .confirmationDialog("Hosten beenden?", isPresented: $vm.showCancelHostAlert) {
                        Button("Beenden", role: .destructive) {
                            session.leaveParty()
                            vm.hostingView = false
                            vm.hostPlayersAmount = 1
                        }
                    } message: {
                        Text("Das Spiel wird für alle beendet")
                    }
                }
            }
        }
    }
}
