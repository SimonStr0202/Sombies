import SwiftUI
import SlideButton
import MapKit
import extendedSyntax
import OSLog
import GameCenterKit
import Shimmer

struct ProfileView: View {
    @ObservedObject var vm: ContentViewModel
    @StateObject var locManager = LocationManager.shared
    @ObservedObject var runManager = RunManager.shared
    @ObservedObject var shopManager: StoreManager
    @Environment(\.colorScheme) var colorScheme
    @State private var multiSelection = Set<Run>()
    @State private var runsLocked = false
    @State private var authenticatingRuns = false
    
    private var canMergeSelected: Bool {
        if multiSelection.count == 2 {
            let new = Array(multiSelection)
            return runManager.isMergePossible(runA: new[0], runB: new[1])
        } else {
            return false
        }
    }
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView(.vertical) {
                    ZStack {
                        PhysicsBallView(multiplier: Int(Math.clamp(vm.coins, min: 0, max: 70)), content: {
                            ZStack {
                                Circle()
                                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
                                Image(systemName: "brain.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            }
                        })
                        .id(vm.coins)
                        .background(RoundedRectangle(cornerRadius: 20).fill(.gray.opacity(0.2)))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "brain.fill")
                                Text("\(Int(vm.coins))")
                            }
                            .padding()
                            .glassEffect(.regular)
                            .padding()
                        }
                    }
                    .frame(width: 300, height: 450)
                    .onAppear {
                        runManager.loadRuns()
                    }
                    .alert("Name ändern", isPresented: $vm.nameAlert, actions: {
                        TextField("Name eingeben", text: $vm.newName)
                        Button(role: .confirm) {
                            vm.nameAlert = false
                            vm.userName = vm.newName
                        }
                        .background(.blue)
                        .disabled(vm.newName.isEmpty)
                        Button(role: .cancel) {}
                    }, message: { Text("Du hannst hier deinen Namen ändern") })
                    NavigationLink(destination: {
                        Shop(vm: vm, shopManager: shopManager)
                    }, label: {
                        HStack {
                            Text("Shop")
                                .foregroundStyle(modeColor())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(modeColor())
                        }
                    })
                    .padding()
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                    .padding()
                    NavigationLink(destination: {
                        SeasonPassView(vm: vm)
                    }, label: {
                        HStack {
                            Text("SomPass")
                                .foregroundStyle(modeColor())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(modeColor())
                        }
                    })
                    .padding()
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                    .padding()
                    NavigationLink(destination: {
                        Settings(vm: vm)
                    }, label: {
                        HStack {
                            Text("Einstellungen")
                                .foregroundStyle(modeColor())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(modeColor())
                        }
                    })
                    .padding()
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading, content: {
                    NavigationLink(destination: {
                        NavigationStack {
                            List(Array(runManager.savedRuns.sorted(by: { $0.startDate > $1.startDate })), selection: $multiSelection) { run in
                                NavigationLink(destination: {
                                    RunDetailView(vm: vm, run: run)
                                }, label: {
                                    RunLabel(vm: vm, run: run)
                                        .redacted(reason: runsLocked ? .placeholder : .init(rawValue: 0))
                                })
                                .tag(run)
                                .disabled(runsLocked)
                            }
                            .onAppear {
                                if vm.runsLocked {
                                    runsLocked = true
                                    authenticatingRuns = true
                                    Task {
                                        do {
                                            try await vm.authenticateUser()
                                            authenticatingRuns = false
                                            runsLocked = false
                                        } catch {
                                            authenticatingRuns = false
                                        }
                                    }
                                } else {
                                    runsLocked = false
                                    authenticatingRuns = false
                                }
                            }
                            .navigationTitle("Deine Läufe")
                            .toolbar {
                                if !runsLocked {
                                    ToolbarItemGroup(placement: .topBarLeading, content: {
                                        EditButton()
                                            .labelStyle(.iconOnly)
                                    })
                                    ToolbarItemGroup(placement: .bottomBar, content: {
                                        Menu("Löschen", systemImage: "trash") {
                                            Button("Löschen bestätigen") {
                                                let idToIndex = Dictionary(uniqueKeysWithValues:
                                                                            runManager.savedRuns.enumerated().map { ($1.id, $0) }
                                                )
                                                let indexes = IndexSet(
                                                    multiSelection.compactMap { idToIndex[$0.id] }
                                                )
                                                runManager.deleteRun(at: indexes)
                                            }
                                        }
                                        Menu("Zusammenfügen", systemImage: "text.append") {
                                            Button("Zusammenfügen bestätigen", systemImage: "text.append") {
                                                let new = Array(multiSelection)
                                                runManager.replaceWithMerged(runA: new[0], runB: new[1])
                                            }
                                        }
                                        .disabled(!canMergeSelected)
                                    })
                                }
                            }
                        }
                    }, label: {
                        Label("Laufhistorie", systemImage: "list.bullet.clipboard.fill")
                    })
                })
                ToolbarItem(placement: .principal, content: {
                    Button(action: {
                        vm.nameAlert.toggle()
                    }, label: {
                        VStack {
                            HStack {
                                Text(vm.userName)
                                Image(systemName: "pencil")
                            }
                            .bold()
                            HStack {
                                Text("\(vm.accountLevel)")
                                ProgressView(value: vm.accountLevelProgress)
                            }
                        }
                    })
                })
                ToolbarItem(placement: .topBarTrailing, content: {
                    Button("Schließen", systemImage: "xmark") {
                        vm.profileShown.toggle()
                    }
                })
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    func modeColor() -> Color {
        if colorScheme == .dark {
            return .white
        } else {
            return .black
        }
    }
}

