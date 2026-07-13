import Cocoa

struct AppInfo {
    let displayName: String
    let icon: NSImage

    static func resolve(from appPath: String) -> AppInfo {
        let fallbackName = (appPath as NSString)
            .lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let fallbackIcon = NSWorkspace.shared.icon(forFile: appPath)
        fallbackIcon.size = NSSize(width: 48, height: 48)

        guard FileManager.default.fileExists(atPath: appPath),
              let bundle = Bundle(path: appPath) else {
            return AppInfo(displayName: fallbackName, icon: fallbackIcon)
        }

        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? fallbackName

        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: 48, height: 48)
        return AppInfo(displayName: name, icon: icon)
    }

    static func resolveBundleID(from appPath: String) -> String? {
        guard FileManager.default.fileExists(atPath: appPath),
              let bundle = Bundle(path: appPath) else { return nil }
        return bundle.bundleIdentifier
    }
}
