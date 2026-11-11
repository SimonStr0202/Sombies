import SwiftUI
import extendedSyntax
import MapKit
import Combine

struct StatusBar: View {
    @Namespace var presentationCoordinator
    @ObservedObject var vm: ContentViewModel
    @ObservedObject var sessionManager: GameSessionManager = .shared
    @Environment(\.colorScheme) var colorScheme
    @State private var containerSize: CGSize = .zero
    var body: some View {
        GlassEffectContainer {
            HStack {
                Gauge(value: Math.clamp(LocationManager.shared.speedInKmh, min: 0, max: vm.antiCheatLimit), in: 0...vm.antiCheatLimit, label: {
                    Text("\(Int(LocationManager.shared.speedInKmh))")
                        .contentTransition(.numericText())
                        .foregroundStyle(modeColor())
                })
                .gaugeStyle(.accessoryCircularCapacity)
                .frame(width: containerSize.width, height: containerSize.height)
                .animation(.linear, value: LocationManager.shared.speedInKmh)
                .tint(modeColor())
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("currentSpeed", in: presentationCoordinator)
                .padding(.leading)
                .onAppear {
                    containerSize = sizeOfGauge()
                }
                .onReceive(vm.gameTimr, perform: { _ in
                    if LocationManager.shared.speedInKmh > vm.antiCheatLimit {
                        withAnimation {
                            vm.antiCheatLoad += 0.04
                        }
                        if vm.antiCheatLoad > 1 {
                            sessionManager.triggerGameOver()
                            vm.antiCheatLoad = 0
                        }
                    } else {
                        withAnimation {
                            vm.antiCheatLoad = Math.clamp(vm.antiCheatLoad - 0.02, min: 0, max: 1)
                        }
                    }
                })
                if vm.antiCheatLoad > 0.01 {
                    Gauge(value: Math.clamp(vm.antiCheatLoad, min: 0, max: 1), in: 0...1, label: {
                        Text("\(Int(vm.antiCheatLoad * 100))")
                            .contentTransition(.numericText())
                            .foregroundStyle(modeColor())
                    })
                    .gaugeStyle(.accessoryCircularCapacity)
                    
                    .tint(modeColor())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("antiCheatLoad", in: presentationCoordinator)
                }
                if sessionManager.gameState == .paused {
                    Button("Fortsetzen", systemImage: "play.fill") {
                        sessionManager.resumeGame()
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .contentShape(Rectangle())
                    .overlay(content: {
                        Circle()
                            .inset(by: 2.5)
                            .stroke(lineWidth: 5)
                            .fill(modeColor().opacity(0.35))
                            .allowsHitTesting(false)
                    })
                    .tint(modeColor())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("resumeButton", in: presentationCoordinator)
                    .onTapGesture {
                        sessionManager.resumeGame()
                    }
                }
                Spacer()
            }
            .animation(.linear, value: sessionManager.gameState)
        }
    }
    func sizeOfGauge() -> CGSize {
        let view = Gauge(value: 0, label: {}).gaugeStyle(.accessoryCircularCapacity)
        let renderer = ImageRenderer(content: view)
        return renderer.uiImage?.size ?? .zero
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
    ZStack {
        Color.red
            .ignoresSafeArea()
        StatusBar(vm: ContentViewModel(), sessionManager: GameSessionManager.shared)
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}
