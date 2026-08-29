import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, macOS 13.0, watchOS 9.0, tvOS 16.1, *)
@MainActor
struct SombiesWidgetsAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var ping: Int
        var health: Double
    }
    var gameName: String
}

#else

struct SombiesWidgetsAttributes {
    struct ContentState: Codable, Hashable {
        var ping: Int
        var health: Double
    }
    var gameName: String
}

#endif
