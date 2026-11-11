import SwiftUI
import Auth
import Supabase
import Shimmer
import AuthenticationServices
import SkimUI
import SwiftyJSON

struct AccountManagerView: View {
    @ObservedObject var vm: ContentViewModel
    @State var currentMode = 0
    var body: some View {
        VStack {
            if currentMode == 0 {
                AccountManagerMainView(vm: vm, mode: $currentMode)
            } else if currentMode == 1 {
                
            } else if currentMode == 2 {
                LoginView(vm: vm)
            }
        }
    }
}

#Preview {
    AccountManagerView(vm: ContentViewModel())
}

struct backupData: Codable {
    let accountName: String
    let accountLevel: Int
    let accountXPPoints: Double
    let lastPremiumSeasonPass: Int
    let seasonXPPoints: Double
    let seasonPassLevel: Int
    let lastClaimedSeasonPassReward: Int
    let lastClaimedSeasonPassPremiumReward: Int
    let inventoryMedkits: Int
    let inventoryNavigatiors: Int
    let coins: Double
    let savedRuns: [Run]
}

struct AccountManagerMainView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentToast) var presentToast
    @ObservedObject var vm: ContentViewModel
    @Binding var mode: Int
    @State var loadingLogin = true
    @State var userMail: String?
    @State var creatingBackup = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.fill")
                        VStack {
                            Text("\(vm.userName)")
                                .fontWeight(.bold)
                            Text(userMail ?? "Keine E-Mail")
                                .font(.caption)
                                .shimmering(active: loadingLogin)
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Backup erstellen") {
                            creatingBackup = true
                            Task {
                                do {
                                    try await vm.session.functions.invoke("ensure-user-backup-folder")
                                    let encoder = JSONEncoder()
                                    let backup = backupData(accountName: vm.userName,
                                                            accountLevel: vm.accountLevel,
                                                            accountXPPoints: vm.xpPoints,
                                                            lastPremiumSeasonPass: vm.lastPremiumSeasonPass,
                                                            seasonXPPoints: vm.seasonXPPoints,
                                                            seasonPassLevel: vm.seasonPassLevel,
                                                            lastClaimedSeasonPassReward: vm.lastClaimedSeasonPassReward,
                                                            lastClaimedSeasonPassPremiumReward: vm.lastClaimedSeasonPassPremiumReward,
                                                            inventoryMedkits: vm.medkits,
                                                            inventoryNavigatiors: vm.navigators,
                                                            coins: vm.coins,
                                                            savedRuns: RunManager.shared.savedRuns)
                                    /* let backupDict: [String: Any] = ["accountName": vm.userName,
                                     "accountLevel": vm.accountLevel,
                                     "accountXpPoints": vm.xpPoints,
                                     "lastPremiumSeasonPass": vm.lastPremiumSeasonPass,
                                     "seasonXPPoints": vm.seasonXPPoints,
                                     "seasonPassLevel": vm.seasonPassLevel,
                                     "lastClaimedSeasonPassReward": vm.lastClaimedSeasonPassReward,
                                     "lastClaimedSeasonPassPremiumReward": vm.lastClaimedSeasonPassPremiumReward,
                                     "inventoryMedkits": vm.medkits,
                                     "inventoryNavigators": vm.navigators,
                                     "coins": vm.coins,
                                     "runs": RunManager.shared.savedRuns
                                     ] */
                                    let jsonData = try encoder.encode(backup)
                                    try await vm.session.storage.from("user-data-backups").upload("\(vm.session.auth.currentUser!.id.uuidString.lowercased())/backup.json", data: jsonData, options: FileOptions(contentType: "application/json", upsert: true))
                                    presentToast(ToastValue(title: "Backup erfolgreich", type: .success))
                                    creatingBackup = false
                                } catch {
                                    presentToast(ToastValue(title: "Fehler beim Backup", message: error.localizedDescription, type: .warning))
                                    print(error.localizedDescription)
                                    creatingBackup = false
                                }
                            }
                        }
                        .disabled(creatingBackup)
                        if creatingBackup {
                            ProgressView()
                        }
                    }
                    NavigationLink(destination: {
                        lastBackupView(vm: vm)
                    }, label: { Text("Letztes Backup") })
                }
                Section {
                    Button("Abmelden", role: .destructive) {
                        Task {
                            do {
                                try await vm.session.auth.signOut()
                                vm.accountManagerShown = false
                            } catch {
                                presentToast(ToastValue(title: "Abmeldung war nicht erfolgreich", message: error.localizedDescription))
                            }
                        }
                    }
                }
                .onAppear {
                    Task {
                        do {
                            userMail = try await vm.session.auth.user().email
                            loadingLogin = false
                        } catch {
                            if vm.session.auth.currentUser == nil {
                                withAnimation {
                                    mode = 2
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing, content: {
                    Button("Schließen", systemImage: "xmark") {
                        dismiss()
                    }
                        .labelStyle(.iconOnly)
                })
            }
        }
    }
}
/*
struct chooseLoginProvider: View {
    var body: some View {
        VStack {
            VStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.yellow)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                    .aspectRatio(1/1, contentMode: .fit)
                    .clipped()
                    .frame(width: 80)
                    .clipped()
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .overlay {
                        Image(systemName: "figure.walk.motion")
                            .imageScale(.large)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 31, weight: .regular, design: .default))
                            .foregroundStyle(.black)
                    }
                Text("Sombies")
                    .font(.system(.largeTitle, weight: .medium))
                Text("Renne mit Freunden vor virtuellen Zombies weg")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .padding()
            .frame(maxWidth: .infinity)
            .clipped()
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.quaternarySystemFill))
            }
            .padding()
            Text("Erstelle ein Konto, um mit deinen Freunden von überall zu spielen")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .padding()
                .frame(maxWidth: .infinity)
                .clipped()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.quaternarySystemFill))
                }
                .padding(.horizontal)
            Spacer()
            VStack {
                GlassEffectContainer {
                    VStack {
                        //SignInWithAppleButton(onRequest: { _ in }, onCompletion: { _ in }})
                        Button(action: { }, label: {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "apple.logo")
                                Text("Mit Apple registrieren")
                            }
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        })
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule(style: .continuous))
                            .controlSize(.regular)
                        .tint(.primary)
                        .foregroundStyle(Color(.systemBackground))
                         // Connect this action to your .sheet() modifier and @State variable
                        Button(action: { }, label: {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "envelope")
                                    .symbolRenderingMode(.monochrome)
                                Text("Mit E-Mail registrieren")
                            }
                            .padding(4)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        })
                            .buttonStyle(GlassButtonStyle(.regular))
                            .buttonBorderShape(.capsule(style: .continuous))
                            .controlSize(.regular)
                        .tint(.gray)
                        .foregroundStyle(.primary)
                    }
                }
            }
            .padding()
            .font(.system(.title3, weight: .medium))
            Spacer()
            Text("Hast du schon ein Konto?")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Button(action: { }, label: {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "person.badge.key.fill")
                        .symbolRenderingMode(.monochrome)
                    Text("Anmelden")
                }
                .padding(4)
                .frame(maxWidth: .infinity)
                .clipped()
            })
                .buttonStyle(GlassButtonStyle(.regular))
                .buttonBorderShape(.capsule(style: .continuous))
                .controlSize(.regular)
            .foregroundStyle(.primary)
            .padding(.horizontal)
            Spacer()
                .frame(height: 48)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.top, 96)
    }
}
*/

