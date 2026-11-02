import Foundation
import Security

/// 轻量 Keychain 封装：保存登录态和设备标识。
enum Keychain {

    private static let service = "com.miaoting.ios"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        _ = SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

/// 设备标识：优先 Keychain 里的 UUID（卸载重装不变），
/// 对应 Android 端 `machineId = Settings.Secure.ANDROID_ID`（取不到则 randomUUID）。
enum DeviceIdentity {

    private static let key = "machineId"

    /// 允许在设置里覆盖机器码（比如填 Android 的 android_id，
    /// 让服务端认为是同一台已绑定权益的设备）。
    static var override: String? {
        get { UserDefaults.standard.string(forKey: "machineIdOverride") }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: "machineIdOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "machineIdOverride")
            }
        }
    }

    static var machineId: String {
        if let custom = override, custom.count >= 6 { return custom }
        if let saved = Keychain.read(key), saved.count >= 8 { return saved }
        let fresh = UUID().uuidString
        Keychain.save(fresh, for: key)
        return fresh
    }
}
