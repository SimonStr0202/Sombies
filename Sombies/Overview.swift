import SwiftUI
import SlideButton
import HealthKit

struct OverviewDisplay: View {
    @ObservedObject var vm: ContentViewModel
    @State var animCount: Int = 0
    var body: some View {
        VStack {
            VStack {
                if BluetoothManager.shared.gameState == .win {
                    if animCount >= 1 {
                        Image(systemName: "figure.run")
                            .font(.system(size: 100))
                            .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    }
                    if animCount >= 2 {
                        Text("Gewonnen!")
                            .font(.largeTitle.bold())
                            .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    }
                } else if BluetoothManager.shared.gameState == .gameOver {
                    if animCount >= 1 {
                        Image(systemName: "figure.fall")
                            .font(.system(size: 100))
                            .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    }
                    if animCount >= 2 {
                        Text("Game Over!")
                            .font(.largeTitle.bold())
                            .transition(.move(edge: .bottom).combined(with: .blurReplace))
                    }
                } else {
                    Text("Ein Fehler ist aufgetreten")
                        .font(.largeTitle.bold())
                }
            }
            Spacer()
            if animCount >= 3 {
                VStack {
                    OverviewCard(vm: vm, icon: "stopwatch", text: "\(Int(vm.gameStopwatch))s", color: .blue, trigger: animCount == 4)
                    OverviewCard(vm: vm, icon: "heart.fill", text: "\(Int(BluetoothManager.shared.health))/100", color: .red, trigger: animCount == 5)
                    OverviewCard(vm: vm, icon: "brain.fill", text: "+\(Int(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 10))) Münzen", color: .yellow, trigger: animCount == 6)
                    OverviewCard(vm: vm, icon: "sparkles", text: "+\(Int(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 50))) XP", color: .green, trigger: animCount == 7)
                }
                .transition(.move(edge: .bottom).combined(with: .blurReplace))
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
            if animCount == 8 {
                Button("Schließen") {
                    RunManager.shared.saveRun(Run(id: UUID(), startDate: vm.runStartDate!, endDate: vm.runEndDate!, track: vm.runLog.map { $0.coordinate }))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        BluetoothManager.shared.gameState = .waiting
                    })
                    vm.hostPlayersAmount = 1
                    vm.overviewShown = false
                    vm.coins += Double(Int(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 10)))
                    let XPEarned = Double(vm.gameStopwatch < 200 ? 0 : floor(vm.gameStopwatch / 50))
                    vm.addXP(baseXP: XPEarned, questXP: XPEarned)
                    vm.saveWidgetData()
                    BluetoothManager.shared.health = 100
                    vm.runLog.removeAll()
                    vm.navigatedRoute = nil
                }
                .padding()
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .bold()
                .glassEffect(.regular.interactive().tint(.blue))
                .contentShape(Rectangle())
                .transition(.move(edge: .bottom).combined(with: .blurReplace))
                .padding()
            }
        }
        .onAppear {
            vm.addToHealthVisible = true
            
            if BluetoothManager.shared.isHosting {
                BluetoothManager.shared.terminateParty()
            } else {
                BluetoothManager.shared.leaveParty()
            }
            BluetoothManager.shared.targetLocation = nil
            BluetoothManager.shared.syncedZombies.removeAll()
            BluetoothManager.shared.peerLocations.removeAll()
            
            if vm.logHealthMode == 2 && vm.runStartDate != nil && vm.runEndDate != nil {
                Task {
                    await vm.saveRunningWorkout(startDate: vm.runStartDate!, endDate: vm.runEndDate!, distanceInMeters: vm.calculateDistance(from: vm.runLog), locations: vm.runLog, type: .walking)
                    vm.addToHealthVisible = false
                }
            }
            
            animCount = 0
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                
                for i in 0...7 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        animCount = i
                    }
                    try? await Task.sleep(for: .seconds(0.8))
                }
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animCount = 8
                }
            }
        }
    }
}

struct OverviewCard: View {
    @ObservedObject var vm: ContentViewModel
    
    let icon: String
    let text: String
    let color: Color
    let trigger: Bool
    
    @State private var isVisible = false
    @State private var iconSize = 1.0
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: icon)
                    .scaleEffect(iconSize)
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(color)
                if isVisible {
                    Text(text)
                        .bold()
                        .font(.title3)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Spacer()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color, lineWidth: 2)
                    .background(color.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            
            if !isVisible {
                Spacer()
            }
        }
        .onChange(of: trigger) { oldValue, newValue in
            if newValue {
                HapticManager.shared.playRisingAndPloppPattern()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    iconSize = 1.4
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        iconSize = 1.0
                        isVisible = true
                    }
                }
            }
        }
    }
}
