import Foundation
import LocalAuthentication
import Security

enum BiometricStoreError: LocalizedError {
    case unavailable(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .cancelled: return "Face ID was cancelled."
        case .failed(let why): return why
        }
    }
}

/// Optional convenience: keep the vault passcode in a Keychain item that requires
/// biometry to read. The item is created only at the moment the user types the
/// passcode, so the app never holds a copy at rest and the plaintext never leaves
/// the Keychain without a biometric check.
///
/// Access control is `.biometryCurrentSet`, so the item is invalidated automatically
/// if the enrolled face/finger set changes. Reading the item is what triggers the
/// Face ID prompt — there is no separate LAContext.evaluatePolicy call, and no
/// device-passcode fallback.
enum BiometricStore {
    private static let service = "com.hermes.credvault.biometric"
    private static let account = "vault-passcode"

    static var biometryLabel: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Existence check that must NOT prompt. With `kSecUseAuthenticationUIFail`, an
    /// existing item that requires interaction reports `errSecInteractionNotAllowed`.
    static var hasStoredPasscode: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            kSecReturnData as String: false,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func save(_ passcode: String) throws {
        guard isAvailable else {
            throw BiometricStoreError.unavailable("Biometrics are not enrolled on this device.")
        }
        delete()

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw BiometricStoreError.failed("Could not create a biometric access policy.")
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(passcode.utf8),
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricStoreError.failed("Keychain save failed (status \(status)).")
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Blocking read; the system shows the Face ID prompt here.
    static func load() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: "Unlock your credential vault",
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8) else {
                throw BiometricStoreError.failed("Stored passcode could not be read.")
            }
            return text
        case errSecUserCanceled, errSecAuthFailed:
            throw BiometricStoreError.cancelled
        case errSecItemNotFound:
            throw BiometricStoreError.unavailable("No saved passcode for biometric unlock.")
        default:
            throw BiometricStoreError.failed("Keychain read failed (status \(status)).")
        }
    }

    /// Async wrapper so the prompt does not block the main thread.
    static func loadAsync() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try load())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
