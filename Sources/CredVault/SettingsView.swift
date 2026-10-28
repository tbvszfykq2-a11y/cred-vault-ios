import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draftURL = ""
    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var localError: String?
    @State private var savedNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://10.200.200.1:8791", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    Button("Save and reconnect") {
                        app.serverURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await app.refreshState()
                            savedNote = app.authed ? "Connected." : "Saved. Unlock to continue."
                        }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("The vault binds the WireGuard address only. Join the tunnel first, or point this at a reverse proxy.")
                }

                Section {
                    LabeledContent("Status", value: app.authed ? "Unlocked" : "Locked")
                    LabeledContent("Entries", value: "\(app.entries.count)")
                    LabeledContent("Attempts left", value: "\(app.attemptsLeft)")
                } header: {
                    Text("Session")
                } footer: {
                    Text("The server drops sessions after 15 minutes of inactivity. The app then asks for the passcode again.")
                }

                if app.authed {
                    Section {
                        SecureField("Current passcode", text: $currentPasscode)
                        SecureField("New passcode", text: $newPasscode)
                        SecureField("Confirm new passcode", text: $confirmPasscode)
                        Button("Change passcode") { Task { await changePasscode() } }
                            .disabled(currentPasscode.isEmpty || newPasscode.isEmpty)
                    } header: {
                        Text("Change passcode")
                    } footer: {
                        Text("Minimum \(VaultPolicy.passcodeMinLength) characters with \(VaultPolicy.passcodeMinDistinct)+ distinct characters. Re-encrypts the vault in place with a fresh salt.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await app.lock()
                            dismiss()
                        }
                    } label: {
                        Label("Lock now", systemImage: "lock.fill")
                    }
                }

                if let localError {
                    Section { Text(localError).foregroundStyle(.red) }
                }
                if let savedNote {
                    Section { Text(savedNote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { draftURL = app.serverURL }
        }
    }

    private func changePasscode() async {
        localError = nil
        savedNote = nil
        guard newPasscode == confirmPasscode else {
            localError = "New passcodes do not match."
            return
        }
        if let problem = VaultPolicy.validatePasscode(newPasscode) {
            localError = problem
            return
        }
        let ok = await app.changePasscode(
            current: currentPasscode,
            new: newPasscode,
            confirm: confirmPasscode
        )
        if ok {
            currentPasscode = ""
            newPasscode = ""
            confirmPasscode = ""
            savedNote = "Passcode changed."
        }
    }
}
