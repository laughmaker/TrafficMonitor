import Foundation
import Testing
@testable import TrafficCore

struct ProcessTrafficAttributorTests {
    @Test func groupsHelpersAndMarksProxyTransportForAccountingModes() {
        let snapshot = TrafficSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            processes: [
                sample(pid: 1, name: "QQ", received: 100, sent: 20),
                sample(pid: 2, name: "QQ Helper", received: 300, sent: 40),
                sample(pid: 3, name: "verge-mihomo", received: 400, sent: 500),
                sample(pid: 4, name: "WeChat", received: 50, sent: 10)
            ]
        )

        let result = ProcessTrafficAttributor().attribute(snapshot) { process in
            switch process.processName {
            case "QQ", "QQ Helper":
                return ProcessAppIdentity(appName: "QQ")
            case "verge-mihomo":
                return ProcessAppIdentity(appName: "Clash Verge", isProxyTransport: true)
            default:
                return ProcessAppIdentity(appName: "微信")
            }
        }

        #expect(result.processes.count == 3)
        let qq = result.processes.first { $0.processName == "QQ" }
        #expect(qq?.receivedBytes == 400)
        #expect(qq?.sentBytes == 60)
        let proxy = result.processes.first { $0.isProxyTransport }
        #expect(proxy?.processName == "Clash Verge")
        #expect(result.applying(.application).processes.count == 2)
        #expect(result.applying(.gateway).processes.map(\.processName) == ["Clash Verge"])
        #expect(result.applying(.diagnostic).processes.count == 3)
    }

    private func sample(
        pid: Int32,
        name: String,
        received: Int64,
        sent: Int64
    ) -> ProcessTraffic {
        ProcessTraffic(
            pid: pid,
            processName: name,
            receivedBytes: received,
            sentBytes: sent,
            sampleDuration: 2
        )
    }
}
