import Foundation

/// A credential entry as returned by GET /api/entries. Never contains the password.
struct VaultEntry: Identifiable, Codable, Hashable {
    let id: String
    let service: String
    let username: String
    let url: String
    let notes: String
    let source: String
    let category: String
    let tags: [String]
    let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id, service, username, url, notes, source, category, tags
        case updatedAt = "updated_at"
    }

    var displayTags: String {
        tags.joined(separator: ", ")
    }

    var host: String {
        guard let parsed = URL(string: url), let h = parsed.host else { return "" }
        return h
    }
}

/// GET /api/state payload.
struct VaultState: Codable {
    let version: String
    let initialized: Bool
    let authed: Bool
    let csrf: String
    let lockedUntil: Int
    let attemptsLeft: Int
    let count: Int

    enum CodingKeys: String, CodingKey {
        case version, initialized, authed, csrf, count
        case lockedUntil = "locked_until"
        case attemptsLeft = "attempts_left"
    }
}

/// Mirrors the server's policy so the UI can validate before spending a request.
enum VaultPolicy {
    static let passcodeMinLength = 10
    static let passcodeMaxLength = 256
    static let passcodeMinDistinct = 3
    static let categories = ["vps", "external"]
    static let defaultCategory = "vps"
    static let maxTags = 12
    static let maxTagLength = 24
    static let genMinLength = 8
    static let genMaxLength = 128
    static let genDefaultLength = 24

    static func validatePasscode(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count < passcodeMinLength {
            return "Passcode must be at least \(passcodeMinLength) characters."
        }
        if value.count > passcodeMaxLength {
            return "Passcode must be under \(passcodeMaxLength) characters."
        }
        if Set(value).count < passcodeMinDistinct {
            return "Too repetitive — use at least \(passcodeMinDistinct) distinct characters."
        }
        return nil
    }
}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    let lockedFor: Int?
    let attemptsLeft: Int?

    var errorDescription: String? { message }
}
