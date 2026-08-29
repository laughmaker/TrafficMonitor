import SwiftUI
import TrafficCore

struct TrafficChartTooltip: View {
    let title: String
    let received: Int64
    let sent: Int64
    var showsRate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                Label(value(received), systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(value(sent), systemImage: "arrow.up")
                    .foregroundStyle(.orange)
            }
            .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private func value(_ bytes: Int64) -> String {
        if showsRate { return ByteRateFormatter.compactString(from: Double(bytes)) }
        return TrafficByteFormatter.string(fromByteCount: bytes)
    }
}

struct HeatmapTooltip: View {
    let weekday: String
    let hour: Int
    let received: Int64
    let sent: Int64

    var body: some View {
        TrafficChartTooltip(
            title: "周\(weekday) · \(String(format: "%02d:00", hour))–\(String(format: "%02d:00", (hour + 1) % 24))",
            received: received,
            sent: sent
        )
    }
}

struct NetworkChartTooltip: View {
    let timestamp: Date
    let latencyMS: Double
    let packetLossPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption.weight(.semibold))
            HStack(spacing: 10) {
                Label(String(format: "%.0f ms", latencyMS), systemImage: "timer")
                    .foregroundStyle(.green)
                Label(String(format: "%.1f%%", packetLossPercent), systemImage: "waveform.path.ecg")
                    .foregroundStyle(packetLossPercent > 5 ? .orange : .blue)
            }
            .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.6) }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}
