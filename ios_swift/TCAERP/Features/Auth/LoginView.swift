import SwiftUI

/// Sign in / request-an-account screen (src/features/auth/LoginPage.jsx).
/// Always English — there's no account yet to have a language preference.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var settings: AppSettings

    private enum Mode { case login, signup }
    private enum FieldFocus { case name, email, password }

    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var remember = true
    @State private var showPassword = false
    @State private var loading = false
    @State private var invalid: Set<FieldFocus> = []
    @State private var shake = 0
    @State private var showServer = false
    @FocusState private var focus: FieldFocus?

    private func en(_ key: String) -> String { L10n.t(key, lang: "en") }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 110)
                    Text("Tunisia Consulting Agency")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text(mode == .signup ? en("auth.signUpSubtitle") : en("auth.signInSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(spacing: 18) {
                    if mode == .signup {
                        underlineField(en("auth.fullName"), field: .name) {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                                .submitLabel(.next)
                        }
                    }

                    underlineField(en("auth.email"), field: .email) {
                        TextField(text: $email, prompt: Text(verbatim: "agent@gmail.com")) { EmptyView() }
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                    }

                    underlineField(en("auth.password"), field: .password) {
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("••••••••", text: $password)
                                } else {
                                    SecureField("••••••••", text: $password)
                                }
                            }
                            .textContentType(mode == .signup ? .newPassword : .password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)

                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(Color.muted)
                            }
                            .accessibilityLabel("Show password")
                        }
                    }

                    if mode == .login {
                        Toggle(en("auth.rememberMe"), isOn: $remember)
                            .font(.subheadline)
                            .tint(.brand)
                    }
                }
                .modifier(Shake(animatableData: CGFloat(shake)))
                .onSubmit {
                    switch focus {
                    case .name: focus = .email
                    case .email: focus = .password
                    default: Task { await submit() }
                    }
                }

                VStack(spacing: 16) {
                    PrimaryButton(
                        title: mode == .signup ? en("auth.requestAccount") : en("auth.signIn"),
                        loading: loading
                    ) {
                        Task { await submit() }
                    }
                    .controlSize(.large)

                    HStack(spacing: 4) {
                        Text(mode == .signup ? en("auth.alreadyHaveAccount") : en("auth.dontHaveAccount"))
                            .foregroundStyle(Color.muted)
                        Button(mode == .signup ? en("auth.signIn") : en("auth.signUp")) {
                            withAnimation(.snappy) {
                                mode = mode == .login ? .signup : .login
                                invalid = []
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .font(.subheadline)

                    Button { showServer = true } label: {
                        Label(settings.serverURL, systemImage: "server.rack")
                            .font(.caption)
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.card.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { showServer = true } label: {
                Image(systemName: "server.rack")
                    .padding(12)
                    .foregroundStyle(Color.muted)
            }
            .accessibilityLabel("Server settings")
            .padding(.trailing, 8)
        }
        .sheet(isPresented: $showServer) {
            NavigationStack { ServerSettingsForm() }
                .environmentObject(settings)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func underlineField<Content: View>(_ label: String, field: FieldFocus, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(invalid.contains(field) ? Color.danger : Color.muted)
            content()
                .focused($focus, equals: field)
                .font(.body)
                .padding(.vertical, 6)
            Rectangle()
                .fill(invalid.contains(field) ? Color.danger : (focus == field ? Color.brand : Color.line))
                .frame(height: focus == field ? 2 : 1)
        }
    }

    private func submit() async {
        var bad: Set<FieldFocus> = []
        if !email.contains("@") { bad.insert(.email) }
        if password.isEmpty || (mode == .signup && password.count < 8) { bad.insert(.password) }
        if mode == .signup && name.trimmingCharacters(in: .whitespaces).isEmpty { bad.insert(.name) }
        invalid = bad
        guard bad.isEmpty else {
            withAnimation(.default) { shake += 1 }
            toast(mode == .signup && bad.contains(.password)
                  ? "Password must be at least 8 characters"
                  : "Please check the highlighted fields", error: true)
            return
        }

        focus = nil
        loading = true
        defer { loading = false }
        do {
            if mode == .signup {
                try await auth.signup(name: name, email: email, password: password)
                toast(en("auth.pendingApproval"))
                withAnimation { mode = .login }
                password = ""
            } else {
                try await auth.login(email: email, password: password, remember: remember)
                toast(en("auth.welcomeBack"))
            }
        } catch {
            withAnimation(.default) { shake += 1 }
            toast(error.localizedDescription, error: true)
        }
    }
}

/// Horizontal wiggle for invalid input (the web's "shake" reaction).
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
