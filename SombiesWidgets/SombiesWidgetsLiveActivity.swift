import ActivityKit
import WidgetKit
import SwiftUI

struct SombiesWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distance: Int
        var statusText: String
        var ping: Int
    }
    var gameName: String
}

struct SombiesWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SombiesWidgetsAttributes.self) { context in
            VStack {
                HStack {
                    Text("Sombies")
                        .padding(10)
                    Spacer()
                    if context.state.ping > 5 {
                        Text("\(context.state.ping)ms")
                            .padding(10)
                    }
                }
                Spacer()
                Text("Entfernung zum nächsten Zombie")
                Text("\(context.state.distance)m")
                Spacer()
            }

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Sombies")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.ping > 5 {
                        Text("\(context.state.ping)ms")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Spacer()
                    VStack {
                        Text("Entfernung zum nächsten Zombie")
                        Text("\(context.state.distance)m")
                    }
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    Spacer()
                }
            } compactLeading: {
                if context.state.ping > 5 {
                    Text("\(context.state.ping)ms")
                }
            } compactTrailing: {
                Text("\(context.state.distance)m")
            } minimal: {
                Text("\(context.state.distance)m")
            }
            .keylineTint(Color.red)
        }
    }
}

extension SombiesWidgetsAttributes {
    fileprivate static var preview: SombiesWidgetsAttributes {
        SombiesWidgetsAttributes(gameName: "World")
    }
}

extension SombiesWidgetsAttributes.ContentState {
    fileprivate static var smiley: SombiesWidgetsAttributes.ContentState {
        SombiesWidgetsAttributes.ContentState(distance: 20, statusText: "Hello", ping: 10)
     }
}

#Preview("Notification", as: .content, using: SombiesWidgetsAttributes.preview) {
   SombiesWidgetsLiveActivity()
} contentStates: {
    SombiesWidgetsAttributes.ContentState.smiley
}
#Preview("Notification", as: .dynamicIsland(.compact), using: SombiesWidgetsAttributes.preview) {
   SombiesWidgetsLiveActivity()
} contentStates: {
    SombiesWidgetsAttributes.ContentState.smiley
}
