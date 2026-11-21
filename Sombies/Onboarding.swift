import SwiftUI
import CoreLocation
import Combine
import SkimUI
import CoreBluetooth

enum OnboardingScreen: Int, CaseIterable, Identifiable {
    case intro
    case welcomeGuides
    case permissions
    case bluetoothPermission
    case startScreen

    var id: Int { rawValue }

    var next: OnboardingScreen? {
        OnboardingScreen(rawValue: rawValue + 1)
    }
}

@MainActor
final class LocationPermissionCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionCoordinator()

    let manager = CLLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func refreshStatus() {
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestWhenInUseAndWait() async -> CLAuthorizationStatus {
        refreshStatus()

        guard authorizationStatus == .notDetermined else {
            return authorizationStatus
        }

        return await withCheckedContinuation { continuation in
            permissionContinuation?.resume(returning: authorizationStatus)
            permissionContinuation = continuation

            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = newStatus
            
            guard newStatus != .notDetermined else { return }

            if let continuation = self.permissionContinuation {
                self.permissionContinuation = nil
                continuation.resume(returning: newStatus)
            }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var vm: ContentViewModel
    @State private var currentScreen: OnboardingScreen = .intro
    @State private var isVisible = false
    @State private var isTransitioning = false
    @State private var isRequestingPermission = false
    @State private var acceptPrivacy = false
    @State private var acceptTerms = false

    @StateObject private var locationCoordinator = LocationPermissionCoordinator.shared
    @ObservedObject private var bluetoothManager = BluetoothManager.shared

    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            backgroundLayer

            Group {
                switch currentScreen {
                case .intro:
                    introView
                case .welcomeGuides:
                    welcomeGuidesView
                case .permissions:
                    requestLocationView
                case .bluetoothPermission:
                    requestBluetoothView
                case .startScreen:
                    finalScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blurFade(active: isVisible)
            .allowsHitTesting(!isTransitioning && !isRequestingPermission)
        }
        .task(id: currentScreen) {
            if currentScreen == .permissions {
                locationCoordinator.refreshStatus()
            }
            if currentScreen == .bluetoothPermission {
                bluetoothManager.refreshBluetoothAuthorization()
            }
            isVisible = false
            isTransitioning = false
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.65)) {
                isVisible = true
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.green.opacity(isVisible ? 0.16 : 0.05),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.8), value: isVisible)
        }
    }
    
    private var finalScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(alignment: isVisible ? .leading : .center, spacing: 6) {
                Text("Willkommen bei")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Sombies")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.green.gradient)
            }
            .frame(maxWidth: .infinity, alignment: isVisible ? .leading : .center)
            .padding(.horizontal, 28)

            Spacer()
            VStack(spacing: 12) {
                ConsentRowView(
                    isAccepted: $acceptPrivacy,
                    prefixText: "Ich stimme den",
                    linkTitle: "Datenschutzbestimmungen",
                    linkURL: URL(string: "https://homepage.stroebele-simon.workers.dev/products/SombiesDetailPage/PrivacyPolicy/"),
                    suffixText: "zu."
                )

                ConsentRowView(
                    isAccepted: $acceptTerms,
                    prefixText: "Ich stimme den",
                    linkTitle: "Nutzungsbedingungen",
                    linkURL: URL(string: "https://homepage.stroebele-simon.workers.dev/products/SombiesDetailPage/Terms/"),
                    suffixText: "zu."
                )
            }
            
            primaryActionButton(title: "Loslegen") {
                transitionToNextScreen()
            }
            .disabled(!acceptTerms || !acceptPrivacy)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(alignment: isVisible ? .leading : .center, spacing: 6) {
                Text("Willkommen bei")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Sombies")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.green.gradient)
            }
            .frame(maxWidth: .infinity, alignment: isVisible ? .leading : .center)
            .padding(.horizontal, 28)

            Spacer()

            primaryActionButton(title: "Weiter") {
                transitionToNextScreen()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var welcomeGuidesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Das erwartet dich")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text("Ein kurzer Überblick, was du in Sombies alles machen kannst.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                
                VStack(spacing: 14) {
                    ForEach(Array(GuideItem.sombiesGuides.enumerated()), id: \.element.id) { index, guide in
                        GuideRowView(guide: guide)
                            .blur(radius: isVisible ? 0 : 8)
                            .opacity(isVisible ? 1 : 0)
                            .offset(y: isVisible ? 0 : 12)
                            .animation(
                                .smooth(duration: 0.5).delay(Double(index) * 0.08),
                                value: isVisible
                            )
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .safeAreaInset(edge: .bottom, content: {
                primaryActionButton(title: "Weiter") {
                    transitionToNextScreen()
                }
                .padding(.bottom, 16)
            })
        }
    }

    private var requestLocationView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: locationIconName)
                .font(.system(size: 54))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: isVisible)

            VStack(spacing: 8) {
                Text("Standortzugriff")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(locationSubtitleText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                Task {
                    await handleLocationContinue()
                }
            } label: {
                HStack(spacing: 10) {
                    if isRequestingPermission {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(locationButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .disabled(isRequestingPermission || isTransitioning)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .onAppear {
            locationCoordinator.refreshStatus()
        }
    }

    private var requestBluetoothView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: bluetoothIconName)
                .font(.system(size: 54))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: isVisible)

            VStack(spacing: 8) {
                Text("Bluetooth-Zugriff")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(bluetoothSubtitleText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                Task {
                    await handleBluetoothContinue()
                }
            } label: {
                HStack(spacing: 10) {
                    if isRequestingPermission {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(bluetoothButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
            .disabled(isRequestingPermission || isTransitioning)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var bluetoothIconName: String {
        switch bluetoothManager.bluetoothAuthorization {
        case .allowedAlways:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "bluetooth.slash"
        case .notDetermined:
            return "bluetooth"
        @unknown default:
            return "bluetooth"
        }
    }

    private var bluetoothSubtitleText: String {
        switch bluetoothManager.bluetoothAuthorization {
        case .allowedAlways:
            return "Bluetooth ist freigegeben. Du kannst direkt fortfahren."
        case .denied, .restricted:
            return "Bluetooth ist derzeit nicht freigegeben. Du kannst die Berechtigung jederzeit in den iOS-Einstellungen ändern."
        case .notDetermined:
            return "Bluetooth wird benötigt, um ohne WLAN mit Freunden in der Nähe zu spielen. Die Abfrage erscheint erst, wenn du hier auf „Bluetooth erlauben“ tippst."
        @unknown default:
            return "Bluetooth wird für lokale Mehrspielerpartien benötigt."
        }
    }

    private var bluetoothButtonTitle: String {
        switch bluetoothManager.bluetoothAuthorization {
        case .allowedAlways:
            return "Weiter"
        case .denied, .restricted:
            return "Ohne Bluetooth weiter"
        case .notDetermined:
            return isRequestingPermission ? "Warte auf Auswahl…" : "Bluetooth erlauben"
        @unknown default:
            return "Weiter"
        }
    }

    private func handleBluetoothContinue() async {
        guard !isRequestingPermission && !isTransitioning else { return }

        if bluetoothManager.bluetoothAuthorization == .notDetermined {
            isRequestingPermission = true
            _ = await bluetoothManager.requestBluetoothPermissionAndWait()
            isRequestingPermission = false
            try? await Task.sleep(for: .milliseconds(180))
        }

        transitionToNextScreen()
    }

    private var locationIconName: String {
        switch locationCoordinator.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "location.fill.checkmark"
        case .denied, .restricted:
            return "location.slash.fill"
        case .notDetermined:
            return "location.fill"
        @unknown default:
            return "location.fill"
        }
    }

    private var locationSubtitleText: String {
        switch locationCoordinator.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Dein Standortzugriff ist bereits aktiviert. Du kannst direkt fortfahren."
        case .denied, .restricted:
            return "Der Standortzugriff ist aktuell deaktiviert. Du kannst ihn jederzeit in den iOS-Einstellungen ändern."
        case .notDetermined:
            return "Die App benötigt für die meisten Funktionen deinen Standort."
        @unknown default:
            return "Die App benötigt für die meisten Funktionen deinen Standort."
        }
    }

    private var locationButtonTitle: String {
        switch locationCoordinator.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Weiter"
        case .denied, .restricted:
            return "Ohne Standort weiter"
        case .notDetermined:
            return isRequestingPermission ? "Warte auf Auswahl…" : "Standort erlauben"
        @unknown default:
            return "Weiter"
        }
    }

    private func handleLocationContinue() async {
        guard !isRequestingPermission && !isTransitioning else { return }

        if locationCoordinator.authorizationStatus == .notDetermined {
            isRequestingPermission = true
            _ = await locationCoordinator.requestWhenInUseAndWait()
            isRequestingPermission = false

            try? await Task.sleep(for: .milliseconds(180))
        }

        transitionToNextScreen()
    }


    private func primaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .tint(.green)
    }

    private func transitionToNextScreen() {
        guard !isTransitioning else { return }
        isTransitioning = true

        withAnimation(.easeInOut(duration: 0.42)) {
            isVisible = false
        }

        Task {
            try? await Task.sleep(for: .milliseconds(430))
            if let nextScreen = currentScreen.next {
                currentScreen = nextScreen
            } else {
                onFinish()
                withAnimation(.easeInOut(duration: 3)) {
                    vm.showOnboarding = false
                }
            }
        }
    }
}


private struct BlurFadeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 0 : 14)
            .opacity(active ? 1 : 0)
            .scaleEffect(active ? 1 : 0.97)
    }
}

