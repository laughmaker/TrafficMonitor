import Foundation

public struct ProcessTraffic: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let receivedBytes: Int64
    public let sentBytes: Int64
    public let sampleDuration: TimeInterval
    public let isProxyTransport: Bool

    public var id: String { "\(pid):\(processName)" }

    public var receivedBytesPerSecond: Double {
        guard sampleDuration > 0 else { return 0 }
        return Double(receivedBytes) / sampleDuration
    }

    public var sentBytesPerSecond: Double {
        guard sampleDuration > 0 else { return 0 }
        return Double(sentBytes) / sampleDuration
    }

    public var totalBytesPerSecond: Double {
        receivedBytesPerSecond + sentBytesPerSecond
    }

    public init(
        pid: Int32,
        processName: String,
        receivedBytes: Int64,
        sentBytes: Int64,
        sampleDuration: TimeInterval,
        isProxyTransport: Bool = false
    ) {
        self.pid = pid
        self.processName = processName
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.sampleDuration = sampleDuration
        self.isProxyTransport = isProxyTransport
    }
}

public enum TrafficAccountingMode: String, CaseIterable, Codable, Sendable {
    case application
    case gateway
    case diagnostic

    public var title: String {
        switch self {
        case .application: "按实际 App"
        case .gateway: "按网络出口"
        case .diagnostic: "诊断模式"
        }
    }

    public var explanation: String {
        switch self {
        case .application: "排除 Clash/VPN 转发层，避免代理链路重复计算。"
        case .gateway: "存在代理流量时只统计 Clash/VPN 对外传输层。"
        case .diagnostic: "同时显示 App 与代理层，数值可能包含重复链路。"
        }
    }
}

public struct TrafficSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let processes: [ProcessTraffic]

    public var totalReceivedBytesPerSecond: Double {
        processes.reduce(0) { $0 + $1.receivedBytesPerSecond }
    }

    public var totalSentBytesPerSecond: Double {
        processes.reduce(0) { $0 + $1.sentBytesPerSecond }
    }

    public init(timestamp: Date = Date(), processes: [ProcessTraffic]) {
        self.timestamp = timestamp
        self.processes = processes
    }

    public func applying(_ mode: TrafficAccountingMode) -> TrafficSnapshot {
        let selected: [ProcessTraffic]
        switch mode {
        case .application:
            selected = processes.filter { !$0.isProxyTransport }
        case .gateway:
            let proxy = processes.filter(\.isProxyTransport)
            selected = proxy.isEmpty ? processes.filter { !$0.isProxyTransport } : proxy
        case .diagnostic:
            selected = processes
        }
        return TrafficSnapshot(timestamp: timestamp, processes: selected)
    }
}
