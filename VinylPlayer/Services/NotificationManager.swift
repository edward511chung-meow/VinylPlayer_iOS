import Foundation
import UserNotifications
import SwiftData
import Combine

/// Manages all local notifications for VinylPlayer.
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    // MARK: - Notification Preferences

    @Published var listeningReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(listeningReminderEnabled, forKey: StorageKeys.listeningReminder) }
    }
    @Published var onThisDayEnabled: Bool {
        didSet { UserDefaults.standard.set(onThisDayEnabled, forKey: StorageKeys.onThisDay) }
    }
    @Published var milestoneEnabled: Bool {
        didSet { UserDefaults.standard.set(milestoneEnabled, forKey: StorageKeys.milestone) }
    }
    @Published var neglectedAlbumEnabled: Bool {
        didSet { UserDefaults.standard.set(neglectedAlbumEnabled, forKey: StorageKeys.neglectedAlbum) }
    }
    @Published var weeklyReportEnabled: Bool {
        didSet { UserDefaults.standard.set(weeklyReportEnabled, forKey: StorageKeys.weeklyReport) }
    }
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Storage Keys

    private enum StorageKeys {
        static let listeningReminder = "notification.listeningReminder"
        static let onThisDay = "notification.onThisDay"
        static let milestone = "notification.milestone"
        static let neglectedAlbum = "notification.neglectedAlbum"
        static let weeklyReport = "notification.weeklyReport"
        static let lastMilestoneCount = "notification.lastMilestoneCount"
    }

    // MARK: - Notification Identifiers

    enum Category: String {
        case listeningReminder = "LISTENING_REMINDER"
        case onThisDay = "ON_THIS_DAY"
        case milestone = "MILESTONE"
        case neglectedAlbum = "NEGLECTED_ALBUM"
        case weeklyReport = "WEEKLY_REPORT"
    }

    // MARK: - Milestone Thresholds

    private static let milestones = [10, 25, 50, 100, 150, 200, 300, 500, 1000]

    private let center = UNUserNotificationCenter.current()

    private init() {
        listeningReminderEnabled = UserDefaults.standard.bool(forKey: StorageKeys.listeningReminder)
        onThisDayEnabled = UserDefaults.standard.bool(forKey: StorageKeys.onThisDay)
        milestoneEnabled = UserDefaults.standard.bool(forKey: StorageKeys.milestone)
        neglectedAlbumEnabled = UserDefaults.standard.bool(forKey: StorageKeys.neglectedAlbum)
        weeklyReportEnabled = UserDefaults.standard.bool(forKey: StorageKeys.weeklyReport)

        // Default: all on for first launch
        if !UserDefaults.standard.bool(forKey: "notification.initialized") {
            listeningReminderEnabled = true
            onThisDayEnabled = true
            milestoneEnabled = true
            neglectedAlbumEnabled = true
            weeklyReportEnabled = true
            UserDefaults.standard.set(true, forKey: "notification.initialized")
        }

        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { checkAuthorizationStatus() }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Schedule All

    /// Call this on app launch and whenever preferences change.
    func rescheduleAll(context: ModelContext) {
        guard authorizationStatus == .authorized else { return }

        // Clear existing scheduled notifications
        center.removeAllPendingNotificationRequests()

        if listeningReminderEnabled {
            scheduleListeningReminder(context: context)
        }
        if onThisDayEnabled {
            scheduleOnThisDay(context: context)
        }
        if neglectedAlbumEnabled {
            scheduleNeglectedAlbum(context: context)
        }
        if weeklyReportEnabled {
            scheduleWeeklyReport(context: context)
        }
        // Milestones are checked on album add, not scheduled
    }

    // MARK: - 1. Listening Reminder

    /// "You haven't played any vinyl in X days" — only schedules if no
    /// ListeningRecord exists in the last 3 days.
    private func scheduleListeningReminder(context: ModelContext) {
        // Check if user has listened in the last 3 days
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        if let records = try? context.fetch(FetchDescriptor<ListeningRecord>()) {
            let hasRecentPlay = records.contains { $0.timestamp > threeDaysAgo }
            if hasRecentPlay { return } // User listened recently, no need to remind
        }

        let content = UNMutableNotificationContent()
        content.title = L("notification.reminder_title")
        content.body = L("notification.reminder_body")
        content.sound = .default
        content.categoryIdentifier = Category.listeningReminder.rawValue

        // Schedule once for today at 20:00 (or tomorrow if past 8pm)
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0

        let now = Date()
        let todayAt8pm = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        if now > todayAt8pm {
            // Already past 8pm, schedule for tomorrow
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            dateComponents.year = tomorrowComponents.year
            dateComponents.month = tomorrowComponents.month
            dateComponents.day = tomorrowComponents.day
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(Category.listeningReminder.rawValue).daily",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Call this when playback starts — cancel pending reminder.
    func cancelListeningReminder() {
        center.removePendingNotificationRequests(
            withIdentifiers: ["\(Category.listeningReminder.rawValue).daily"]
        )
    }

    // MARK: - 2. On This Day

    /// "X year(s) ago you added [album]" — scheduled daily at 10am.
    private func scheduleOnThisDay(context: ModelContext) {
        guard let albums = try? context.fetch(FetchDescriptor<Album>()) else { return }

        let calendar = Calendar.current
        let today = Date()

        let matches = albums.filter { album in
            guard let addedDate = album.addedDate else { return false }
            let addedComponents = calendar.dateComponents([.month, .day], from: addedDate)
            let todayComponents = calendar.dateComponents([.month, .day], from: today)
            let yearDiff = calendar.dateComponents([.year], from: addedDate, to: today).year ?? 0
            return addedComponents.month == todayComponents.month &&
                   addedComponents.day == todayComponents.day &&
                   yearDiff >= 1
        }

        guard let album = matches.randomElement(),
              let addedDate = album.addedDate else { return }

        let years = calendar.dateComponents([.year], from: addedDate, to: today).year ?? 1

        let content = UNMutableNotificationContent()
        content.title = L("notification.on_this_day_title")
        content.body = String(
            format: L("notification.on_this_day_body"),
            years,
            album.title,
            album.artist
        )
        content.sound = .default
        content.categoryIdentifier = Category.onThisDay.rawValue

        // Tomorrow at 10:00 (we check daily)
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        dateComponents.year = tomorrowComponents.year
        dateComponents.month = tomorrowComponents.month
        dateComponents.day = tomorrowComponents.day

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Category.onThisDay.rawValue).\(album.id)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - 3. Collection Milestone

    /// "Congrats! You've collected your Nth album!" — triggered on album add.
    func checkMilestone(albumCount: Int) {
        guard milestoneEnabled, authorizationStatus == .authorized else { return }

        let lastCount = UserDefaults.standard.integer(forKey: StorageKeys.lastMilestoneCount)

        for milestone in Self.milestones {
            if albumCount >= milestone && lastCount < milestone {
                let content = UNMutableNotificationContent()
                content.title = L("notification.milestone_title")
                content.body = String(format: L("notification.milestone_body"), milestone)
                content.sound = .default
                content.categoryIdentifier = Category.milestone.rawValue

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(Category.milestone.rawValue).\(milestone)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)

                UserDefaults.standard.set(albumCount, forKey: StorageKeys.lastMilestoneCount)
                break
            }
        }

        UserDefaults.standard.set(albumCount, forKey: StorageKeys.lastMilestoneCount)
    }

    // MARK: - 4. Neglected Album

    /// "You haven't played [album] in 3 months" — scheduled weekly on Sunday at 14:00.
    private func scheduleNeglectedAlbum(context: ModelContext) {
        guard let albums = try? context.fetch(FetchDescriptor<Album>()),
              let records = try? context.fetch(FetchDescriptor<ListeningRecord>()) else { return }

        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date())!

        // Find albums not played in 3+ months
        let recentAlbumIds = Set(
            records.filter { $0.timestamp > threeMonthsAgo }
                   .map { $0.albumId }
        )

        let neglected = albums.filter { !recentAlbumIds.contains($0.id) }
        guard let album = neglected.randomElement() else { return }

        let content = UNMutableNotificationContent()
        content.title = L("notification.neglected_title")
        content.body = String(
            format: L("notification.neglected_body"),
            album.title,
            album.artist
        )
        content.sound = .default
        content.categoryIdentifier = Category.neglectedAlbum.rawValue

        // Next Sunday at 14:00
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 14
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(Category.neglectedAlbum.rawValue).weekly",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - 5. Weekly Report

    /// "This week: X albums, Y minutes of listening" — scheduled Monday at 9am.
    private func scheduleWeeklyReport(context: ModelContext) {
        guard let records = try? context.fetch(FetchDescriptor<ListeningRecord>()) else { return }

        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        let weekRecords = records.filter { $0.timestamp > oneWeekAgo }
        let uniqueAlbums = Set(weekRecords.map { $0.albumId }).count
        let totalMinutes = Int(weekRecords.reduce(0) { $0 + $1.listenDuration } / 60)

        let content = UNMutableNotificationContent()
        content.title = L("notification.weekly_title")
        content.body = String(
            format: L("notification.weekly_body"),
            uniqueAlbums,
            totalMinutes
        )
        content.sound = .default
        content.categoryIdentifier = Category.weeklyReport.rawValue

        // Monday at 09:00
        var dateComponents = DateComponents()
        dateComponents.weekday = 2 // Monday
        dateComponents.hour = 9
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "\(Category.weeklyReport.rawValue).weekly",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
