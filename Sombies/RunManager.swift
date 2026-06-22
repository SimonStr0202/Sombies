import Foundation
import Combine
import SwiftUI
import CoreLocation
import OSLog
import os

class RunManager: ObservableObject {
    static let shared = RunManager()
    @Published var savedRuns: [Run] = []
    private var fileURL: URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent("saved_runs.json")
    }
    
    init() {
        loadRuns()
    }
    
    func saveRun(_ run: Run) {
        savedRuns.append(run)
        persistToDisk()
    }
    
    private func persistToDisk() {
        do {
            let data = try JSONEncoder().encode(savedRuns)
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
            Logger.system.info("Lauf erfolgreich gespeichert!")
        } catch {
            Logger.system.error("Speicherfehler: \(error.localizedDescription)")
        }
    }
    
    func loadRuns() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Run].self, from: data)
            DispatchQueue.main.async {
                self.savedRuns = decoded
            }
        } catch {
            Logger.system.error("Ladefehler: \(error.localizedDescription)")
        }
    }
    
    func deleteRun(at indexSet: IndexSet) {
        savedRuns.remove(atOffsets: indexSet)
        persistToDisk()
    }
}

extension RunManager {
    var groupedRuns: [(Date, [Run])] {
        let grouped = Dictionary(grouping: savedRuns) { (run: Run) -> Date in
            Calendar.current.startOfDay(for: run.startDate)
        }
        return grouped.sorted { $0.key > $1.key }
    }
}

extension RunManager {
    func isMergePossible(runA: Run, runB: Run) -> Bool {
        let first = runA.startDate < runB.startDate ? runA : runB
        let second = runA.startDate < runB.startDate ? runB : runA
        
        let timeGap = second.startDate.timeIntervalSince(first.endDate)
        guard abs(timeGap) <= 300 else {
            Logger.calculation.log("Zusammenführen abgelehnt: Zeitlücke zu groß (\(Int(timeGap/60)) Min)")
            return false
        }
        guard let lastCoord = first.track.last,
              let firstCoord = second.track.first else {
            Logger.calculation.log("Zusammenführen abgelehnt: Track-Daten fehlen")
            return false
        }
        
        let endPoint = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
        let startPoint = CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude)
        let distance = endPoint.distance(from: startPoint)
        
        guard distance <= 150 else {
            Logger.calculation.log("Zusammenführen abgelehnt: Distanz zu groß (\(Int(distance))m)")
            return false
        }
        return true
    }
    func mergeIfPossible(runA: Run, runB: Run) -> Run? {
        let first = runA.startDate < runB.startDate ? runA : runB
        let second = runA.startDate < runB.startDate ? runB : runA
        
        let timeGap = second.startDate.timeIntervalSince(first.endDate)
        guard abs(timeGap) <= 300 else {
            Logger.calculation.log("Zusammenführen abgelehnt: Zeitlücke zu groß (\(Int(timeGap/60)) Min)")
            return nil
        }
        guard let lastCoord = first.track.last,
              let firstCoord = second.track.first else {
            Logger.calculation.log("Zusammenführen abgelehnt: Track-Daten fehlen")
            return nil
        }
        
        let endPoint = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
        let startPoint = CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude)
        let distance = endPoint.distance(from: startPoint)
        
        guard distance <= 150 else {
            Logger.calculation.log("Zusammenführen abgelehnt: Distanz zu groß (\(Int(distance))m)")
            return nil
        }
        let combinedTrack = first.track + second.track
        
        let mergedRun = Run(
            id: first.id, 
            startDate: first.startDate, 
            endDate: second.endDate, 
            track: combinedTrack
        )
        
        Logger.calculation.info("Läufe erfolgreich zusammengeführt! Neue Distanz: \(combinedTrack.count) Punkte")
        return mergedRun
    }
    
    func replaceWithMerged(runA: Run, runB: Run) {
        if let merged = mergeIfPossible(runA: runA, runB: runB) {
            DispatchQueue.main.async {
                self.savedRuns.removeAll { $0.id == runA.id || $0.id == runB.id }
                self.saveRun(merged)
            }
        }
    }
}
