import SwiftUI
import CoreLocation
import SkimUI

@main
struct SombiesApp: App {
    @ObservedObject var vm = ContentViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .installToasts(position: .top)
        }
    }
}

struct Run: Codable, Identifiable, Hashable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var track: [CLLocationCoordinate2D]

    private enum CodingKeys: String, CodingKey {
        case id
        case startDate
        case endDate
        case track
    }

    private struct CoordinateDTO: Codable {
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
    }

    init(id: UUID, startDate: Date, endDate: Date, track: [CLLocationCoordinate2D]) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.track = track
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        let dtos = try container.decode([CoordinateDTO].self, forKey: .track)
        track = dtos.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        let dtos = track.map { CoordinateDTO(latitude: $0.latitude, longitude: $0.longitude) }
        try container.encode(dtos, forKey: .track)
    }

    // MARK: - Equatable
    static func == (lhs: Run, rhs: Run) -> Bool {
        // Consider runs equal if all properties match
        guard lhs.id == rhs.id,
              lhs.startDate == rhs.startDate,
              lhs.endDate == rhs.endDate,
              lhs.track.count == rhs.track.count else { return false }
        // Compare coordinates element-wise
        for (l, r) in zip(lhs.track, rhs.track) {
            if l.latitude != r.latitude || l.longitude != r.longitude { return false }
        }
        return true
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(startDate)
        hasher.combine(endDate)
        // Combine each coordinate's components
        for coord in track {
            hasher.combine(coord.latitude)
            hasher.combine(coord.longitude)
        }
    }
}