private extension View {
    func blurFade(active: Bool) -> some View {
        modifier(BlurFadeModifier(active: active))
    }
}

struct GuideItem: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let description: String

    static let sombiesGuides: [GuideItem] = [
        GuideItem(
            icon: "sparkles",
            tint: .green,
            title: "Fit bleiben",
            description: "Renne vor virtuellen Punkten weg."
        ),
        GuideItem(
            icon: "person.2.fill",
            tint: .mint,
            title: "Spiele mit Freunden",
            description: "Du kannst mit Bluetooth mit Leuten in der Nähe spielen"
        ),
        GuideItem(
            icon: "star.fill",
            tint: .teal,
            title: "Entdecke Orte",
            description: "Vielleicht findest du bald dein neues Lieblingscafé oder deine neue Lieblingsbäckerei."
        ),
        GuideItem(
            icon: "person.badge.shield.checkmark.fill",
            tint: .cyan,
            title: "Um Privatsphäre gebaut",
            description: "Wir wissen nichts über dich. Selbst wenn die App aktiv genutzt wird, werden wir nicht wissen, wo du bist oder mit wem du dich triffst."
        )
    ]
}

struct GuideRowView: View {
    let guide: GuideItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: guide.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(guide.tint)
                .frame(width: 44, height: 44)
                .background(guide.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(guide.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ConsentRowView: View {
    @Binding var isAccepted: Bool
    let prefixText: String
    let linkTitle: String
    let linkURL: URL?
    let suffixText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: $isAccepted) {
                EmptyView()
            }
            .toggleStyle(.check)
            .labelsHidden()

            consentLabel
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var consentLabel: some View {
        let markdownString: String
        if let linkURL {
            markdownString = "\(prefixText) [\(linkTitle)](\(linkURL.absoluteString)) \(suffixText)"
        } else {
            markdownString = "\(prefixText) \(linkTitle) \(suffixText)"
        }

        return Text(.init(markdownString))
            .font(.subheadline)
            .tint(.green)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    OnboardingView(vm: ContentViewModel())
}