struct ShopSlot: Identifiable {
    let id = UUID()
    let index: Int
    let itemNumber: Int     // Zufällige Artikelnummer (z.B. 91)
    let price: Int          // Zufälliger Preis
    let systemIcon: String  // z.B. "cross.case"
}

struct Shop: View {
    @ObservedObject var vm: ContentViewModel
    @StateObject var locManager = LocationManager.shared
    @ObservedObject var runManager = RunManager.shared
    @ObservedObject var shopManager: StoreManager
    
    @State private var slots: [ShopSlot] = []
    @State private var selectedIndex: Int = 0
    
    @State private var coinOffset: CGSize = .zero
    @State private var isHoveringOverSlot = false
    
    @State private var inputArticleNumber: String = ""
    @State private var inputAmount: String = "1"
    
    @State var inventoryShown: Bool = false
    
    private let shopSpaceID = "ShopSpace"
    
    private let gridColumns: [GridItem] = [
        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
    ]
    
    var body: some View {
        VStack {
            if !inventoryShown {
                VStack {
                    
                    Spacer()
                    
                    VStack {
                        LazyVGrid(columns: gridColumns) {
                            ForEach(slots, id: \.id) { slot in
                                let isSelected = selectedIndex == slot.index
                                
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.systemFill))
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                                    .aspectRatio(6/5, contentMode: .fit)
                                    .clipped()
                                    .glassEffect(.regular.tint(.orange.opacity(0.3)), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        VStack {
                                            HStack {
                                                Image(systemName: slot.systemIcon)
                                                    .imageScale(.large)
                                                    .symbolRenderingMode(.monochrome)
                                                    .font(.largeTitle)
                                                    .foregroundColor(isSelected ? .orange : .primary)
                                                HStack {
                                                    Image(systemName: "brain.fill")
                                                        .symbolRenderingMode(.monochrome)
                                                    Text("\(slot.price)")
                                                        .font(.system(size: 15, weight: .regular, design: .default))
                                                }
                                            }
                                            Divider()
                                            Text("\(slot.itemNumber)")
                                                .font(.system(.title, weight: .bold))
                                        }
                                    }
                                    .onTapGesture {
                                        selectedIndex = slot.index
                                        inputArticleNumber = String(slot.itemNumber)
                                    }
                            }
                        }
                        .padding()
                        
                        HStack {
                            HStack {
                                TextField("Nr.", text: $inputArticleNumber)
                                    .keyboardType(.numberPad)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.center)
                                    .onChange(of: inputArticleNumber) { _, newValue in
                                        if let matchedSlot = slots.first(where: { String($0.itemNumber) == newValue }) {
                                            selectedIndex = matchedSlot.index
                                        }
                                    }
                                
                                Divider()
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                TextField("Anzahl", text: $inputAmount)
                                    .keyboardType(.numberPad)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .glassEffect(.regular.interactive(), in: .capsule(style: .continuous))
                            
                            Spacer()
                            
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .frame(width: 100, height: 20)
                                .clipped()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isHoveringOverSlot ? Color.orange : Color.clear, lineWidth: 1)
                                    
                                    Text(isHoveringOverSlot ? "LOSLASSEN" : "Münze einwerfen".uppercased())
                                        .foregroundStyle(isHoveringOverSlot ? .orange : .gray)
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                }
                        }
                        .padding(.horizontal)
                        
                    }
                    .coordinateSpace(name: shopSpaceID)
                    
