import CoreWLAN
import CoreLocation
import Foundation
import SystemConfiguration

@MainActor
final class NetworkProfileDetector: NSObject {
    private var cachedName = "未知网络"
    private var lastRefresh = Date.distantPast
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
    }

    func requestSSIDAccess() {
        locationManager.requestWhenInUseAuthorization()
        lastRefresh = .distantPast
    }

    func currentName() -> String {
        if Date().timeIntervalSince(lastRefresh) < 30 { return cachedName }
        lastRefresh = Date()

        guard let store = SCDynamicStoreCreate(nil, "TrafficMonitor" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let interfaceName = value["PrimaryInterface"] as? String
        else {
            cachedName = "未知网络"
            return cachedName
        }

        if let interface = CWWiFiClient.shared().interface(withName: interfaceName) {
            cachedName = interface.ssid().flatMap { $0.isEmpty ? nil : $0 } ?? "Wi-Fi"
        } else {
            cachedName = interfaceName.hasPrefix("en") ? "有线网络（\(interfaceName)）" : interfaceName
        }
        return cachedName
    }
}