struct lastBackupView: View {
    @Environment(\.presentToast) var presentToast
    @ObservedObject var vm: ContentViewModel
    @State var lastBackup: String?
    @State var lastBackupLoading = false
    @State var backupDataLoaded: backupData?
    var body: some View {
        List {
            Section("Letztes Backup einsehen") {
                    if let backup = backupDataLoaded {
                        Text("Backup von \(backup.accountName)")
                        Text("Münzen: \(Int(backup.coins))")
                        Text("Erste Hilfe Kästen: \(Int(backup.inventoryMedkits))")
                        Text("Navigatoren: \(Int(backup.inventoryNavigatiors))")
                        Text("Level: \(Int(backup.accountLevel))")
                    } else if lastBackupLoading {
                        HStack {
                            ProgressView()
                            Text("Letztes Backup wird geladen...")
                        }
                    } else {
                        Button("Letztes Backup anzeigen") {
                            Task {
                                do {
                                    lastBackupLoading = true
                                    
                                    let fileData = try await vm.session.storage
                                        .from("user-data-backups")
                                        .download(path: "\(vm.session.auth.currentUser!.id.uuidString.lowercased())/backup.json")
                                    
                                    let decoded = try JSONDecoder().decode(backupData.self, from: fileData)
                                    
                                    backupDataLoaded = decoded
                                    lastBackupLoading = false
                                } catch {
                                    lastBackupLoading = false
                                    presentToast(ToastValue(title: "Backup nicht geladen", message: error.localizedDescription, type: .danger))
                                }
                            }
                        }
                    }
                }
        }
    }
}
