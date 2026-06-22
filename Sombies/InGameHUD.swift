import SwiftUI
import extendedSyntax
import SlideButton
import MapKit

struct InGameHUD: View {
    @ObservedObject var vm: ContentViewModel
    @ObservedObject var btManager: BluetoothManager
    @State var editOverview = false
    var body: some View {
        VStack {
            HStack {
                if vm.inGameTab == 0 {
                    VStack(alignment: .center, spacing: 2) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Gauge(value: Math.clamp(btManager.health, min: 0, max: 100), in: 0...100, label: {})
                                .tint(LinearGradient(colors: [.red, .yellow, .green], startPoint: .leading, endPoint: .trailing))
                            if !btManager.isHosting {
                                TimelineView(.periodic(from: .now, by: 0.19)) { context in
                                    let timeSinceLastPackage = context.date.timeIntervalSince(btManager.lastPingReceivedAt)
                                    let connectionHealth = max(0, min(1, 1.0 - (timeSinceLastPackage - 1)))
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: "cellularbars", variableValue: connectionHealth)
                                            .foregroundStyle(timeSinceLastPackage > 1.5 ? .red : .green)
                                        if vm.precisePingNumbers {
                                            VStack(alignment: .leading, spacing: 0) {
                                                if timeSinceLastPackage < 1.5 {
                                                    Text("\(Int(Math.toPositive(btManager.lastPing))) ms")
                                                        .font(.system(.caption, design: .monospaced))
                                                        .fontWeight(.bold)
                                                } else {
                                                    Text("\(Int(timeSinceLastPackage * 1000)) ms")
                                                        .font(.system(.caption, design: .monospaced))
                                                        .fontWeight(.bold)
                                                }
                                            }
                                        }
                                    }
                                    .opacity(timeSinceLastPackage > 5 ? 0.3 : 1.0)
                                }
                            }
                        }
                        if vm.showDistance {
                            Text("Entfernung zum Ziel")
                                .font(.caption2.bold())
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\(vm.distanceToTarget ?? "?")")
                                    .font(.title2.monospacedDigit().bold())
                            }
                            .frame(minHeight: .zero, idealHeight: .zero)
                        }
                        if vm.showCpu {
                            Label("CPU-Auslastung", systemImage: "cpu")
                                .font(.caption2.bold())
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\((vm.currentCPU / 100).formatted(.percent.precision(.fractionLength(1))))")
                                    .font(.title2.monospacedDigit().bold())
                            }
                            .frame(minHeight: .zero, idealHeight: .zero)
                        }
                        if vm.showRam {
                            Text("Arbeitsspeicher")
                                .font(.caption2.bold())
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\(vm.currentRAM.formatted(.number.precision(.fractionLength(2))))/\(vm.maxAvailableRAM.formatted(.number.precision(.fractionLength(2)))) MB (\(Int(vm.currentRAM / vm.maxAvailableRAM*100.0))%)")
                                    .font(.title2.monospacedDigit().bold())
                            }
                            .frame(minHeight: .zero, idealHeight: .zero)
                        }
                        if vm.showThermal {
                            Text("Temperatur")
                                .font(.caption2.bold())
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Label(vm.thermalStateDescription.text, systemImage: vm.thermalStateDescription.icon)
                                    .font(.title2.monospacedDigit().bold())
                            }
                            .frame(minHeight: .zero, idealHeight: .zero)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: ContainerRelativeShape())
                    .contextMenu(menuItems: {
                        Button("Bearbeiten", systemImage: "pencil") {
                            editOverview.toggle()
                        }
                    })
                    .sheet(isPresented: $editOverview, content: { DisplayOverviewSettings(vm: vm) })
                    .padding()
                } else if vm.inGameTab == 1 {
                    ScrollView(.horizontal) {
                        HStack {
                            VStack {
                                Label("x\(vm.medkits)", systemImage: "cross.case.fill")
                                    .font(.title)
                                Text("Erste Hilfe Kasten")
                                    .font(.largeTitle)
                                Text("Heile 50 Leben")
                                SlideButton(String(localized: "Benutzen"), action: {
                                    if vm.medkits >= 1 {
                                        if btManager.health < 70 {
                                            btManager.health = Math.clamp(btManager.health + 50, min: 0, max: 100)
                                            vm.medkits -= 1
                                        }
                                    }
                                })
                                .disabled(vm.medkits == 0 || btManager.health >= 70)
                            }
                            .padding(.horizontal)
                            VStack {
                                Label("x\(vm.navigators)", systemImage: "point.topleft.filled.down.to.point.bottomright.curvepath")
                                    .font(.title)
                                Text("Navigator")
                                    .font(.largeTitle)
                                Text("Findet den schnellsten Weg zum Ziel")
                                SlideButton(String(localized: "Benutzen"), action: {
                                    if vm.navigators >= 1 {
                                        do {
                                            let r = await vm.calculateRoute(from: LocationManager.shared.lastLocation!.coordinate, to: btManager.targetLocation!, type: .walking)
                                            if r != nil {
                                                vm.navigators -= 1
                                                vm.navigatedRoute = r!
                                            }
                                        }
                                    }
                                })
                                .disabled(vm.navigators == 0)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: ContainerRelativeShape())
                    .padding()
                } else if vm.inGameTab == 2 {
                    VStack {
                        Toggle("Ping-Nummer zeigen", isOn: $vm.precisePingNumbers)
                        Toggle("Gelaufene Strecke zeigen", isOn: $vm.showRunLog)
                        if btManager.gameState != .paused {
                            Button("Pause") {
                                btManager.togglePause()
                            }
                        }
                        SlideButton(String(localized: "Beenden"), styling: SlideButtonStyling(indicatorColor: .red), action: {
                            btManager.triggerGameOver()
                        })
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: ContainerRelativeShape())
                    .padding()
                }
            }
            Picker("Tab", selection: $vm.inGameTab, content: {
                Label("Übersicht", systemImage: "list.bullet.clipboard")
                    .padding(.vertical)
                    .tag(0)
                Label("Inventar", systemImage: "backpack")
                    .padding(.vertical)
                    .tag(1)
                Label("Einstellungen", systemImage: "gear")
                    .padding(.vertical)
                    .tag(2)
            })
            .pickerStyle(.segmented)
            .padding()
        }
    }
}
