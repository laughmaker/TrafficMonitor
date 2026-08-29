import AppKit
import SwiftUI

struct AppIconView: View {
    let name: String
    var pid: Int32?
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = AppIdentityResolver.shared.icon(for: name, pid: pid) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.9), .indigo.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

@MainActor
private final class AppIdentityResolver {
    static let shared = AppIdentityResolver()

    private struct InstalledApplication {
        let url: URL
    }

    private let localizedAliasesByBundleIdentifier = [
        "com.tencent.xinwechat": "微信",
        "com.bot.pc.doubao.browser": "豆包浏览器"
    ]
    private var installedAppsByAlias: [String: InstalledApplication]?
    private var iconCache: [String: NSImage] = [:]
    private var missingAliases: Set<String> = []

    func icon(for processName: String, pid: Int32?) -> NSImage? {
        if let pid, pid > 0,
           let runningIcon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon
        {
            return runningIcon
        }

        let alias = Self.normalized(processName)
        guard !alias.isEmpty else { return nil }
        if let cached = iconCache[alias] { return cached }
        if missingAliases.contains(alias) { return nil }

        if let runningApp = matchingRunningApplication(for: alias),
           let icon = runningApp.icon
        {
            iconCache[alias] = icon
            return icon
        }

        if installedAppsByAlias == nil {
            installedAppsByAlias = buildInstalledApplicationIndex()
        }

        guard let application = installedAppsByAlias?[alias] else {
            missingAliases.insert(alias)
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: application.url.path)
        iconCache[alias] = icon
        return icon
    }

    private func matchingRunningApplication(for alias: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            let candidates = [
                application.localizedName,
                application.bundleIdentifier,
                application.bundleURL?.deletingPathExtension().lastPathComponent,
                application.executableURL?.lastPathComponent
            ]
            return candidates.compactMap { $0 }.contains { Self.normalized($0) == alias }
        }
    }

    private func buildInstalledApplicationIndex() -> [String: InstalledApplication] {
        var index: [String: InstalledApplication] = [:]
        for applicationURL in installedApplicationURLs() {
            let application = InstalledApplication(url: applicationURL)
            for alias in aliases(for: applicationURL) where index[alias] == nil {
                index[alias] = application
            }
        }
        return index
    }

    private func installedApplicationURLs() -> [URL] {
        let fileManager = FileManager.default
        let roots = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        var results: [URL] = []
        var seenPaths: Set<String> = []

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                if seenPaths.insert(url.path).inserted {
                    results.append(url)
                }
            }
        }
        return results
    }

    private func aliases(for applicationURL: URL) -> Set<String> {
        let bundle = Bundle(url: applicationURL)
        var names: [String] = [applicationURL.deletingPathExtension().lastPathComponent]

        if let bundle {
            names.append(contentsOf: [
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                bundle.bundleIdentifier,
                bundle.executableURL?.lastPathComponent
            ].compactMap { $0 })

            if let bundleIdentifier = bundle.bundleIdentifier?.lowercased(),
               let localizedAlias = localizedAliasesByBundleIdentifier[bundleIdentifier]
            {
                names.append(localizedAlias)
            }
        }

        let executableDirectory = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        if let executableURLs = try? FileManager.default.contentsOfDirectory(
            at: executableDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            names.append(contentsOf: executableURLs.map(\.lastPathComponent))
        }

        names.append(contentsOf: nestedHelperNames(in: applicationURL))
        return Set(names.map(Self.normalized).filter { !$0.isEmpty })
    }

    private func nestedHelperNames(in applicationURL: URL) -> [String] {
        let relativeDirectories = [
            "Contents/Frameworks", "Contents/Helpers", "Contents/XPCServices",
            "Contents/Library/LoginItems"
        ]
        var names: [String] = []

        for relativeDirectory in relativeDirectories {
            let directoryURL = applicationURL.appendingPathComponent(relativeDirectory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let extensionName = item.pathExtension.lowercased()
                guard extensionName == "app" || extensionName == "xpc" else { continue }

                names.append(item.deletingPathExtension().lastPathComponent)
                if let helperBundle = Bundle(url: item) {
                    names.append(contentsOf: [
                        helperBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                        helperBundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                        helperBundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
                        helperBundle.executableURL?.lastPathComponent
                    ].compactMap { $0 })
                }
                enumerator.skipDescendants()
            }
        }
        return names
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
