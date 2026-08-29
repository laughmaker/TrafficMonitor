import Darwin
import Foundation

public struct ProcessAppIdentity: Equatable, Sendable {
    public let appName: String
    public let isProxyTransport: Bool

    public init(appName: String, isProxyTransport: Bool = false) {
        self.appName = appName
        self.isProxyTransport = isProxyTransport
    }
}

public struct ProcessTrafficAttributor: Sendable {
    public init() {}

    public func attribute(
        _ snapshot: TrafficSnapshot,
        identityFor: (ProcessTraffic) -> ProcessAppIdentity
    ) -> TrafficSnapshot {
        struct AccumulatedTraffic {
            var pid: Int32
            var name: String
            var receivedBytes: Int64
            var sentBytes: Int64
            var sampleDuration: TimeInterval
            var isProxyTransport: Bool
        }

        var grouped: [String: AccumulatedTraffic] = [:]

        for process in snapshot.processes {
            let identity = identityFor(process)

            let key = "\(Self.normalized(identity.appName)):\(identity.isProxyTransport ? 1 : 0)"
            guard !key.isEmpty else { continue }

            if var existing = grouped[key] {
                existing.receivedBytes += process.receivedBytes
                existing.sentBytes += process.sentBytes
                if process.processName == identity.appName {
                    existing.pid = process.pid
                }
                grouped[key] = existing
            } else {
                grouped[key] = AccumulatedTraffic(
                    pid: process.pid,
                    name: identity.appName,
                    receivedBytes: process.receivedBytes,
                    sentBytes: process.sentBytes,
                    sampleDuration: process.sampleDuration,
                    isProxyTransport: identity.isProxyTransport
                )
            }
        }

        let processes = grouped.values
            .map {
                ProcessTraffic(
                    pid: $0.pid,
                    processName: $0.name,
                    receivedBytes: $0.receivedBytes,
                    sentBytes: $0.sentBytes,
                    sampleDuration: $0.sampleDuration,
                    isProxyTransport: $0.isProxyTransport
                )
            }
            .sorted {
                ($0.receivedBytes + $0.sentBytes) > ($1.receivedBytes + $1.sentBytes)
            }

        return TrafficSnapshot(timestamp: snapshot.timestamp, processes: processes)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

final class ProcessApplicationResolver {
    private struct CachedIdentity {
        let executablePath: String?
        let identity: ProcessAppIdentity
    }

    private var cache: [Int32: CachedIdentity] = [:]

    func identity(for process: ProcessTraffic) -> ProcessAppIdentity {
        let executablePath = Self.executablePath(for: process.pid)
        if let cached = cache[process.pid], cached.executablePath == executablePath {
            return cached.identity
        }

        let identity: ProcessAppIdentity
        if Self.isProxyTransport(processName: process.processName, executablePath: executablePath) {
            let proxyName: String
            if let executablePath,
               let application = Self.containingApplication(forExecutablePath: executablePath)
            {
                proxyName = Self.displayName(for: application)
            } else {
                proxyName = Self.proxyDisplayName(for: process.processName)
            }
            identity = ProcessAppIdentity(appName: proxyName, isProxyTransport: true)
        } else if let executablePath,
                  let application = Self.containingApplication(forExecutablePath: executablePath)
        {
            identity = ProcessAppIdentity(appName: Self.displayName(for: application))
        } else if let application = Self.responsibleApplication(for: process.pid) {
            identity = ProcessAppIdentity(appName: Self.displayName(for: application))
        } else {
            identity = ProcessAppIdentity(appName: process.processName)
        }

        cache[process.pid] = CachedIdentity(executablePath: executablePath, identity: identity)
        return identity
    }

    private static func executablePath(for pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func containingApplication(forExecutablePath path: String) -> URL? {
        let components = URL(fileURLWithPath: path).pathComponents
        var currentPath = ""
        var applications: [URL] = []

        for component in components {
            if component == "/" {
                currentPath = "/"
            } else {
                currentPath = URL(fileURLWithPath: currentPath, isDirectory: true)
                    .appendingPathComponent(component)
                    .path
            }

            if component.lowercased().hasSuffix(".app") {
                applications.append(URL(fileURLWithPath: currentPath, isDirectory: true))
            }
        }

        guard !applications.isEmpty else { return nil }
        return applications.reversed().first { !looksLikeHelperBundle($0) }
            ?? applications.first
    }

    private static func responsibleApplication(for pid: Int32) -> URL? {
        var currentPID = pid
        var visited = Set<Int32>()
        for _ in 0..<8 {
            guard currentPID > 1, !visited.contains(currentPID) else { break }
            visited.insert(currentPID)
            if let path = executablePath(for: currentPID),
               let application = containingApplication(forExecutablePath: path)
            {
                return application
            }
            guard let parent = parentPID(for: currentPID), parent != currentPID else { break }
            currentPID = parent
        }
        return nil
    }

    private static func parentPID(for pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, pointer, Int32(size))
        }
        guard result == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    private static func looksLikeHelperBundle(_ url: URL) -> Bool {
        let name = normalized(url.deletingPathExtension().lastPathComponent)
        let helperMarkers = [
            "helper", "renderer", "plugin", "gpu", "accessory", "service",
            "crashpad", "appex", "webview", "framework"
        ]
        return helperMarkers.contains { name.contains($0) }
    }

    private static func displayName(for applicationURL: URL) -> String {
        let bundle = Bundle(url: applicationURL)
        let bundleIdentifier = bundle?.bundleIdentifier?.lowercased()
        let localizedNames = [
            "com.tencent.xinwechat": "微信",
            "com.bot.pc.doubao.browser": "豆包浏览器"
        ]
        if let bundleIdentifier, let localizedName = localizedNames[bundleIdentifier] {
            return localizedName
        }

        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty
        {
            return name
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty
        {
            return name
        }
        return applicationURL.deletingPathExtension().lastPathComponent
    }

    private static func isProxyTransport(processName: String, executablePath: String?) -> Bool {
        let process = normalized(processName)
        let executable = executablePath.map { normalized(URL(fileURLWithPath: $0).lastPathComponent) }
        let transportNames: Set<String> = [
            "vergemihomo", "mihomo", "clashmeta", "xray", "v2ray",
            "singbox", "wireguardgo", "openvpn", "openvpnconnect"
        ]
        return transportNames.contains(process) || executable.map(transportNames.contains) == true
    }

    private static func proxyDisplayName(for processName: String) -> String {
        let normalizedName = normalized(processName)
        if ["vergemihomo", "mihomo", "clashmeta"].contains(normalizedName) {
            return "Clash Verge"
        }
        if normalizedName.contains("openvpn") { return "OpenVPN" }
        if normalizedName.contains("wireguard") { return "WireGuard" }
        return processName
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
