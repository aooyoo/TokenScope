import Foundation

public enum AppLanguage: String, CaseIterable, Hashable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let defaultsKey = "app.language"

    public static var current: AppLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey) else {
                return .simplifiedChinese
            }
            return AppLanguage(rawValue: rawValue) ?? .simplifiedChinese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    public var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans")
        }
    }
}