                    Spacer()
                    
                    HStack {
                        ZStack {
                            Image(systemName: "brain.fill")
                                .symbolRenderingMode(.monochrome)
                                .font(.title3)
                                .padding()
                                .background {
                                    LinearGradient(gradient: Gradient(colors: [.orange, .yellow]), startPoint: .top, endPoint: .bottom)
                                        .clipShape(Circle())
                                }
                                .offset(coinOffset)
                                .gesture(
                                    DragGesture(coordinateSpace: .named(shopSpaceID))
                                        .onChanged { gesture in
                                            coinOffset = gesture.translation
                                            isHoveringOverSlot = gesture.location.x > 180 && gesture.location.y < -10
                                        }
                                        .onEnded { _ in
                                            if isHoveringOverSlot {
                                                executePurchase()
                                            }
                                            withAnimation(.bouncy) {
                                                coinOffset = .zero
                                                isHoveringOverSlot = false
                                            }
                                        }
                                )
                        }
                        Text("x\(Int(vm.coins))")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                }
                .transition(.move(edge: .top).combined(with: .blurReplace))
            }
            Button(action: {
                withAnimation {
                    inventoryShown.toggle()
                }
            }, label: {
                HStack {
                    Image(systemName: "chevron.up")
                        .symbolRenderingMode(.monochrome)
                        .rotationEffect(Angle(degrees: inventoryShown ? 180: 0))
                    Text("Inventar")
                }
            })
            .buttonStyle(.automatic)
            .controlSize(.regular)
            if inventoryShown {
                //VStack {
                    List {
                        LabeledContent(content: {
                            Text("x\(vm.medkits)")
                        }, label: {
                            Label("Erste Hilfe Kasten", systemImage: "cross.case.fill")
                        })
                        LabeledContent(content: {
                            Text("x\(vm.navigators)")
                        }, label: {
                            Label("Navigator", systemImage: "point.topleft.filled.down.to.point.bottomright.curvepath")
                        })
                    }
                //}
                .transition(.move(edge: .bottom).combined(with: .blurReplace))
            }
        }
        .onAppear {
            if slots.isEmpty {
                var tempSlots: [ShopSlot] = []
                for idx in 0...8 {
                    let itemNum = Int.random(in: 10...99)
                    let price = idx % 2 == 0 ? 30 : 5
                    let icon = idx % 2 == 0 ? "cross.case" : "point.topleft.filled.down.to.point.bottomright.curvepath"
                    
                    tempSlots.append(ShopSlot(index: idx, itemNumber: itemNum, price: price, systemIcon: icon))
                }
                self.slots = tempSlots
                
                if let first = tempSlots.first {
                    inputArticleNumber = String(first.itemNumber)
                }
            }
        }
    }
    
    private func executePurchase() {
        guard !slots.isEmpty, slots.indices.contains(selectedIndex) else { return }
        let selectedSlot = slots[selectedIndex]
        
        let amountToBuy = max(1, Int(inputAmount) ?? 1)
        let totalCost = Double(selectedSlot.price * amountToBuy)
        
        if vm.coins >= totalCost {
            vm.coins -= totalCost
            
            if selectedSlot.systemIcon == "cross.case" {
                vm.medkits += amountToBuy
            } else {
                vm.navigators += amountToBuy
            }
            
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

#Preview {
    ProfileView(vm: ContentViewModel(), shopManager: StoreManager())
}

struct RunLabel: View {
    let vm: ContentViewModel
    let run: Run
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(run.startDate.formatted(date: .omitted, time: .shortened))
                Text(vm.formatDurationR(from: run.startDate, to: run.endDate))
                    .font(.caption2.width(.expanded))
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(formatDistance(meters: run.track.totalDistance()))")
                let dateString = run.startDate.formatted(date: .long, time: .omitted)
                Text(dateString)
                    .font(.caption2.width(.expanded))
            }
        }
    }
    func formatDistance(meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }
}


