import SwiftUI
import extendedSyntax

struct Warning: View {
    @ObservedObject var vm: ContentViewModel
    @Environment(\.colorScheme) var colorScheme
    let warning = String(localized: "Bitte sei vorsichtig, wenn du dieses Spiel spielst. Achte immer auf deine Umgebung und laufe nicht einfach auf die Straße. Achte auf dich und andere Personen.")
    @State var countdown = 5
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .foregroundStyle(.yellow)
                .font(.system(size: 50))
            Text("Bevor du spielst".uppercased())
                .font(.system(.largeTitle, weight: .bold))
            Text(warning)
                .multilineTextAlignment(.center)
            VStack {
                Button(action: {
                    if vm.warningType == 0 {
                        vm.hostingView = true
                    } else {
                        vm.joiningView = true
                    }
                    vm.warningShown = false
                    vm.lastWarning = Date()
                }, label: {
                    Text("OK \(countdown > 0 ? "(\(countdown))" : "")")
                        .foregroundStyle(modeColor())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.tint(.blue).interactive(), in: RoundedRectangle(cornerRadius: 15))
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .saturation(countdown > 0 ? 0 : 1)
                })
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { timer in
                        countdown -= 1
                        if countdown <= 0 {
                            timer.invalidate()
                        }
                    })
                }
                .disabled(countdown > 0)
                Button(action: {
                    vm.hostingView = false
                    vm.joiningView = false
                    vm.warningShown = false
                }, label: {
                    Text("Zurück")
                        .foregroundStyle(modeColor())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 15))
                        .font(.system(.body, design: .rounded, weight: .bold))
                })
            }
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
        .padding()
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
    Warning(vm: ContentViewModel())
}
