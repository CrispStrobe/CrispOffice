import FlutterMacOS
import Foundation
import LocalAuthentication
import Security

/// Holds the credential-vault unlock key in the data protection keychain as a
/// generic password whose access control requires the *current* biometric
/// enrolment (`.biometryCurrentSet`, `WhenUnlockedThisDeviceOnly`). macOS
/// enforces Touch ID on the item itself: reading it shows the system sheet,
/// and adding or removing a fingerprint makes the item permanently
/// unreadable. There is no app-side "authenticated" flag.
///
/// Channel `com.crispoffice/biometric_vault`:
///   isAvailable -> "available" | "noHardware" | "notEnrolled" | "lockedOut"
///                  | "keychainUnavailable" | "error"
///   store {secret}                          -> nil, or FlutterError
///   read {reason, cancelTitle?, fallbackTitle?}
///        -> {status: "success" | "cancelled" | "notFound" | "failed"
///                    | "unavailable", secret?}
///   delete                                  -> nil, or FlutterError
/// The secret is never logged or put into an error.
final class BiometricVaultKeychain {
  static let channelName = "com.crispoffice/biometric_vault"
  private static let service = "com.crispoffice.credential-vault.biometric"
  private static let account = "vault-unlock-key"

  private var channel: FlutterMethodChannel?
  // SecItemCopyMatching blocks while the Touch ID sheet is shown.
  private let queue = DispatchQueue(label: "com.crispoffice.biometric-vault")

  func register(binaryMessenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(
      name: Self.channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "biometric_vault_unavailable",
                            message: "Biometric unlock is unavailable.", details: nil))
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "isAvailable":
        self.queue.async {
          let status = self.availability()
          DispatchQueue.main.async { result(status) }
        }
      case "store":
        guard let secret = arguments["secret"] as? String, !secret.isEmpty else {
          result(FlutterError(code: "biometric_vault_invalid_secret",
                              message: "A secret is required.", details: nil))
          return
        }
        self.queue.async {
          let status = self.store(Data(secret.utf8))
          DispatchQueue.main.async {
            result(status == errSecSuccess ? nil : Self.failure("store", status))
          }
        }
      case "read":
        guard let reason = arguments["reason"] as? String, !reason.isEmpty else {
          result(FlutterError(code: "biometric_vault_invalid_reason",
                              message: "A reason is required.", details: nil))
          return
        }
        let cancelTitle = arguments["cancelTitle"] as? String
        let fallbackTitle = arguments["fallbackTitle"] as? String
        self.queue.async {
          let response = self.read(
            reason: reason, cancelTitle: cancelTitle, fallbackTitle: fallbackTitle)
          DispatchQueue.main.async { result(response) }
        }
      case "delete":
        self.queue.async {
          let status = self.delete()
          DispatchQueue.main.async {
            result(status == errSecSuccess || status == errSecItemNotFound
                   ? nil : Self.failure("delete", status))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private static func failure(_ operation: String, _ status: OSStatus) -> FlutterError {
    FlutterError(code: "biometric_vault_\(operation)_failed",
                 message: "Keychain \(operation) failed (\(status)).",
                 details: Int(status))
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: Self.account,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  /// Touch ID must be enrolled *and* this build must be entitled to the data
  /// protection keychain. The keychain probe never shows UI.
  private func availability() -> String {
    let context = LAContext()
    var error: NSError?
    if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      switch LAError.Code(rawValue: error?.code ?? 0) {
      case .biometryNotEnrolled, .passcodeNotSet: return "notEnrolled"
      case .biometryLockout: return "lockedOut"
      case .biometryNotAvailable: return "noHardware"
      default: return "error"
      }
    }
    guard context.biometryType == .touchID else { return "noHardware" }

    // A read cannot tell: an unentitled build gets errSecItemNotFound for a
    // query but errSecMissingEntitlement (-34018) for a write (measured on
    // macOS 26). So probe with a short-lived item without access control.
    var probe: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service + ".probe",
      kSecAttrAccount as String: UUID().uuidString,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let deleteQuery = probe
    probe[kSecValueData as String] = Data("probe".utf8)
    let status = SecItemAdd(probe as CFDictionary, nil)
    if status == errSecSuccess { SecItemDelete(deleteQuery as CFDictionary) }
    switch status {
    case errSecSuccess, errSecDuplicateItem:
      return "available"
    case errSecMissingEntitlement:
      return "keychainUnavailable"
    default:
      return "error"
    }
  }

  private func store(_ secret: Data) -> OSStatus {
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error)
    else {
      return errSecParam
    }
    _ = delete()
    var item = baseQuery()
    item[kSecAttrAccessControl as String] = access
    item[kSecAttrLabel as String] = "CrispOffice credential vault (Touch ID)"
    item[kSecValueData as String] = secret
    return SecItemAdd(item as CFDictionary, nil)
  }

  private func read(reason: String, cancelTitle: String?, fallbackTitle: String?)
    -> [String: Any]
  {
    let context = LAContext()
    context.localizedReason = reason
    if let cancelTitle { context.localizedCancelTitle = cancelTitle }
    // An empty title hides the fallback button; a title makes it return
    // errSecUserCanceled, which the app treats as "use the master password".
    context.localizedFallbackTitle = fallbackTitle ?? ""
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, let secret = String(data: data, encoding: .utf8)
      else {
        return ["status": "failed"]
      }
      return ["status": "success", "secret": secret]
    case errSecUserCanceled:
      return ["status": "cancelled"]
    case errSecItemNotFound:
      // Never stored, deleted, or invalidated by a fingerprint change.
      return ["status": "notFound"]
    case errSecMissingEntitlement, errSecNotAvailable:
      return ["status": "unavailable"]
    default:
      // errSecAuthFailed, errSecInteractionNotAllowed and the rest.
      return ["status": "failed"]
    }
  }

  private func delete() -> OSStatus {
    var query = baseQuery()
    // Deleting needs no authentication; never show UI for it.
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
    return SecItemDelete(query as CFDictionary)
  }
}
