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
    /// Automatically synchronizes across the user's Apple devices via iCloud Keychain when enabled.
    @discardableResult
    public static func set(_ value: String, forKey key: String, service: String? = nil, syncAcrossDevices: Bool = true) -> Bool {
        return shared.set(value, forKey: key, service: service, syncAcrossDevices: syncAcrossDevices)
    }
    
    /// Retrieves a decrypted secret string from the iOS Keychain (checks both device-only and iCloud Keychain)
    public static func get(forKey key: String, service: String? = nil) -> String? {
        return shared.get(forKey: key, service: service)
    }
    
    /// Deletes a secret from the iOS Keychain
    @discardableResult
    public static func delete(forKey key: String, service: String? = nil) -> Bool {
        return shared.delete(forKey: key, service: service)
    }
    
    // MARK: - Internal Implementation
    
    public func set(_ value: String, forKey key: String, service: String? = nil, syncAcrossDevices: Bool = true) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        guard let data = value.data(using: .utf8) else { return false }
        
        // 1. Delete any existing item (both synchronized and local) to prevent errSecDuplicateItem
        let deleteSyncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteSyncQuery as CFDictionary)
        
        let deleteLocalQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteLocalQuery as CFDictionary)
        
        // 2. Insert new item with hardware-level security (AES-256 in Secure Enclave)
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: syncAcrossDevices ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if syncAcrossDevices {
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        
        // Fallback to local-only storage if iCloud Keychain is not active on device or running in Simulator
        if status != errSecSuccess && syncAcrossDevices {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        if status != errSecSuccess {
            AppLogger.warning("Keychain set failed for key '\(key)' with SecStatus: \(status)")
        }
        return status == errSecSuccess
    }
    
    public func get(forKey key: String, service: String? = nil) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        
        // 1. First attempt: Query with synchronizable support (iCloud Keychain)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        
        var dataTypeRef: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        // 2. Second attempt: Fallback to local-only query
        if status != errSecSuccess {
            query.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        }
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
    
    public func delete(forKey key: String, service: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(syncQuery as CFDictionary)
        
        let localQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(localQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