extension Array where Element == CLLocationCoordinate2D {
    func totalDistance() -> Double {
        guard self.count > 1 else { return 0.0 }
        
        var total: Double = 0.0
        
        for i in 0..<self.count - 1 {
            let start = CLLocation(latitude: self[i].latitude, longitude: self[i].longitude)
            let end = CLLocation(latitude: self[i+1].latitude, longitude: self[i+1].longitude)
            
            total += start.distance(from: end)
        }
        
        return total
    }
}

import Toasts

struct OpenSources: View {
    @Environment(\.presentToast) var presentToast
    var body: some View {
        List {
            NavigationLink("SlideButton", destination: {
                TabView {
                    Tab("Lizenz", systemImage: "sparkle.text.clipboard", content: {
                        ScrollView {
                            Text(readBundleFile(name: "LICENSE_SLIDEBUTTON") ?? String(localized: "Lizenz nicht vorhanden"))
                                .monospaced()
                                .padding()
                        }
                    })
                    Tab("Beispiel", systemImage: "star.hexagon", content: {
                        VStack {
                            SlideButton("", action: {
                                do {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                }
                            })
                        }
                        .padding()
                    })
                }
                .navigationTitle("SlideButton")
            })
            NavigationLink("GameCenterKit", destination: {
                TabView {
                    ScrollView {
                        Text(readBundleFile(name: "LICENSE_GAMECENTERKIT") ?? String(localized: "Lizenz nicht vorhanden"))
                            .monospaced()
                            .padding()
                    }
                }
                .navigationTitle("GameCenterKit")
            })
            NavigationLink("swiftui-toasts", destination: {
                TabView {
                    Tab("Lizenz", systemImage: "sparkle.text.clipboard", content: {
                        ScrollView {
                            Text(readBundleFile(name: "LICENSE_SWIFTUITOASTS") ?? String(localized: "Lizenz nicht vorhanden"))
                                .monospaced()
                                .padding()
                        }
                    })
                    Tab("Beispiel", systemImage: "star.hexagon", content: {
                        VStack {
                            Button("swiftui-toasts") {
                                Task {
                                    try? await presentToast(
                                        message: "Lade großartige Dinge...",
                                        task: {
                                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                                            return "Geht gut!"
                                        },
                                        onSuccess: { result in
                                            ToastValue(icon: Image(systemName: "checkmark.circle"), message: result)
                                        },
                                        onFailure: { error in
                                            ToastValue(icon: Image(systemName: "xmark.circle"), message: error.localizedDescription)
                                        }
                                    )
                                }
                            }
                        }
                        .padding()
                    })
                }
                .navigationTitle("swiftui-toasts")
            })
            NavigationLink("SwiftUI-Shimmer", destination: {
                TabView {
                    Tab("Lizenz", systemImage: "sparkle.text.clipboard", content: {
                        ScrollView {
                            Text(readBundleFile(name: "LICENSE_SWIFTUISHIMMER") ?? String(localized: "Lizenz nicht vorhanden"))
                                .monospaced()
                                .padding()
                        }
                    })
                    Tab("Beispiel", systemImage: "star.hexagon", content: {
                        VStack(alignment: .leading) {
                            Text("Ein großartiger Titel!")
                                .font(.largeTitle)
                            Text("Untertitel hierhin!")
                                .font(.title)
                            RoundedRectangle(cornerRadius: 10)
                                .opacity(0.5)
                            Text("Ein ziemlich langer Textblock, der einfach dazu da ist, um den Schimmereffekt zu visualisieren. Wenn du das hier aber lesen kannst, bist du ein großartiger Mensch! (Und sonst natürlich auch)")
                        }
                        .padding()
                        .redacted(reason: .placeholder)
                        .shimmering()
                    })
                }
                .navigationTitle("SwiftUI-Shimmer")
            })
            NavigationLink("swiftui-window-overlay", destination: {
                TabView {
                    ScrollView {
                        Text(readBundleFile(name: "LICENSE_SWIFTUIWINDOWOVERLAY") ?? String(localized: "Lizenz nicht vorhanden"))
                            .monospaced()
                            .padding()
                    }
                }
                .navigationTitle("swiftui-window-overlay")
            })
        }
        .navigationTitle("Open-Source Lizenzen")
    }
    func readBundleFile(name: String) -> String? {
        if let filepath = Bundle.main.path(forResource: name, ofType: "txt") {
            do {
                let contents = try String(contentsOfFile: filepath, encoding: .utf8)
                return contents
            } catch {
                Logger.system.error("Datei konnte nicht geladen werden: \(error.localizedDescription)")
            }
        }
        return nil
    }
}

