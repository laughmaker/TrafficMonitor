import Charts
import SwiftUI
import TrafficCore

/// 代理分流：通过 Clash/mihomo 的 /connections 接口，按「目标域名」展示
/// 哪些流量走代理节点、哪些走直连（DIRECT）。
struct ProxyRoutingDashboard: View {
    @ObservedObject var store: TrafficMonitorStore
    @State private var filter: RoutingFilter = .all
    @State private var searchText = ""

    enum RoutingFilter: String, CaseIterable, Identifiable {
        case all, proxied, direct
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .proxied: "走代理"
            case .direct: "直连"
            }
        }
    }

    private var snapshot: ProxyRoutingSnapshot { store.proxyRouting }

    private var filteredEntries: [ProxyRoutingEntry] {
        snapshot.entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .proxied: matchesFilter = !entry.isDirect
            case .direct: matchesFilter = entry.isDirect
            }
            let matchesSearch = searchText.isEmpty
                || entry.target.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !snapshot.isAvailable {
                    unavailableCard
                } else {
                    summaryCards
                    accountingNote
                    splitChart
                    if !snapshot.entries.isEmpty {
                        routingTable
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DashboardBackground())
        .navigationTitle("代理")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("代理")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("基于 Clash 连接的真实出站走向：哪些目标走代理、哪些直连")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refreshProxyRouting() }
            } label: {
                if store.isRefreshingProxyRouting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(store.isRefreshingProxyRouting)
        }
    }

    private var unavailableCard: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("无法读取 Clash 分流数据", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(snapshot.errorMessage ?? "未知错误")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("需要 Clash Verge / mihomo 正在运行，且开启了外部控制（外部控制器 socket）。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !snapshot.socketPath.isEmpty {
                    Text("探测路径：\(snapshot.socketPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            ProxyMetric(
                title: "Clash 累计总量",
                value: TrafficByteFormatter.string(fromByteCount: snapshot.cumulativeBytes),
                tint: .blue,
                subtitle: "自 Clash 启动以来"
            )
            ProxyMetric(
                title: "当前活跃连接",
                value: TrafficByteFormatter.string(fromByteCount: snapshot.totalBytes),
                tint: .teal,
                subtitle: "\(snapshot.entries.count) 个目标 · 实时"
            )
            ProxyMetric(
                title: "活跃·走代理",
                value: TrafficByteFormatter.string(fromByteCount: snapshot.proxiedBytes),
                tint: .purple,
                subtitle: percentText(snapshot.proxiedBytes)
            )
            ProxyMetric(
                title: "活跃·直连",
                value: TrafficByteFormatter.string(fromByteCount: snapshot.directBytes),
                tint: .green,
                subtitle: percentText(snapshot.directBytes)
            )
        }
    }

    private var accountingNote: some View {
        Text("说明：「Clash 累计总量」是 Clash 自启动以来的总流量（与概览历史统计同量级）；「当前活跃连接」只统计此刻仍打开的连接，连接关闭后会释放，因此数值远小于累计总量。下方按目标域名列出的是活跃连接的实时走向。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func percentText(_ bytes: Int64) -> String {
        guard snapshot.totalBytes > 0 else { return "0%" }
        let p = Double(bytes) / Double(snapshot.totalBytes) * 100
        return String(format: "%.0f%%", p)
    }

    private var splitChart: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("代理 / 直连占比").font(.headline)
                Chart {
                    BarMark(
                        x: .value("类型", "直连"),
                        y: .value("流量", snapshot.directBytes)
                    )
                    .foregroundStyle(.green)
                    BarMark(
                        x: .value("类型", "走代理"),
                        y: .value("流量", snapshot.proxiedBytes)
                    )
                    .foregroundStyle(.purple)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let bytes = value.as(Int64.self) {
                                Text(TrafficByteFormatter.string(fromByteCount: bytes))
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private var routingTable: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("按目标域名").font(.headline).fixedSize()
                    Spacer(minLength: 8)
                    Picker("筛选", selection: $filter) {
                        ForEach(RoutingFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    .fixedSize()
                    TextField("搜索域名", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .fixedSize()
                }

                HStack {
                    Text("目标").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("走向").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text("上传").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    Text("下载").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    Text("合计").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                }
                .padding(.top, 4)

                Divider()

                ForEach(filteredEntries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirect ? "arrow.right.circle.fill" : "shield.lefthalf.filled")
                            .foregroundStyle(entry.isDirect ? .green : .purple)
                        Text(entry.target)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(entry.isDirect ? "直连" : entry.chain)
                            .font(.caption)
                            .foregroundStyle(entry.isDirect ? .green : .secondary)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
                        Text(TrafficByteFormatter.string(fromByteCount: entry.uploadBytes))
                            .font(.caption.monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                        Text(TrafficByteFormatter.string(fromByteCount: entry.downloadBytes))
                            .font(.caption.monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                        Text(TrafficByteFormatter.string(fromByteCount: entry.totalBytes))
                            .font(.caption.monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.4)
                }

                if filteredEntries.isEmpty {
                    Text("没有匹配的目标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct ProxyMetric: View {
    let title: String
    let value: String
    let tint: Color
    var subtitle: String? = nil

    var body: some View {
        ProxyCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProxyCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.045), radius: 10, y: 3)
    }
}
