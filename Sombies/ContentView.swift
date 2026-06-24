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
                OverviewDisplay(vm: vm)
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