struct Reward: Identifiable {
    let id: UUID = UUID()
    var amount: Int
    var icon: String
    var lvl: Int
}

struct SeasonPassView: View {
    @ObservedObject var vm: ContentViewModel
    
    @State var defaultGenerator = SeededGenerator(seed: UInt64(Calendar.current.component(.year, from: Date())))
    @State var defaultRewards: [Reward] = []
    @State var premiumGenerator = SeededGenerator(seed: UInt64(Calendar.current.component(.year, from: Date()).advanced(by: 1000)))
    @State var premiumRewards: [Reward] = []
    @State var showPremiumPurchase: Bool = false
    var longCountdownFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.month, .day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter
    }
    var digitalCountdownFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.month, .day, .hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }
    var endOfYearDate: Date {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        let components = DateComponents(
            year: currentYear,
            month: 12,
            day: 31,
            hour: 23,
            minute: 59,
            second: 59
        )
        
        return calendar.date(from: components) ?? Date()
    }
    
    var body: some View {
        VStack {
            Text("Level \(vm.seasonPassLevel) (\(Int(vm.seasonXPPoints))/10 XP)")
                .bold()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 20) {
                        LazyHStack {
                            ForEach(defaultRewards) { reward in
                                VStack {
                                    Image(systemName: reward.icon)
                                    Text("x\(reward.amount)")
                                    if reward.lvl == vm.lastClaimedSeasonPassReward + 1 && reward.lvl <= vm.seasonPassLevel {
                                        Button("Sammeln", systemImage: "square.and.arrow.down") {
                                            claimReward(reward, isPremium: false)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding()
                                .frame(width: 100, height: 120)
                                .glassEffect(.regular.tint(vm.lastClaimedSeasonPassReward >= reward.lvl ? .blue : .clear))
                                .id(reward.lvl)
                                if reward.lvl < defaultRewards.count {
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 8)
                                        Capsule()
                                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: determineBridgeProgress(for: reward.lvl), height: 8)
                                            .animation(.easeInOut, value: vm.seasonPassLevel)
                                    }
                                    .frame(width: 60)
                                }
                            }
                        }
                        
                        Divider()
                        
                        LazyHStack {
                            ForEach(premiumRewards) { reward in
                                VStack {
                                    Image(systemName: reward.icon)
                                    Text("x\(reward.amount)")
                                    if reward.lvl == vm.lastClaimedSeasonPassPremiumReward + 1 && reward.lvl <= vm.seasonPassLevel {
                                        Button("Sammeln", systemImage: "square.and.arrow.down") {
                                            if Calendar.current.component(.year, from: Date()) == vm.lastPremiumSeasonPass {
                                                claimReward(reward, isPremium: true)
                                            } else {
                                                withAnimation {
                                                    showPremiumPurchase.toggle()
                                                }
                                            }
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.borderedProminent)
                                        .tint(.yellow)
                                    }
                                }
                                .padding()
                                .frame(width: 100, height: 120)
                                .glassEffect(.regular.tint(vm.lastClaimedSeasonPassPremiumReward >= reward.lvl ? .blue : .clear))
                                if reward.lvl < premiumRewards.count {
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 8)
                                        Capsule()
                                            .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: determineBridgeProgress(for: reward.lvl), height: 8)
                                            .animation(.easeInOut, value: vm.seasonPassLevel)
                                    }
                                    .frame(width: 60)
                                }
                            }
                        }
                    }
                    .padding()
                    .onAppear {
                        if defaultRewards.isEmpty { generateRewards() }
                        if vm.lastPremiumSeasonPass != Calendar.current.component(.year, from: Date()) {
                            proxy.scrollTo(vm.lastClaimedSeasonPassReward)
                        } else {
                            proxy.scrollTo(vm.lastClaimedSeasonPassPremiumReward)
                        }
                        if Calendar.current.component(.year, from: Date()) != vm.currentSeason {
                            vm.seasonPassLevel = 0
                            vm.seasonXPPoints = 0
                            vm.currentSeason = Calendar.current.component(.year, from: Date())
                        }
                    }
                }
            }
        }
        .overlay(content: {
            if showPremiumPurchase {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    VStack {
                        Text("Premium-Belohnungen freischalten?")
                            .font(.largeTitle)
                            .multilineTextAlignment(.center)
                        TimelineView(.periodic(from: .now, by: 1.0)) { context in
                            let remainingTime = endOfYearDate.timeIntervalSince(context.date)
                            Text("Du wirst bis zum Ende des Jahres die Möglichkeit haben, mehr Belohnungen pro Level zu sammeln. Übrige Zeit bis zum Neujahr: \(longCountdownFormatter.string(from: remainingTime) ?? "Ein Fehler ist aufgetreten")")
                                .multilineTextAlignment(.center)
                        }
                        SlideButton(action: {
                            do {
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                if vm.coins >= 300 {
                                    vm.coins -= 300
                                    vm.lastPremiumSeasonPass = Calendar.current.component(.year, from: Date())
                                    withAnimation {
                                        showPremiumPurchase.toggle()
                                    }
                                }
                            } catch {}
                        }, label: {
                            Label("300", systemImage: "brain.fill")
                                .bold()
                        })
                        .disabled(vm.coins < 300)
                        Button(action: {
                            withAnimation {
                                showPremiumPurchase.toggle()
                            }
                        }, label: {
                            Label("Abbrechen", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        })
                        .bold()
                        .padding()
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .padding()
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 40))
                    .padding()
                }
            }
        })
    }
    
    private func claimReward(_ reward: Reward, isPremium: Bool) {
        vm.coins += Double(reward.amount)
        if isPremium {
            vm.lastClaimedSeasonPassPremiumReward = reward.lvl
        } else {
            vm.lastClaimedSeasonPassReward = reward.lvl
        }
    }
    
    private func determineBridgeProgress(for bridgeLvl: Int) -> CGFloat {
        if vm.seasonPassLevel > bridgeLvl {
            return 60
        } else if vm.seasonPassLevel == bridgeLvl {
            return CGFloat(vm.seasonPassProgress * 60)
        } else {
            return 0
        }
    }
    
    private func generateRewards() {
        for i in 1...1000 {
            let icon = "brain.fill"
            defaultRewards.append(Reward(amount: Int.random(in: 5...20, using: &defaultGenerator), icon: icon, lvl: i))
        }
        for i in 1...1000 {
            let icon = "brain.fill"
            premiumRewards.append(Reward(amount: Int.random(in: 25...75, using: &premiumGenerator), icon: icon, lvl: i))
        }
    }
}

