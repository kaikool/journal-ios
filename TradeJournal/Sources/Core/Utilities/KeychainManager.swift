import Foundation
import Security

/// Thread-safe Hardware-backed Key Storage using iOS Keychain Services (Security.framework)
/// Provides AES-256 hardware encryption in the Secure Enclave instead of plain-text UserDefaults.
public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()
    
    private let defaultService = "com.tradejournal.credentials"
    private let lock = NSLock()
    
    private init() {}
    
    /// Stores or updates an encrypted secret string in the iOS Keychain
    @discardableResult
    public static func set(_ value: String, forKey key: String, service: String? = nil) -> Bool {
        return shared.set(value, forKey: key, service: service)
    }
    
    /// Retrieves a decrypted secret string from the iOS Keychain
    public static func get(forKey key: String, service: String? = nil) -> String? {
        return shared.get(forKey: key, service: service)
    }
    
    /// Deletes a secret from the iOS Keychain
    @discardableResult
    public static func delete(forKey key: String, service: String? = nil) -> Bool {
        return shared.delete(forKey: key, service: service)
    }
    
    // MARK: - Internal Implementation
    
    public func set(_ value: String, forKey key: String, service: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        guard let data = value.data(using: .utf8) else { return false }
        
        // 1. Delete any existing item to prevent duplicate key conflicts (errSecDuplicateItem)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 2. Insert new item with hardware-level security (accessible after first device unlock)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.warning("Keychain set failed for key '\(key)' with SecStatus: \(status)")
        }
        return status == errSecSuccess
    }
    
    public func get(forKey key: String, service: String? = nil) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
    
    public func delete(forKey key: String, service: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
