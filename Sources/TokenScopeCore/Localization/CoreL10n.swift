import Foundation

enum CoreL10n {
    static func string(_ key: String) -> String {
        switch AppLanguage.current {
        case .english:
            return key
        case .simplifiedChinese:
            return NSLocalizedString(key, tableName: nil, bundle: zhHansBundle ?? resourceBundle, value: key, comment: "")
        }
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLanguage.current.locale, arguments: arguments)
    }

    private static let resourceBundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(
               url: resourceURL.appendingPathComponent("TokenScope_TokenScopeCore.bundle", isDirectory: true)
           ) {
            return bundle
        }
        return .module
    }()

    private static let zhHansBundle: Bundle? = {
        for resourceName in ["zh-Hans", "zh-hans"] {
            if let path = resourceBundle.path(forResource: resourceName, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }()
}