struct Settings: View {
    @ObservedObject var vm: ContentViewModel
    
    var body: some View {
        List {
            Section("Spiel", content: {
                Toggle("Langsamen Modus ausblenden", isOn: $vm.hideSlowMode)
                HStack {
                    Text("Am Ende des Trainings zu Health hinzufügen?")
                    Spacer()
                    Picker("Modus", selection: $vm.logHealthMode, content: {
                        Text("Aus").tag(0)
                        Text("Jedes Mal fragen").tag(1)
                        Text("Automatisch").tag(2)
                    })
                    .labelsHidden()
                }
            })
            Section("Anzeige", content: {
                NavigationLink("Übersicht", destination: {
                    DisplayOverviewSettings(vm: vm)
                })
            })
            Section("Sicherheit", content: {
                NavigationLink("Face ID", destination: {
                    FaceIDSettings(vm: vm)
                })
            })
            Section("Mehr", content: {
                NavigationLink("Open-Source Lizenzen", destination: {
                    OpenSources()
                })
            })
        }
        .navigationTitle("Einstellungen")
    }
}

struct DisplayOverviewSettings: View {
    @ObservedObject var vm: ContentViewModel
    
    var body: some View {
        NavigationStack {
            List {
                Toggle(isOn: .constant(true), label: {
                    Text("Leben und Ping anzeigen")
                    Text("Kann nicht ausgeblendet werden")
                })
                .disabled(true)
                Toggle(isOn: $vm.showDistance, label: {
                    Text("Entfernung zum Ziel anzeigen")
                })
                Toggle(isOn: $vm.showCpu, label: {
                    Text("CPU-Auslastung anzeigen")
                    Text("Aktuell: \((vm.currentCPU / 100).formatted(.percent.precision(.fractionLength(1))))")
                })
                Toggle(isOn: $vm.showRam, label: {
                    Text("Arbeitsspeicher-Auslastung anzeigen")
                    Text("Aktuell: \(vm.currentRAM.formatted(.number.precision(.fractionLength(2))))/\(vm.maxAvailableRAM.formatted(.number.precision(.fractionLength(2)))) MB (\(Int(vm.currentRAM / vm.maxAvailableRAM*100.0))%)")
                })
                Toggle(isOn: $vm.showThermal, label: {
                    Text("Gerätetemperatur anzeigen")
                    Text("Aktuell: \(vm.thermalStateDescription.text)")
                })
            }
            .navigationTitle("Übersicht anpassen")
        }
    }
}

