import SwiftUI
import MapKit
import SlideButton
import HealthKit

struct RunDetailView: View {
    @ObservedObject var vm: ContentViewModel
    @ObservedObject var runManager = RunManager.shared
    @State var addAsAlertShown = false
    @State var selectedType: HKWorkoutActivityType?
    @State private var selectionContinuation: CheckedContinuation<HKWorkoutActivityType?, Never>?
    let run: Run
    var body: some View {
        VStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: run.track.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                MapPolyline(coordinates: run.track)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding()
            Text(vm.formatDurationR(from: run.startDate, to: run.endDate))
                .font(.largeTitle.bold())
                .padding(.bottom)
            SlideButton(action: {
                addAsAlertShown = true
                let type = await awaitSelection()
                guard let type else {
                    // User cancelled or dismissed without selecting
                    selectedType = nil
                    return
                }
                await vm.saveRunningWorkout(
                    startDate: run.startDate,
                    endDate: run.endDate,
                    distanceInMeters: run.track.totalDistance(),
                    locations: run.track.map { $0.location() },
                    type: type
                )
                selectedType = nil
            }, label: {
                Text("Zu Health hinzufügen...")
                    .bold()
            })
            .padding(.horizontal)
            .confirmationDialog("Typ", isPresented: $addAsAlertShown, actions: {
                Button("Gehen Outdoor") {
                    selectedType = .walking
                    if let continuation = selectionContinuation {
                        continuation.resume(returning: .walking)
                        selectionContinuation = nil
                        addAsAlertShown = false
                    }
                }
                Button("Laufen Outdoor") {
                    selectedType = .running
                    if let continuation = selectionContinuation {
                        continuation.resume(returning: .running)
                        selectionContinuation = nil
                        addAsAlertShown = false
                    }
                }
                Button("Rad outdoor") {
                    selectedType = .cycling
                    if let continuation = selectionContinuation {
                        continuation.resume(returning: .cycling)
                        selectionContinuation = nil
                        addAsAlertShown = false
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    if let continuation = selectionContinuation {
                        continuation.resume(returning: nil)
                        selectionContinuation = nil
                    }
                    addAsAlertShown = false
                }
            }, message: { Text("Als was zu Health hinzufügen?") })
        }
    }
    
    private func awaitSelection() async -> HKWorkoutActivityType? {
        await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkoutActivityType?, Never>) in
            self.selectionContinuation = continuation
        }
    }
}

#Preview {
    RunDetailView(vm: ContentViewModel(), runManager: RunManager(), run: Run(id: UUID(), startDate: Date(), endDate: Date(), track: []))
}

extension CLLocationCoordinate2D {
    func location() -> CLLocation {
        return CLLocation(latitude: self.latitude, longitude: self.longitude)
    }
}
