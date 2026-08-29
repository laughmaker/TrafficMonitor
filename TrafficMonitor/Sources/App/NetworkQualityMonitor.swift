import CoreWLAN
import Foundation

struct NetworkQualityPoint: Identifiable, Sendable {
    let timestamp: Date
    let latencyMS: Double?
    let packetLossPercent: Double
    var id: Date { timestamp }
}

struct NetworkOutage: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
}

struct SpeedTestResult: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let downloadMbps: Double
}

private struct ConnectivityProbe: Sendable {
    let latencyMS: Double?
    let packetLossPercent: Double
    let dnsLatencyMS: Double?
}

@MainActor
final class NetworkQualityMonitor: ObservableObject {
    @Published private(set) var points: [NetworkQualityPoint] = []
    @Published private(set) var latencyMS: Double?
    @Published private(set) var packetLossPercent = 0.0
    @Published private(set) var dnsLatencyMS: Double?
    @Published private(set) var wifiRSSI: Int?
    @Published private(set) var wifiTransmitRate: Double?
    @Published private(set) var wifiChannel: Int?
    @Published private(set) var outages: [NetworkOutage] = []
    @Published private(set) var speedTestResults: [SpeedTestResult] = []
    @Published private(set) var isRunningSpeedTest = false

    private var probeTask: Task<Void, Never>?
    private var wasOnline: Bool?
    private let outageDefaultsKey = "networkQualityOutages"
    private let speedTestDefaultsKey = "networkQualitySpeedTests"

    var speedTestResult: SpeedTestResult? { speedTestResults.first }

    init() {
        if let data = UserDefaults.standard.data(forKey: outageDefaultsKey),
           let saved = try? JSONDecoder().decode([NetworkOutage].self, from: data)
        {
            outages = saved
        }
        if let data = UserDefaults.standard.data(forKey: speedTestDefaultsKey),
           let saved = try? JSONDecoder().decode([SpeedTestResult].self, from: data)
        {
            speedTestResults = saved
        }
    }

    func start() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = await Self.probeConnectivity()
                self?.apply(result)
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func stop() {
        probeTask?.cancel()
        probeTask = nil
    }

    func runSpeedTest() async {
        guard !isRunningSpeedTest else { return }
        isRunningSpeedTest = true
        defer { isRunningSpeedTest = false }
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000") else { return }
        do {
            let start = ContinuousClock.now
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let duration = start.duration(to: .now)
            let seconds = max(Double(duration.components.attoseconds) / 1e18
                              + Double(duration.components.seconds), 0.001)
            addSpeedTestResult(SpeedTestResult(
                id: UUID(),
                timestamp: Date(),
                downloadMbps: Double(data.count) * 8 / seconds / 1_000_000
            ))
        } catch {
            addSpeedTestResult(SpeedTestResult(id: UUID(), timestamp: Date(), downloadMbps: 0))
        }
    }

    private func addSpeedTestResult(_ result: SpeedTestResult) {
        speedTestResults.insert(result, at: 0)
        if speedTestResults.count > 50 { speedTestResults.removeLast(speedTestResults.count - 50) }
        if let data = try? JSONEncoder().encode(speedTestResults) {
            UserDefaults.standard.set(data, forKey: speedTestDefaultsKey)
        }
    }

    private func apply(_ result: ConnectivityProbe) {
        latencyMS = result.latencyMS
        packetLossPercent = result.packetLossPercent
        dnsLatencyMS = result.dnsLatencyMS
        let now = Date()
        points.append(NetworkQualityPoint(timestamp: now, latencyMS: result.latencyMS, packetLossPercent: result.packetLossPercent))
        if points.count > 180 { points.removeFirst(points.count - 180) }

        if let interface = CWWiFiClient.shared().interface(), interface.powerOn() {
            wifiRSSI = interface.rssiValue()
            wifiTransmitRate = interface.transmitRate()
            wifiChannel = interface.wlanChannel()?.channelNumber
        } else {
            wifiRSSI = nil
            wifiTransmitRate = nil
            wifiChannel = nil
        }

        let online = result.latencyMS != nil && result.packetLossPercent < 100
        if wasOnline == true && !online {
            outages.insert(NetworkOutage(id: UUID(), startedAt: now, endedAt: nil), at: 0)
        } else if wasOnline == false && online, !outages.isEmpty, outages[0].endedAt == nil {
            outages[0].endedAt = now
        }
        wasOnline = online
        if outages.count > 100 { outages.removeLast(outages.count - 100) }
        if let data = try? JSONEncoder().encode(outages) {
            UserDefaults.standard.set(data, forKey: outageDefaultsKey)
        }
    }

    nonisolated private static func probeConnectivity() async -> ConnectivityProbe {
        await Task.detached(priority: .utility) {
            let ping = run("/sbin/ping", arguments: ["-c", "3", "-W", "1000", "1.1.1.1"])
            let loss = firstNumber(in: ping, pattern: #"([0-9.]+)% packet loss"#) ?? 100
            let latency = firstNumber(in: ping, pattern: #"= [0-9.]+/([0-9.]+)/"#)
            let dnsStart = ContinuousClock.now
            let dnsOutput = run("/usr/bin/dscacheutil", arguments: ["-q", "host", "-a", "name", "apple.com"])
            let duration = dnsStart.duration(to: .now)
            let dnsSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return ConnectivityProbe(
                latencyMS: latency,
                packetLossPercent: loss,
                dnsLatencyMS: dnsOutput.isEmpty ? nil : dnsSeconds * 1_000
            )
        }.value
    }

    nonisolated private static func run(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Double(text[range])
    }
}