struct FaceIDSettings: View {
    @ObservedObject var vm: ContentViewModel
    @State private var ready = false
    @State private var isAuthenticating = false
    @State private var localWayOfAuth: Int = 0
    @State private var localAppLocked: Bool = false
    @State private var localRunsLocked: Bool = false
    
    var body: some View {
        List {
            Picker(selection: $localWayOfAuth, content: {
                Text("Passcode oder Biometrisch").tag(0)
                Text("Biometrisch").tag(1)
            }, label: {
                Text("Weg der Authentifizierung")
            })
            .onChange(of: localWayOfAuth) { oldValue, newValue in
                guard newValue != vm.wayToAutheticate else { return }
                if ready {
                    Task {
                        isAuthenticating = true
                        do {
                            try await vm.authenticateUser()
                            vm.wayToAutheticate = localWayOfAuth
                        } catch {
                            withAnimation {
                                localWayOfAuth = vm.wayToAutheticate
                            }
                        }
                        isAuthenticating = false
                    }
                }
            }
            Toggle("App vollständig sperren", isOn: $localAppLocked)
                .onChange(of: localAppLocked) { oldValue, newValue in
                    guard newValue != vm.appLocked else { return }
                    if ready {
                        Task {
                            isAuthenticating = true
                            do {
                                try await vm.authenticateUser()
                                vm.appLocked = newValue
                            } catch {
                                withAnimation {
                                    localAppLocked = vm.appLocked
                                }
                            }
                            isAuthenticating = false
                        }
                    }
                }
            Toggle("Deine Läufe sperren", isOn: $localRunsLocked)
                .onChange(of: localRunsLocked) { oldValue, newValue in
                    guard newValue != vm.runsLocked else { return }
                    if ready {
                        Task {
                            isAuthenticating = true
                            do {
                                try await vm.authenticateUser()
                                vm.runsLocked = newValue
                            } catch {
                                withAnimation {
                                    localRunsLocked = vm.runsLocked
                                }
                            }
                            isAuthenticating = false
                        }
                    }
                }
        }
        .onAppear {
            localWayOfAuth = vm.wayToAutheticate
            localAppLocked = vm.appLocked
            localRunsLocked = vm.runsLocked
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                ready = true
            })
        }
    }
}
