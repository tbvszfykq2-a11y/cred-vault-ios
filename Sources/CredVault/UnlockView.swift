import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var app: AppState
    @State private var passcode = ""
    @State private var showSettings = false
    @State private var rememberWithBiometrics = false
    @State private var autoPrompted = false

    private var canUseBiometrics: Bool {
        app.biometricsAvailable && app.biometricsEnrolled
    }

    var body: some View {
        Form {
            if canUseBiometrics {
                Section {
                    Button {
                        Task { _ = await app.unlockWithBiometrics() }
                    } label: {
                        Label("Unlock with \(app.biometryLabel)", systemImage: "faceid")
                    }
                    .disabled(app.busy || app.isLockedOut)
                } footer: {
                    if app.isLockedOut {
                        Text("Biometric unlock is paused while the server is locked out.")
                    } else {
                        Text("Reads your saved passcode from the Keychain. \(app.biometryLabel) is required each time.")
                    }
                }
            }

            Section {
                SecureField("Passcode", text: $passcode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
            } header: {
                Text("Unlock vault")
            } footer: {
                Text("Your passcode is sent to your server to derive the decryption key. It is only kept on this device if you enable biometric unlock below.")
            }

            Section {
                Button {
                    let value = passcode
                    let remember = rememberWithBiometrics
                    Task {
                        let ok = await app.unlock(passcode: value)
                        if ok {
                            if remember {
                                app.rememberPasscode(value)
                            } else if app.biometricsEnrolled {
                                app.forgetPasscode()
                            }
                        }
                        passcode = ""
                    }
                } label: {
                    HStack {
                        if app.busy { ProgressView().padding(.trailing, 4) }
                        Text("Unlock")
                    }
                }
                .disabled(passcode.isEmpty || app.busy || app.isLockedOut)

                if app.biometricsAvailable {
                    Toggle("Remember with \(app.biometryLabel)", isOn: $rememberWithBiometrics)
                }
            } footer: {
                if app.biometricsAvailable {
                    Text("Stores the passcode in a Keychain item that only unlocks with \(app.biometryLabel). Changing your enrolled face or fingerprint invalidates it automatically.")
                }
            }

            Section {
                if let until = app.lockedUntil, until > Date() {
                    LockoutCountdown(until: until)
                } else {
                    LabeledContent("Attempts left", value: "\(app.attemptsLeft)")
                }
            } header: {
                Text("Status")
            } footer: {
                if app.isLockedOut {
                    Text("The server locks globally after repeated failures. Waiting is the only way through.")
                }
            }

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label("Server settings", systemImage: "gear")
                }
            }
        }
        .navigationTitle("Unlock")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Vault error", isPresented: errorBinding) {
            Button("OK") { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
        .task {
            // Offer biometric unlock once per launch, but never while locked out.
            guard !autoPrompted, canUseBiometrics, !app.isLockedOut else { return }
            autoPrompted = true
            _ = await app.unlockWithBiometrics()
        }
        .onAppear {
            rememberWithBiometrics = app.biometricsEnrolled
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )
    }
}

struct LockoutCountdown: View {
    let until: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(until.timeIntervalSince(context.date).rounded(.up)))
            Label(
                "Locked — try again in \(remaining / 60)m \(remaining % 60)s",
                systemImage: "lock.timer"
            )
            .foregroundStyle(.red)
        }
    }
}
