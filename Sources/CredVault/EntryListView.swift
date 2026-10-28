import SwiftUI

struct EntryListView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var category = "all"
    @State private var showSettings = false
    @State private var adding = false

    private var filtered: [VaultEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return app.entries.filter { entry in
            let matchesCategory = category == "all" || entry.category == category
            guard matchesCategory else { return false }
            guard !needle.isEmpty else { return true }
            return entry.service.lowercased().contains(needle)
                || entry.username.lowercased().contains(needle)
                || entry.url.lowercased().contains(needle)
                || entry.notes.lowercased().contains(needle)
                || entry.tags.contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    Text("All").tag("all")
                    Text("VPS").tag("vps")
                    Text("External").tag("external")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section {
                if filtered.isEmpty {
                    Text(app.entries.isEmpty ? "No credentials yet." : "No matches.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                    }
                }
            } footer: {
                Text("\(app.entries.count) credential\(app.entries.count == 1 ? "" : "s")")
            }
        }
        .searchable(text: $query, prompt: "Search service, user, URL, tag")
        .refreshable { await app.refreshState() }
        .navigationTitle("Vault")
        .navigationDestination(for: VaultEntry.self) { entry in
            EntryDetailView(entry: entry)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await app.lock() }
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Label("Add credential", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $adding) {
            EntryEditView(existing: nil)
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

struct EntryRow: View {
    let entry: VaultEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.service)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 4)
                CategoryBadge(category: entry.category)
            }
            if !entry.username.isEmpty {
                Text(entry.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.displayTags.isEmpty {
                Text(entry.displayTags)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CategoryBadge: View {
    let category: String

    var body: some View {
        Text(category.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        category == "external" ? .orange : .blue
    }
}
