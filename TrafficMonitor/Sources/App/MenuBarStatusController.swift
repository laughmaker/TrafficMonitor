import AppKit
import Combine
import SwiftUI
import TrafficCore

@MainActor
final class MenuBarStatusController: NSObject {
    var openDashboard: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let rateView = MenuBarRateView(frame: NSRect(x: 0, y: 0, width: 92, height: 22))
    private var snapshotObservation: AnyCancellable?
    private var totalsObservation: AnyCancellable?
    private var billingObservation: AnyCancellable?
    private var defaultsObservation: NSObjectProtocol?
    private weak var store: TrafficMonitorStore?

    func install(store: TrafficMonitorStore) {
        guard self.store == nil else { return }
        self.store = store

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityRole(.button)

            rateView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(rateView)
            NSLayoutConstraint.activate([
                rateView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                rateView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                rateView.topAnchor.constraint(equalTo: button.topAnchor),
                rateView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: TrafficPopoverView(store: store) { [weak self] in
                self?.popover.performClose(nil)
                self?.openDashboard?()
            }
        )

        snapshotObservation = store.$snapshot.sink { [weak self] snapshot in
            self?.update(with: snapshot)
        }
        totalsObservation = store.$todayTotals.combineLatest(store.$monthTotals).sink { [weak self] _, _ in
            guard let self, let store = self.store else { return }
            self.update(with: store.snapshot)
        }
        billingObservation = store.$billingCycleTotals.sink { [weak self] _ in
            guard let self, let store = self.store else { return }
            self.update(with: store.snapshot)
        }
        defaultsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let store = self.store else { return }
                self.update(with: store.snapshot)
            }
        }
        update(with: store.snapshot)
    }

    func remove() {
        snapshotObservation = nil
        totalsObservation = nil
        billingObservation = nil
        if let defaultsObservation {
            NotificationCenter.default.removeObserver(defaultsObservation)
        }
        defaultsObservation = nil
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
        store = nil
    }

    private func update(with snapshot: TrafficSnapshot) {
        let received = snapshot.totalReceivedBytesPerSecond
        let sent = snapshot.totalSentBytesPerSecond
        let rawMode = UserDefaults.standard.string(forKey: PreferenceKey.menuBarDisplayMode)
        let mode = MenuBarDisplayMode(rawValue: rawMode ?? "") ?? .liveRate
        let preferredWidth = rateView.update(
            mode: mode,
            receivedBytesPerSecond: received,
            sentBytesPerSecond: sent,
            todayBytes: store?.todayTotals.totalBytes ?? 0,
            monthBytes: mode == .quotaRemaining
                ? store?.billingCycleTotals.totalBytes ?? 0
                : store?.monthTotals.totalBytes ?? 0,
            quotaBytes: Int64(
                UserDefaults.standard.double(forKey: PreferenceKey.monthlyQuotaBytes)
                    * 1_073_741_824
            )
        )
        statusItem.length = min(max(preferredWidth, 54), 108)
        statusItem.button?.setAccessibilityLabel(
            "下载 \(ByteRateFormatter.string(from: received))，"
                + "上传 \(ByteRateFormatter.string(from: sent))"
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private final class MenuBarRateView: NSView {
    private var receivedText = "0KB/s"
    private var sentText = "0KB/s"

    override var isFlipped: Bool { true }

    private var firstLine = "↙ 0KB/s"
    private var secondLine = "↗ 0KB/s"

    @discardableResult
    func update(
        mode: MenuBarDisplayMode,
        receivedBytesPerSecond: Double,
        sentBytesPerSecond: Double,
        todayBytes: Int64,
        monthBytes: Int64,
        quotaBytes: Int64
    ) -> CGFloat {
        receivedText = Self.rateString(from: receivedBytesPerSecond)
        sentText = Self.rateString(from: sentBytesPerSecond)
        switch mode {
        case .liveRate:
            firstLine = "↙ \(receivedText)"
            secondLine = "↗ \(sentText)"
        case .todayTotal:
            firstLine = "今日用量"
            secondLine = TrafficByteFormatter.string(fromByteCount: todayBytes).replacingOccurrences(of: " ", with: "")
        case .monthTotal:
            firstLine = "本月用量"
            secondLine = TrafficByteFormatter.string(fromByteCount: monthBytes).replacingOccurrences(of: " ", with: "")
        case .quotaRemaining:
            firstLine = "配额剩余"
            secondLine = quotaBytes > 0
                ? TrafficByteFormatter.string(fromByteCount: max(0, quotaBytes - monthBytes)).replacingOccurrences(of: " ", with: "")
                : "未设置"
        }
        needsDisplay = true
        return preferredWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        NSAttributedString(string: firstLine, attributes: attributes)
            .draw(in: NSRect(x: 2, y: 0, width: bounds.width - 4, height: 11))
        NSAttributedString(string: secondLine, attributes: attributes)
            .draw(in: NSRect(x: 2, y: 10, width: bounds.width - 4, height: 11))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private static func rateString(from bytesPerSecond: Double) -> String {
        ByteRateFormatter.string(from: bytesPerSecond)
            .replacingOccurrences(of: " ", with: "")
    }

    private var preferredWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        ]
        let firstWidth = ceil((firstLine as NSString).size(withAttributes: attributes).width)
        let secondWidth = ceil((secondLine as NSString).size(withAttributes: attributes).width)
        return max(firstWidth, secondWidth) + 8
    }
}
