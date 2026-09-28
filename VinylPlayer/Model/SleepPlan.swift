import Foundation

struct SleepPlan: Equatable {
    var deadline: Date?
    var afterCurrentTrack = false
    var isActive: Bool { deadline != nil || afterCurrentTrack }
    func isExpired(at date: Date) -> Bool { deadline.map { date >= $0 } ?? false }
}
