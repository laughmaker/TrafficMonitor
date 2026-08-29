import Foundation

public protocol TrafficCollector: AnyObject {
    func start(handler: @escaping @Sendable (TrafficSnapshot) -> Void) throws
    func stop()
}

public enum TrafficCollectorError: LocalizedError {
    case alreadyRunning
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "流量采集器已在运行。"
        case let .launchFailed(message):
            return "无法启动 nettop：\(message)"
        }
    }
}
