import Foundation
import TrafficCore

@main
struct TrafficProbe {
    static func main() async throws {
        let collector = NettopCollector()
        let stream = AsyncThrowingStream<TrafficSnapshot, Error> { continuation in
            do {
                try collector.start { snapshot in
                    continuation.yield(snapshot)
                }
            } catch {
                continuation.finish(throwing: error)
            }

            continuation.onTermination = { _ in
                collector.stop()
            }
        }

        for try await snapshot in stream {
            print("processes=\(snapshot.processes.count)")
            print("download=\(ByteRateFormatter.string(from: snapshot.totalReceivedBytesPerSecond))")
            print("upload=\(ByteRateFormatter.string(from: snapshot.totalSentBytesPerSecond))")

            for process in snapshot.processes
                .sorted(by: { $0.totalBytesPerSecond > $1.totalBytesPerSecond })
                .prefix(5)
            {
                print(
                    "\(process.processName) "
                        + "↓\(ByteRateFormatter.compactString(from: process.receivedBytesPerSecond)) "
                        + "↑\(ByteRateFormatter.compactString(from: process.sentBytesPerSecond))"
                )
            }

            collector.stop()
            try await Task.sleep(for: .milliseconds(250))
            return
        }
    }
}
