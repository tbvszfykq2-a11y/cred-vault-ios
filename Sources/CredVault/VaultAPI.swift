import Foundation

/// Thin async client for the cred-vault HTTP API.
///
/// Auth model: POST /api/auth/login sets an HttpOnly `cv_session` cookie which
/// URLSession stores in the shared cookie storage. Every other POST additionally
/// requires the session CSRF token in the `X-CSRF-Token` header. The passcode is
/// never persisted by this client — it exists only as a request body.
final class VaultAPI {
    private let base: URL
    private let session: URLSession

    init(base: URL) {
        self.base = base
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - plumbing

    private func endpoint(_ path: String) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + "/" + path)
    }

    private func send(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        csrf: String? = nil
    ) async throws -> (status: Int, data: Data) {
        guard let target = endpoint(path) else {
            throw APIError(status: 0, message: "Server URL is not valid.", lockedFor: nil, attemptsLeft: nil)
        }
        var req = URLRequest(url: target)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let csrf, !csrf.isEmpty {
            req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, data)
    }

    private func failure(_ data: Data, _ status: Int) -> APIError {
        var message = "Server returned HTTP \(status)."
        var lockedFor: Int?
        var attempts: Int?
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = obj["error"] as? String { message = text }
            lockedFor = obj["locked_for"] as? Int
            attempts = obj["attempts_left"] as? Int
        }
        return APIError(status: status, message: message, lockedFor: lockedFor, attemptsLeft: attempts)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ status: Int) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError(status: status, message: "Unexpected server response.", lockedFor: nil, attemptsLeft: nil)
        }
    }

    // MARK: - auth

    func state() async throws -> VaultState {
        let (status, data) = try await send("api/state")
        guard status == 200 else { throw failure(data, status) }
        return try decode(VaultState.self, data, status)
    }

    func login(passcode: String) async throws {
        let (status, data) = try await send("api/auth/login", method: "POST", body: ["passcode": passcode])
        guard status == 200 else { throw failure(data, status) }
    }

    func logout() async {
        _ = try? await send("api/auth/logout", method: "POST", body: [:])
        clearCookies()
    }

    func clearCookies() {
        for cookie in HTTPCookieStorage.shared.cookies(for: base) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    func changePasscode(current: String, new: String, confirm: String, csrf: String) async throws {
        let (status, data) = try await send(
            "api/passcode", method: "POST",
            body: ["current": current, "new": new, "confirm": confirm], csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
    }

    // MARK: - entries

    private struct EntriesPayload: Codable { let entries: [VaultEntry] }
    private struct PasswordPayload: Codable { let password: String }
    private struct SavePayload: Codable { let ok: Bool; let entry: VaultEntry }

    func entries(csrf: String) async throws -> [VaultEntry] {
        let (status, data) = try await send("api/entries", csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
        return try decode(EntriesPayload.self, data, status).entries
    }

    func reveal(id: String, csrf: String) async throws -> String {
        let (status, data) = try await send(
            "api/entries/reveal", method: "POST", body: ["id": id], csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
        return try decode(PasswordPayload.self, data, status).password
    }

    func save(
        id: String,
        service: String,
        username: String,
        password: String,
        link: String,
        notes: String,
        category: String?,
        tags: [String],
        csrf: String
    ) async throws -> VaultEntry {
        var body: [String: Any] = [
            "id": id,
            "service": service,
            "username": username,
            "password": password,
            "url": link,
            "notes": notes,
            "tags": tags,
        ]
        if let category { body["category"] = category }
        let (status, data) = try await send(
            "api/entries/save", method: "POST", body: body, csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
        return try decode(SavePayload.self, data, status).entry
    }

    func delete(id: String, csrf: String) async throws {
        let (status, data) = try await send(
            "api/entries/delete", method: "POST", body: ["id": id], csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
    }

    func generatePassword(length: Int, csrf: String) async throws -> String {
        let (status, data) = try await send(
            "api/password/generate", method: "POST", body: ["length": length], csrf: csrf)
        guard status == 200 else { throw failure(data, status) }
        return try decode(PasswordPayload.self, data, status).password
    }
}
