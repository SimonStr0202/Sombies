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
            if emailAddress.isEmpty && password.isEmpty {
                SignInWithAppleButton(registerMode ? .signUp : .signIn, onRequest: { request in
                    request.requestedScopes = [.email]
                    loggingIn = true
                }, onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                           let identityToken = appleIDCredential.identityToken,
                           let tokenString = String(data: identityToken, encoding: .utf8) {
                            Task {
                                do {
                                    try await vm.session.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: tokenString))
                                } catch {
                                    presentToast(ToastValue(title: "Anmeldung fehlgeschlagen", message: error.localizedDescription, type: .warning))
                                }
                            }
                        }
                    case .failure(let error):
                        presentToast(ToastValue(title: "Anmeldung fehlgeschlagen", message: error.localizedDescription, type: .warning))
                    }
                })
                .signInWithAppleButtonStyle(.black)
                .padding()
                .disabled(loggingIn)
            } else {
                Button(action: {
                    feedback = .selection
                    Task {
                        do {
                            loggingIn = true
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
                        } catch {
                            errorStr = error.localizedDescription
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
        }
        .sensoryFeedback(feedback, trigger: loggingIn)
    }
}

#Preview {
    LoginView(vm: ContentViewModel())
}
