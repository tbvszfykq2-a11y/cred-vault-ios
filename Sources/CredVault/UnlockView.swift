import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var app: AppState
    @State private var passcode = ""
    @State private var showSettings = false

    var body: some View {
        Form {
            Section {
                SecureField("Passcode", text: $passcode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
            } header: {
                Text("Unlock vault")
            } footer: {
                Text("Your passcode is sent to your server to derive the decryption key. It is never stored on this device.")
            }

            Section {
                Button {
                    let value = passcode
                    Task {
                        _ = await app.unlock(passcode: value)
                        passcode = ""
                    }
                } label: {
                    HStack {
                        if app.busy { ProgressView().padding(.trailing, 4) }
                        Text("Unlock")
                    }
                }
                .disabled(passcode.isEmpty || app.busy || app.isLockedOut)
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
