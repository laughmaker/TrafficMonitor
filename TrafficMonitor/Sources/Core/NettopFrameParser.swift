import Foundation

public struct NettopFrameParser: Sendable {
    public let sampleDuration: TimeInterval

    public init(sampleDuration: TimeInterval) {
        self.sampleDuration = sampleDuration
    }

    public func parseFrame(_ lines: [String], timestamp: Date = Date()) -> TrafficSnapshot {
        let samples = lines.compactMap(parseLine)
        return TrafficSnapshot(timestamp: timestamp, processes: samples)
    }

    public func parseLine(_ line: String) -> ProcessTraffic? {
        let fields = Self.parseCSV(line)
        guard fields.count >= 3 else { return nil }

        let identity = fields[0]
        guard
            let separator = identity.lastIndex(of: "."),
            separator < identity.index(before: identity.endIndex),
            let pid = Int32(identity[identity.index(after: separator)...]),
            let receivedBytes = Int64(fields[1]),
            let sentBytes = Int64(fields[2])
        else {
            return nil
        }

        let processName = String(identity[..<separator])
        guard !processName.isEmpty else { return nil }

        return ProcessTraffic(
            pid: pid,
            processName: processName,
            receivedBytes: max(0, receivedBytes),
            sentBytes: max(0, sentBytes),
            sampleDuration: sampleDuration
        )
    }

    static func parseCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var insideQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "\"" {
                let next = line.index(after: index)
                if insideQuotes, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = line.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                fields.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(character)
            }

            index = line.index(after: index)
        }

        fields.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }
}
