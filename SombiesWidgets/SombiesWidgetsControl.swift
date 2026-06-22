import AppIntents
import SwiftUI
import WidgetKit

struct SombiesWidgetsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "self.edu.Sombies.SombiesWidgets",
            provider: Provider()
        ) { value in
            ControlWidgetButton(action: StartTimerIntent(), label: {Label("Sombies starten", systemImage: "figure.run")})
            { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Sombies öffnen")
        .description("Öffnet die App Sombies")
    }
}

extension SombiesWidgetsControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = true // Check if the timer is running
            return isRunning
        }
    }
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Spiel Starten"

    @Parameter(title: "")
    var value: Bool
    static var supportedModes: IntentModes = .foreground(.immediate)

    func perform() async throws -> some IntentResult {
        // Start / stop the timer based on `value`.
        return .result()
    }
}
