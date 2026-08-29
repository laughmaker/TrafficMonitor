import Charts
import SwiftUI

struct NetworkQualityDashboard: View {
    @ObservedObject var monitor: NetworkQualityMonitor
    @State private var hoveredPoint: NetworkQualityPoint?

    private var latencyPoints: [NetworkQualityPoint] {
        monitor.points.filter { $0.latencyMS != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("网络质量")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("每 20 秒检查互联网、DNS 和当前 Wi‑Fi 状态")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await monitor.runSpeedTest() }
                    } label: {
                        if monitor.isRunningSpeedTest {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("下载测速", systemImage: "speedometer")
                        }
                    }
                    .disabled(monitor.isRunningSpeedTest)
                }

                HStack(spacing: 12) {
                    QualityMetric(title: "互联网延迟", value: monitor.latencyMS.map { "\(Int($0)) ms" } ?? "离线", tint: monitor.latencyMS == nil ? .red : .green)
                    QualityMetric(title: "丢包", value: String(format: "%.1f%%", monitor.packetLossPercent), tint: monitor.packetLossPercent > 5 ? .orange : .blue)
                    QualityMetric(title: "DNS", value: monitor.dnsLatencyMS.map { "\(Int($0)) ms" } ?? "—", tint: .indigo)
                    QualityMetric(title: "Wi-Fi 信号", value: monitor.wifiRSSI.map { "\($0) dBm" } ?? "有线/未知", tint: .cyan)
                }

                QualityPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("延迟趋势").font(.headline)
                            Spacer()
                            if let rate = monitor.wifiTransmitRate {
                                Text("协商速率 \(Int(rate)) Mbps")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let channel = monitor.wifiChannel {
                                Text("信道 \(channel)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if latencyPoints.isEmpty {
                            ContentUnavailableView("等待检测", systemImage: "network")
                                .frame(height: 220)
                        } else {
                            Chart(latencyPoints) { point in
                                LineMark(
                                    x: .value("时间", point.timestamp),
                                    y: .value("延迟", point.latencyMS ?? 0)
                                )
                                .foregroundStyle(.green)
                                .interpolationMethod(.monotone)
                                AreaMark(
                                    x: .value("时间", point.timestamp),
                                    y: .value("延迟", point.latencyMS ?? 0)
                                )
                                .foregroundStyle(.green.opacity(0.1))

                                if hoveredPoint?.id == point.id, let latency = point.latencyMS {
                                    RuleMark(x: .value("选中时间", point.timestamp))
                                        .foregroundStyle(.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .annotation(position: .top, spacing: 8) {
                                            NetworkChartTooltip(
                                                timestamp: point.timestamp,
                                                latencyMS: latency,
                                                packetLossPercent: point.packetLossPercent
                                            )
                                        }
                                }
                            }
                            .chartYAxisLabel("ms")
                            .frame(height: 240)
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onContinuousHover { phase in
                                            switch phase {
                                            case let .active(location):
                                                guard let plotFrame = proxy.plotFrame else { return }
                                                let frame = geometry[plotFrame]
                                                let x = location.x - frame.minX
                                                guard x >= 0, x <= frame.width,
                                                      let date: Date = proxy.value(atX: x)
                                                else { hoveredPoint = nil; return }
                                                hoveredPoint = latencyPoints.min {
                                                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                                                }
                                            case .ended:
                                                hoveredPoint = nil
                                            }
                                        }
                                }
                            }
                        }
                    }
                }

                if let result = monitor.speedTestResult {
                    QualityPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("下载测速历史", systemImage: "arrow.down.circle.fill")
                                    .font(.headline).foregroundStyle(.blue)
                                Spacer()
                                Text(result.downloadMbps > 0
                                     ? String(format: "最近 %.1f Mbps", result.downloadMbps)
                                     : "最近测速失败")
                                    .font(.headline)
                            }
                            ForEach(Array(monitor.speedTestResults.prefix(10))) { item in
                                let dateText = item.timestamp.formatted(date: .abbreviated, time: .standard)
                                let speedText = item.downloadMbps > 0
                                    ? String(format: "%.1f Mbps", item.downloadMbps)
                                    : "失败"
                                HStack {
                                    Text(dateText)
                                    Spacer()
                                    Text(speedText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(item.downloadMbps > 0 ? Color.primary : Color.red)
                                }
                            }
                        }
                    }
                }

                QualityPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("断网记录").font(.headline)
                        if monitor.outages.isEmpty {
                            Text("暂无断网记录").foregroundStyle(.secondary)
                        } else {
                            ForEach(monitor.outages.prefix(20)) { outage in
                                HStack {
                                    Image(systemName: outage.endedAt == nil ? "wifi.slash" : "checkmark.circle")
                                        .foregroundStyle(outage.endedAt == nil ? .red : .green)
                                    Text(outage.startedAt.formatted(date: .abbreviated, time: .standard))
                                    Spacer()
                                    if let end = outage.endedAt {
                                        Text(duration(from: outage.startedAt, to: end))
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    } else {
                                        Text("尚未恢复").foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(DashboardBackground())
        .navigationTitle("网络质量")
    }

    private func duration(from start: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

private struct QualityMetric: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        QualityPanel {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(tint)
            }
        }
    }
}

private struct QualityPanel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.045), radius: 10, y: 3)
    }
}
