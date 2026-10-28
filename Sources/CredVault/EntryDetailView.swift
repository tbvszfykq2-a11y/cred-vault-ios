import SwiftUI
import UIKit

struct EntryDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let entry: VaultEntry

    /// Prefer the live copy from app state so an edit is reflected immediately.
    private var current: VaultEntry {
        app.entries.first { $0.id == entry.id } ?? entry
    }

    @State private var password: String?
    @State private var revealed = false
    @State private var loading = false
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Service", value: current.service)
                if !current.username.isEmpty {
                    HStack {
                        LabeledContent("Username", value: current.username)
                        Button {
                            copy(current.username, label: "Username copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if !current.url.isEmpty {
                    HStack {
                        LabeledContent("URL", value: current.url)
                        Button {
                            copy(current.url, label: "URL copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                LabeledContent("Category", value: current.category)
                if !current.displayTags.isEmpty {
                    LabeledContent("Tags", value: current.displayTags)
                }
                if !current.source.isEmpty {
                    LabeledContent("Source", value: current.source)
                }
            }

            Section("Password") {
                if loading {
                    ProgressView()
                } else if let password, revealed {
                    HStack {
                        Text(password)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            copy(password, label: "Password copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    HStack {
                        Text("••••••••")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await loadPassword() }
                        } label: {
                            Label(password == nil ? "Reveal" : "Show", systemImage: "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    Task {
                        if let fetched = await fetchPassword() {
                            copy(fetched, label: "Password copied")
                        }
                    }
                } label: {
                    Label("Copy password", systemImage: "key.horizontal")
                }
                .disabled(loading)
            }

            if !current.notes.isEmpty {
                Section("Notes") {
                    Text(current.notes)
                }
            }

            Section {
                Button {
                    editing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .navigationTitle(current.service)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $editing) {
            EntryEditView(existing: current)
        }
        .confirmationDialog("Delete this credential?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(current.service)", role: .destructive) {
                Task {
                    if await app.delete(id: current.id) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from the vault on the server. It cannot be undone.")
        }
    }

    /// Fetches (once) and returns the plaintext secret, revealing it in the UI.
    @discardableResult
    private func fetchPassword() async -> String? {
        if let password { return password }
        loading = true
        defer { loading = false }
        guard let fetched = await app.reveal(id: current.id) else { return nil }
        password = fetched
        revealed = true
        return fetched
    }

    private func loadPassword() async {
        _ = await fetchPassword()
    }

    private func copy(_ value: String, label: String) {
        Clipboard.copy(value)
        withAnimation { toast = label }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { toast = nil }
        }
    }
}

enum Clipboard {
    /// Copy with a 60s expiry so the secret does not linger in paste history.
    static func copy(_ value: String) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: value]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )
    }
}
