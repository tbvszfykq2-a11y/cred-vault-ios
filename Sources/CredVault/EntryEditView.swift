import SwiftUI

struct EntryEditView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// nil = new entry.
    let existing: VaultEntry?

    @State private var service = ""
    @State private var username = ""
    @State private var password = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var category = VaultPolicy.defaultCategory
    @State private var tagsText = ""

    @State private var revealed = false
    @State private var loadingSecret = false
    @State private var saving = false
    @State private var localError: String?

    private var isNew: Bool { existing == nil }

    private var tags: [String] {
        tagsText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Credential") {
                    TextField("Service (required)", text: $service)
                        .textInputAutocapitalization(.words)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("URL", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    if loadingSecret {
                        HStack {
                            ProgressView()
                            Text("Fetching stored password…").foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            if revealed {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            Button {
                                revealed.toggle()
                            } label: {
                                Image(systemName: revealed ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        Button {
                            Task {
                                if let generated = await app.generatePassword() {
                                    password = generated
                                    revealed = true
                                }
                            }
                        } label: {
                            Label("Generate strong password", systemImage: "wand.and.stars")
                        }
                    }
                } header: {
                    Text("Password")
                } footer: {
                    Text("Generated on the server and never logged. Copying puts it on the clipboard for 60 seconds.")
                }

                Section("Organisation") {
                    Picker("Category", selection: $category) {
                        ForEach(VaultPolicy.categories, id: \.self) { value in
                            Text(value == "vps" ? "VPS" : "External").tag(value)
                        }
                    }
                    TextField("Tags (comma separated, max \(VaultPolicy.maxTags))", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let localError {
                    Section {
                        Text(localError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "New credential" : "Edit credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || loadingSecret || service.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { await prefill() }
        }
    }

    private func prefill() async {
        guard let existing else { return }
        service = existing.service
        username = existing.username
        link = existing.url
        notes = existing.notes
        category = existing.category
        tagsText = existing.tags.joined(separator: ", ")

        // The server's upsert always writes the password field, so an edit must
        // carry the real secret or it would blank the stored one.
        loadingSecret = true
        defer { loadingSecret = false }
        if let current = await app.reveal(id: existing.id) {
            password = current
        } else {
            localError = "Could not fetch the stored password. Saving would erase it, so editing is blocked."
        }
    }

    private func save() async {
        localError = nil
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else {
            localError = "Service name is required."
            return
        }
        guard !password.isEmpty else {
            localError = "Password cannot be empty."
            return
        }
        if tags.count > VaultPolicy.maxTags {
            localError = "Too many tags (max \(VaultPolicy.maxTags))."
            return
        }

        saving = true
        defer { saving = false }
        let ok = await app.save(
            id: existing?.id ?? "",
            service: trimmedService,
            username: username,
            password: password,
            link: link,
            notes: notes,
            category: category,
            tags: tags
        )
        if ok { dismiss() }
    }
}
