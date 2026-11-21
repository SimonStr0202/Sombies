import SwiftUI
import Auth
import SkimUI
import Supabase
import AuthenticationServices

struct LoginView: View {
    @Environment(\.presentToast) var presentToast
    @ObservedObject var vm: ContentViewModel
    @State var registerMode = false
    @State var emailAddress = ""
    @State var password = ""
    @State var loggingIn = false
    @State var errorStr: String?
    @State var feedback: SensoryFeedback = .levelChange
    @State var birthday: Date = Date()
    var body: some View {
        VStack {
            Text(registerMode ? "Bei Sombies registrieren" : "Bei Sombies anmelden")
                .font(.system(size: 30, design: .rounded))
                .padding(30)
                .contentTransition(.numericText())
            VStack {
                TextField("E-Mail Adresse", text: $emailAddress)
                    .padding(5)
                Divider()
                SecureField("Passwort", text: $password)
                    .padding(5)
                if registerMode {
                    Divider()
                    DatePicker("Geburtstag", selection: $birthday, displayedComponents: [.date])
                    /*
                    if birthday.timeIntervalSinceNow > -409968000 {
                        Text("Du musst mindestens 13 Jahre alt sein, um ein Konto zu erstellen")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                     */                }
            }
            .padding()
            .background(content: {
                RoundedRectangle(cornerRadius: 30)
                    .foregroundStyle(.quaternary)
            })
            .padding()
            Spacer()
            if errorStr != nil {
                Text(errorStr!)
                    .foregroundStyle(.red)
            }
            Button(registerMode ? "Hast du schon einen Account?" : "Noch kein Account?") {
                withAnimation {
                    registerMode.toggle()
                }
            }
            .foregroundStyle(.secondary)
            .font(.caption)
            .contentTransition(.numericText())
            Button(action: {
                feedback = .selection
                Task {
                    do {
                        loggingIn = true
                        try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...2_000_000_000))
                        if birthday.timeIntervalSinceNow > -409968000 && registerMode {
                            presentToast(ToastValue(title: "Anmeldung fehlgeschlagen", message: "Du musst mindestens 13 Jahre alt sein, um dich anzumelden.", type: .danger))
                            feedback = .error
                            loggingIn = false
                        } else {
                            if registerMode {
                                try await SupabaseClient(
                                    supabaseURL: URL(string: "https://hdqubxxsjkucpyxbcjgv.supabase.co")!,
                                    supabaseKey: "sb_publishable_zGWwVCMB5fhOl5pk7fZFNw_KkaXutkX").auth.signUp(email: emailAddress, password: password)
                            } else {
                                try await SupabaseClient(
                                    supabaseURL: URL(string: "https://hdqubxxsjkucpyxbcjgv.supabase.co")!,
                                    supabaseKey: "sb_publishable_zGWwVCMB5fhOl5pk7fZFNw_KkaXutkX").auth.signIn(email: emailAddress, password: password)
                            }
                            feedback = .success
                            loggingIn = false
                            vm.accountManagerShown = false
                        }
                    } catch {
                        presentToast(ToastValue(title: "Anmeldung fehlgeschlagen", message: error.localizedDescription, type: .danger))
                        feedback = .error
                        loggingIn = false
                    }
                }
            }, label: {
                Text(registerMode ? "Registrieren" : "Anmelden")
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .contentTransition(.numericText())
            })
            .buttonStyle(GlassProminentButtonStyle())
            .buttonSizing(.flexible)
            .padding()
            .disabled(loggingIn)
        }
        .sensoryFeedback(feedback, trigger: loggingIn)
    }
}

#Preview {
    LoginView(vm: ContentViewModel())
}
