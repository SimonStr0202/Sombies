import SwiftUI

struct ContentView: View {
    let connector = WatchConnector.shared
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .foregroundStyle(.red)
                    .opacity(0.3)
                Circle()
                    .scaleEffect(connector.lastReceivedZombieDistance / 100)
            }
            Text("\(Int(connector.lastReceivedZombieDistance))m")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
