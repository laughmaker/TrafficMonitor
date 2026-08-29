import Foundation
import UserNotifications

enum QuotaNotifications {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func evaluate(
        today: Int64,
        week: Int64,
        billingCycle: Int64,
        network: Int64,
        networkName: String
    ) {
        guard UserDefaults.standard.bool(forKey: PreferenceKey.quotaAlertsEnabled) else { return }
        let threshold = max(UserDefaults.standard.double(forKey: PreferenceKey.quotaWarningPercent), 1)
        let bytesPerGB = 1_073_741_824.0
        let calendar = Calendar.current
        let now = Date()
        let dayID = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let weekID = calendar.component(.weekOfYear, from: now) + calendar.component(.yearForWeekOfYear, from: now) * 100
        let monthID = calendar.component(.month, from: now) + calendar.component(.year, from: now) * 100

        check(label: "今日", used: today, quota: UserDefaults.standard.double(forKey: PreferenceKey.dailyQuotaBytes) * bytesPerGB, periodID: "day-\(dayID)", threshold: threshold)
        check(label: "本周", used: week, quota: UserDefaults.standard.double(forKey: PreferenceKey.weeklyQuotaBytes) * bytesPerGB, periodID: "week-\(weekID)", threshold: threshold)
        check(label: "本账单周期", used: billingCycle, quota: UserDefaults.standard.double(forKey: PreferenceKey.monthlyQuotaBytes) * bytesPerGB, periodID: "month-\(monthID)", threshold: threshold)
        let networkQuota = Double(NetworkQuotaPreferences.quotas()[networkName] ?? 0)
        check(label: networkName, used: network, quota: networkQuota, periodID: "network-\(networkName)-\(monthID)", threshold: threshold)
    }

    private static func check(label: String, used: Int64, quota: Double, periodID: String, threshold: Double) {
        guard quota > 0 else { return }
        let percent = Double(used) / quota * 100
        guard percent >= threshold else { return }
        let noticeKey = "quotaNotice.\(periodID).\(Int(threshold))"
        guard !UserDefaults.standard.bool(forKey: noticeKey) else { return }
        UserDefaults.standard.set(true, forKey: noticeKey)

        let content = UNMutableNotificationContent()
        content.title = "流量配额提醒"
        content.body = "\(label)已使用 \(Int(percent))%，请留意剩余流量。"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: noticeKey, content: content, trigger: nil)
        )
    }
}
