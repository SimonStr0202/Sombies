//  SombiesWidgetsAttributes.swift
//  Sombies
//
//  Auto-created to fix missing type error in ZombieActivityManager.

import Foundation

#if canImport(ActivityKit)
import ActivityKit

// Attributes for the Sombies Live Activity
@available(iOS 16.1, macOS 13.0, watchOS 9.0, tvOS 16.1, *)
struct SombiesWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state for the Live Activity
        var distance: Int
        var statusText: String
        var ping: Int
    }

    // Static attributes for the activity
    var gameName: String
}

#else

// Fallback so code can compile when ActivityKit isn't available
struct SombiesWidgetsAttributes {
    struct ContentState: Codable, Hashable {
        var distance: Int
        var statusText: String
        var ping: Int
    }
    var gameName: String
}

#endif
