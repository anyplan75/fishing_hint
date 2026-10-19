import Foundation
import UserNotifications

// 저장한 자리의 해루질 시간만 아이폰 알림으로 올립니다.
// 낚시 시간과 저장하지 않은 자리는 알림으로 만들지 않습니다.

struct SavedSpotTimes: Identifiable {
    var id: String { pointId }
    var pointId: String
    var fishingLines: [String]
    var dayLines: [String]
    var nightLines: [String]
}

enum GleanAlarm {
    static func replace(items: [(point: FishingPoint, day: [Date], night: [Date])]) async -> String {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix("glean-") }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard !items.isEmpty else {
            return "저장한 자리가 없습니다. 저장하지 않은 자리는 시간 추천과 알림 대상이 아닙니다."
        }
        let allowed = await allow(center)
        guard allowed else {
            return "알림 권한이 없습니다. 해루질 시간은 화면에만 보이고, 알림은 오지 않습니다. 낚시 시간에는 알림을 보내지 않습니다."
        }
        var count = 0
        let soon = Date().addingTimeInterval(30)
        for item in items {
            for when in item.day where when >= soon {
                await add(center, point: item.point, when: when, night: false)
                count += 1
            }
            for when in item.night where when >= soon {
                await add(center, point: item.point, when: when, night: true)
                count += 1
            }
        }
        if count == 0 {
            return "등록한 자리의 받은 예보 안에 다가올 해루질 시간이 없습니다. 알림을 만들지 않았습니다. 낚시 시간에는 알림을 보내지 않습니다."
        }
        return "등록한 자리의 해루질 알림 \(count)건을 올려 두었습니다. 그 시간이 되면 알림이 옵니다. 낚시 시간에는 알림을 보내지 않습니다."
    }

    static func cancel(pointId: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix("glean-\(pointId)-") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func allow(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    private static func add(_ center: UNUserNotificationCenter, point: FishingPoint, when: Date, night: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = night ? "야간 해루질" : "주간 해루질"
        content.body = "\(point.name). \(FieldFormat.dayClock(when)). 받은 물때와 날씨로 고른 시간입니다."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let id = "glean-\(point.id)-\(night ? "night" : "day")-\(Int(when.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
