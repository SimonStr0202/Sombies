import SwiftUI
import MapKit
import HealthKit
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
    @StateObject var gameSessionManager = GameSessionManager.shared
    
    @StateObject var locManager = LocationManager.shared
    @StateObject var runManager = RunManager.shared
    
    @State var joinMode = 0
    @State var joinRoomID = ""
    @State var joinRoomPassword = ""
    
    let vibrate = UIImpactFeedbackGenerator(style: .medium)
    var body: some View {
        ZStack {
            ZStack {
                MainMap(vm: vm, sessionManager: gameSessionManager)
                    .safeAreaPadding(.top)
                    .padding(.top)
            }
            .safeAreaInset(edge: .bottom, content: {
                VStack {
                    if gameSessionManager.gameState != .active && gameSessionManager.gameState != .paused {
                        BottomButtons(vm: vm)
                            .padding([.horizontal, .bottom], 25)
                    } else {
                        if gameSessionManager.gameState == .active || gameSessionManager.gameState == .paused {
                            StatusBar(vm: vm, sessionManager: gameSessionManager)
                            InGameHUD(vm: vm, sessionManager: gameSessionManager)
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
            .onChange(of: gameSessionManager.gameState) { _, newState in
                if newState == .active {
                    vm.gameRunning = true
                    vm.joiningView = false
                    vm.hostingView = false
                }
            }
            .sheet(isPresented: $vm.joiningView) {
                NavigationStack {
                    VStack {
                        if !vm.inGame {
                            // MARK: - Eingabe / Suche
                            if gameSessionManager.selectedMode == .bluetooth {
                                List {
                                    Section("Verfügbare Spieler (Lokal)") {
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
                                    }
                                }
                            } else if gameSessionManager.selectedMode == .supabase {
                                List {
                                    Section("ID und Passwort eingeben") {
                                        TextField("ID", text: $joinRoomID)
                                        SecureField("Passwort", text: $joinRoomPassword)
                                    }
                                    Section {
                                        Button("Beitreten") {
                                            Task {
                                                await gameSessionManager.joinParty(roomId: joinRoomID, password: joinRoomPassword)
                                                if gameSessionManager.fullyConnected {
                                                    vm.inGame = true
                                                }
                                            }
                                        }
                                        .disabled(joinRoomID.isEmpty)
                                    }
                                }
                            }
                        } else {
                            // MARK: - Statusanzeige
                            Spacer()
                            ProgressView()
                            
                            // Prüft ob der Manager einsatzbereit ist
                            let isConnected = gameSessionManager.fullyConnected
                            
                            Text(isConnected ? "Auf den Start warten..." : "Verbinden...")
                                .font(.headline)
                                .padding()
                            
                            Spacer()
                        }
                    }
                    .navigationTitle("Beitreten")
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("Spielmodus", selection: $gameSessionManager.selectedMode) {
                                Text("Lokal").tag(NetworkMode.bluetooth)
                                Text("Internet").tag(NetworkMode.supabase)
                            }
                            .pickerStyle(.segmented)
                            .disabled(vm.inGame)
                        }
                        
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Schließen", systemImage: "xmark") {
                                if vm.inGame || gameSessionManager.fullyConnected {
                                    vm.showCancelJoinAlert = true
                                } else {
                                    gameSessionManager.leaveParty()
                                    vm.inGame = false
                                    vm.joiningView = false
                                }
                            }
                            .confirmationDialog("Lobby verlassen?", isPresented: $vm.showCancelJoinAlert) {
                                Button("Verlassen", role: .destructive) {
                                    gameSessionManager.leaveParty()
                                    vm.inGame = false
                                    vm.joiningView = false
                                }
                            } message: {
                                Text("Möchtest du die Lobby wirklich verlassen?")
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
                .onAppear {
                    if gameSessionManager.selectedMode == .bluetooth {
                        btManager.lookForParties()
                    }
                }
            }

            .sheet(isPresented: $vm.overviewShown, content: {
                OverviewDisplay(vm: vm)
                .interactiveDismissDisabled()
            })
            .sheet(isPresented: $vm.hostingView, content: {
                HostingView(vm: vm, locManager: vm.locManager)
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

