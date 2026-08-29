import AppKit
import SwiftUI
import TrafficCore

struct TrafficPopoverView: View {
    @ObservedObject var store: TrafficMonitorStore
    let openDashboard: () -> Void

    private var activeProcesses: [ProcessTraffic] {
        store.snapshot.processes
            .filter { $0.totalBytesPerSecond > 0 }
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "无法读取流量",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxHeight: .infinity)
            } else if activeProcesses.isEmpty {
                ContentUnavailableView(
                    "正在等待网络活动",
                    systemImage: "network",
                    description: Text("产生网络流量后，应用和进程会显示在这里。")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activeProcesses.prefix(20)) { process in
                            ProcessTrafficRow(process: process)
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }

            Divider()
            Button {
                openDashboard()
            } label: {
                Label("打开流量监控", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(12)
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TrafficByteFormatter.string(fromByteCount: store.monthTotals.totalBytes))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("本月")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label(
                        ByteRateFormatter.compactString(
                            from: store.snapshot.totalSentBytesPerSecond
                        ),
                        systemImage: "arrow.up"
                    )
                    .foregroundStyle(.orange)
                    Label(
                        ByteRateFormatter.compactString(
                            from: store.snapshot.totalReceivedBytesPerSecond
                        ),
                        systemImage: "arrow.down"
                    )
                    .foregroundStyle(.blue)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            }

            Spacer()

            Button {
                openDashboard()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

private struct ProcessTrafficRow: View {
    let process: ProcessTraffic

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(name: process.processName, pid: process.pid, size: 28)

            Text(process.processName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Text("↑ \(ByteRateFormatter.compactString(from: process.sentBytesPerSecond))")
                    .foregroundStyle(.orange)
                Text("↓ \(ByteRateFormatter.compactString(from: process.receivedBytesPerSecond))")
                    .foregroundStyle(.blue)
            }
            .font(.system(size: 10, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
