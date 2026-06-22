import SwiftUI
import MapKit

struct FeatureScreen: View {
    @ObservedObject var vm: ContentViewModel
    @State private var item: MKMapItem?
    @State private var loadingItem = false
    @State private var loadError: Error?
    @State private var furtherInformationShown = false
    @State private var currentDetent: PresentationDetent = .fraction(0.1)
    var body: some View {
        VStack {
            if vm.selectedObj != nil {
                VStack {
                    if currentDetent != .fraction(0.1) {
                        Text("\(vm.selectedObj!.title ?? "")")
                            .font(.largeTitle.bold())
                            .padding()
                        if loadingItem {
                            ProgressView()
                                .controlSize(.large)
                        } else if loadError != nil {
                            HStack {
                                Label("Ein Fehler ist aufgetreten: \(loadError?.localizedDescription ?? String(localized: "Unbekannter Fehler"))", image: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        } else if item != nil {
                            List {
                                if item?.url != nil {
                                    HStack {
                                        Text("Webseite")
                                        Spacer()
                                        Button(item!.url!.absoluteString) {
                                            UIApplication.shared.open(item!.url!)
                                        }
                                    }
                                }
                                if item?.phoneNumber != nil {
                                    HStack {
                                        Text("Telefonnummer")
                                        Spacer()
                                        Button("\(item!.phoneNumber!)") {
                                            UIApplication.shared.open(URL(string: "tel://\(item!.phoneNumber!.replacingOccurrences(of: " ", with: ""))")!)
                                        }
                                    }
                                }
                                if item?.address != nil {
                                    HStack {
                                        Text("Addresse")
                                        Spacer()
                                        Text(item!.address!.fullAddress.replacingOccurrences(of: ", ", with: "\n"))
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                                Button("Mehr...") {
                                    furtherInformationShown.toggle()
                                }
                            }
                            .scrollContentBackground(.hidden)
                        }
                        Spacer()
                        Divider()
                    }
                    Button(action: {
                        vm.newGoal = vm.selectedObj?.coordinate
                        vm.featureScreen = false
                        vm.hostingView = true
                    }, label: {
                        Text("Als Ziel verwenden")
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: currentDetent == .fraction(0.1) ? .infinity : nil)
                            .foregroundStyle(.white)
                            .bold()
                            .glassEffect(.regular.interactive().tint(.blue))
                            .contentShape(Rectangle())
                    })
                    .padding(currentDetent == .fraction(0.1) ? 0 : 15)
                    .buttonStyle(.plain)
                }
                .mapItemDetailSheet(isPresented: $furtherInformationShown, item: item ?? MKMapItem(), displaysMap: false)
                .onAppear {
                    Task {
                        do {
                            loadingItem = true
                            item = try await fetchFeatureDetails(for: vm.selectedObj!)
                            loadingItem = false
                        } catch {
                            loadingItem = false
                            loadError = error
                        }
                    }
                }
                .onChange(of: vm.selectedObj) {
                    Task {
                        do {
                            loadingItem = true
                            item = try await fetchFeatureDetails(for: vm.selectedObj!)
                            loadingItem = false
                        } catch {
                            loadingItem = false
                            loadError = error
                        }
                    }
                }
            }
        }
        .animation(.easeInOut, value: currentDetent)
        .frame(maxHeight: .infinity)
        .presentationDetents([.fraction(0.3), .fraction(0.1), .medium, .large], selection: $currentDetent)
        .presentationBackgroundInteraction(.enabled)
    }
    private func fetchFeatureDetails(for feature: MapFeature) async throws -> MKMapItem? {
        let request = MKMapItemRequest(feature: feature)
        
        return try await withCheckedThrowingContinuation { continuation in
            request.getMapItem { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }
}
