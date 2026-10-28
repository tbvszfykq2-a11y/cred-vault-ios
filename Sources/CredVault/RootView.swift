import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cred Vault")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if !app.didLoad { await app.refreshState() }
        }
        .onChange(of: phase) { _, newPhase in
            // Re-check the server session whenever the app comes back to the front.
            if newPhase == .active { Task { await app.refreshState() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.didLoad && app.busy {
            ProgressView("Contacting vault…")
        } else if !app.initialized {
            NoticeView(
                icon: "exclamationmark.triangle",
                title: "Vault not initialized",
                detail: "This server has no vault yet. Run the setup flow on the server first, then pull to refresh."
            )
        } else if app.authed {
            EntryListView()
        } else {
            UnlockView()
        }
    }
}

struct NoticeView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
