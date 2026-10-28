import Foundation
import SwiftUI

/// Session + data state for the vault app.
///
/// Deliberately holds no passcode: the server keeps it in memory for the life of
/// its session and the app only ever forwards it once, at unlock time. The
/// session cookie lives in URLSession's shared cookie storage.
@MainActor
final class AppState: ObservableObject {
    static let defaultServer = "http://10.200.200.1:8791"

    @Published var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? defaultServer {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    @Published var authed = false
    @Published var initialized = true
    @Published var csrf = ""
    @Published var entries: [VaultEntry] = []
    @Published var lockedUntil: Date?
    @Published var attemptsLeft = 5
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var didLoad = false
    /// HTTP status of the last failure, so callers can tell "wrong passcode" (401)
    /// from a transport error without string-matching the message.
    @Published var lastErrorStatus: Int?

    /// Cached rather than computed: the unlock screen re-renders once a second while a
    /// lockout countdown runs, and each of these touches LAContext or the Keychain.
    @Published var biometricsAvailable: Bool = BiometricStore.isAvailable
    @Published var biometricsEnrolled: Bool = BiometricStore.hasStoredPasscode
    let biometryLabel: String = BiometricStore.biometryLabel

    private var cached: (base: String, api: VaultAPI)?

    // MARK: - client

    func client() throws -> VaultAPI {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty else {
            throw APIError(status: 0,
                           message: "Set a valid server URL, for example http://10.200.200.1:8791",
                           lockedFor: nil, attemptsLeft: nil)
        }
        if let cached, cached.base == trimmed { return cached.api }
        let api = VaultAPI(base: parsed)
        cached = (trimmed, api)
        return api
    }

    var isLockedOut: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > Date()
    }

    // MARK: - session

    func refreshState() async {
        busy = true
        defer { busy = false }
        do {
            let st = try await client().state()
            apply(st)
            if st.authed {
                await loadEntries()
            } else {
                entries = []
            }
            errorMessage = nil
        } catch let e as APIError {
            handle(e)
        } catch {
            errorMessage = error.localizedDescription
            authed = false
        }
        didLoad = true
    }

    func unlock(passcode: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await client().login(passcode: passcode)
            let st = try await client().state()
            apply(st)
            await loadEntries()
            errorMessage = nil
            return true
        } catch let e as APIError {
            handle(e)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reads the passcode from the biometric Keychain item (this is what shows the
    /// Face ID prompt) and unlocks with it. If the server rejects the saved passcode,
    /// the stale item is deleted so it cannot burn attempts and trip the global lockout.
    func unlockWithBiometrics() async -> Bool {
        lastErrorStatus = nil
        do {
            let saved = try await BiometricStore.loadAsync()
            let ok = await unlock(passcode: saved)
            if !ok, lastErrorStatus == 401 {
                BiometricStore.delete()
                biometricsEnrolled = false
                errorMessage = "The saved Face ID passcode no longer works. It has been removed — type the passcode to unlock."
            }
            return ok
        } catch let e as BiometricStoreError {
            errorMessage = e.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Store the passcode for Face ID unlock. Called only where the user just typed it.
    func rememberPasscode(_ passcode: String) {
        do {
            try BiometricStore.save(passcode)
            biometricsEnrolled = true
        } catch {
            errorMessage = error.localizedDescription
            biometricsEnrolled = BiometricStore.hasStoredPasscode
        }
    }

    func forgetPasscode() {
        BiometricStore.delete()
        biometricsEnrolled = false
    }

    func lock() async {
        if let api = try? client() {
            await api.logout()
        }
        authed = false
        csrf = ""
        entries = []
    }

    func changePasscode(current: String, new: String, confirm: String) async -> Bool {
        do {
            try await client().changePasscode(current: current, new: new, confirm: confirm, csrf: csrf)
            return true
        } catch let e as APIError {
            handle(e)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - entries

    func loadEntries() async {
        do {
            entries = try await client().entries(csrf: csrf)
        } catch let e as APIError {
            handle(e)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reveal(id: String) async -> String? {
        do {
            return try await client().reveal(id: id, csrf: csrf)
        } catch let e as APIError {
            handle(e)
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func save(
        id: String,
        service: String,
        username: String,
        password: String,
        link: String,
        notes: String,
        category: String,
        tags: [String]
    ) async -> Bool {
        do {
            let saved = try await client().save(
                id: id, service: service, username: username, password: password,
                link: link, notes: notes, category: category, tags: tags, csrf: csrf)
            if let idx = entries.firstIndex(where: { $0.id == saved.id }) {
                entries[idx] = saved
            } else {
                entries.insert(saved, at: 0)
            }
            return true
        } catch let e as APIError {
            handle(e)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: String) async -> Bool {
        do {
            try await client().delete(id: id, csrf: csrf)
            entries.removeAll { $0.id == id }
            return true
        } catch let e as APIError {
            handle(e)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func generatePassword(length: Int = VaultPolicy.genDefaultLength) async -> String? {
        do {
            return try await client().generatePassword(length: length, csrf: csrf)
        } catch let e as APIError {
            handle(e)
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - helpers

    private func apply(_ st: VaultState) {
        initialized = st.initialized
        authed = st.authed
        csrf = st.csrf
        attemptsLeft = st.attemptsLeft
        lockedUntil = st.lockedUntil > 0
            ? Date().addingTimeInterval(TimeInterval(st.lockedUntil))
            : nil
    }

    private func handle(_ e: APIError) {
        errorMessage = e.message
        lastErrorStatus = e.status
        if let locked = e.lockedFor, locked > 0 {
            lockedUntil = Date().addingTimeInterval(TimeInterval(locked))
            authed = false
            csrf = ""
        }
        if let left = e.attemptsLeft { attemptsLeft = left }
        if e.status == 401 {
            authed = false
            csrf = ""
        }
    }
}
