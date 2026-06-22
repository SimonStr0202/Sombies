import SwiftUI
import extendedSyntax

struct BottomButtons:View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var vm: ContentViewModel
    @AppStorage("userName") var userName = UIDevice.current.name
    var body: some View {
        GlassEffectContainer {
            HStack {
                Button("Du", systemImage: "person.fill") {
                    vm.newName = userName
                    vm.profileShown.toggle()
                }
                .labelStyle(.iconOnly)
                .padding()
                .foregroundStyle(modeColor())
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())
                Button("Beitreten", systemImage: "iphone.and.arrow.forward.inward") {
                    if vm.lastWarning == nil || Math.toPositive(vm.lastWarning?.timeIntervalSinceNow ?? 0) > 2592000 {
                        vm.warningShown = true
                        vm.warningType = 1
                    } else {
                        vm.joiningView.toggle()
                    }
                }
                .padding()
                .foregroundStyle(modeColor())
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())
                Spacer()
                Button("Spielen", systemImage: "play.fill") {
                    if vm.lastWarning == nil || Math.toPositive(vm.lastWarning?.timeIntervalSinceNow ?? 0) > 2592000 {
                        vm.warningShown = true
                        vm.warningType = 0
                    } else {
                        vm.hostingView.toggle()
                    }
                }
                .padding()
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive().tint(.blue), in: Capsule())
                .contentShape(Capsule())
            }
        }
    }
    func modeColor() -> Color {
        if colorScheme == .dark {
            return .white
        } else {
            return .black
        }
    }
}
