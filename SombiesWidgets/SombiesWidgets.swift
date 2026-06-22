import WidgetKit
import SwiftUI

struct CoinEntry: TimelineEntry {
    let date: Date
    let coins: Int
    let accountLevel: Int
    let levelProgress: Double
}

struct Provider: TimelineProvider {
    
    func placeholder(in context: Context) -> CoinEntry {
        CoinEntry(date: Date(), coins: 100, accountLevel: 1, levelProgress: 0.5)
    }

    func getSnapshot(in context: Context, completion: @escaping (CoinEntry) -> ()) {
        let entry = CoinEntry(date: Date(), coins: fetchSharedCoins(), accountLevel: fetchSharedAccountLevel(), levelProgress: fetchSharedLevelProgress())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CoinEntry>) -> Void) {
        let entry = CoinEntry(date: Date(), coins: fetchSharedCoins(), accountLevel: fetchSharedAccountLevel(), levelProgress: fetchSharedLevelProgress())
        
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
    
    private func fetchSharedCoins() -> Int {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.simonstr.sombies") {
            return Int(sharedDefaults.double(forKey: "widgetCoins"))
        }
        return 0
    }
    
    private func fetchSharedAccountLevel() -> Int {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.simonstr.sombies") {
            return sharedDefaults.integer(forKey: "widgetLevel")
        }
        return 0
    }
    
    private func fetchSharedLevelProgress() -> Double {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.simonstr.sombies") {
            return sharedDefaults.double(forKey: "widgetAccountProgress")
        }
        return 0
    }
}

struct SombiesWidgetsEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Spacer()
            Label("\(entry.coins)", systemImage: "brain.fill")
            Spacer()
            HStack {
                Text("\(entry.accountLevel)")
                Gauge(value: entry.levelProgress, label: {})
                Text("\(entry.accountLevel + 1)")
            }
        }
    }
}

struct SombiesWidgets: Widget {
    let kind: String = "SombiesWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                SombiesWidgetsEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                SombiesWidgetsEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Aktuelles Inventar")
        .description("Sieh dir deine Münzen und XP an")
    }
}

#Preview(as: .systemMedium) {
    SombiesWidgets()
} timeline: {
    CoinEntry(date: .now, coins: 100, accountLevel: 1, levelProgress: 0)
    CoinEntry(date: .now, coins: 250, accountLevel: 13, levelProgress: 0.8)
}
