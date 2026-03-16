import Foundation

struct ChargeCode: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var code: String

    init(id: UUID = UUID(), name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }
}

struct TimeEntry: Identifiable, Codable {
    let id: UUID
    let chargeCodeId: UUID
    let startTime: Date
    var endTime: Date?
    var awaySeconds: TimeInterval

    init(id: UUID = UUID(), chargeCodeId: UUID, startTime: Date = Date(), endTime: Date? = nil, awaySeconds: TimeInterval = 0) {
        self.id = id
        self.chargeCodeId = chargeCodeId
        self.startTime = startTime
        self.endTime = endTime
        self.awaySeconds = awaySeconds
    }

    var activeSeconds: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime) - awaySeconds
    }
}

struct DayLog: Identifiable, Codable {
    let id: UUID
    let date: Date
    var entries: [TimeEntry]

    init(id: UUID = UUID(), date: Date = Date(), entries: [TimeEntry] = []) {
        self.id = id
        self.date = date
        self.entries = entries
    }

    var totalActiveSeconds: TimeInterval {
        entries.reduce(0) { $0 + $1.activeSeconds }
    }
}

struct AppData: Codable {
    var chargeCodes: [ChargeCode]
    var logs: [DayLog]

    init(chargeCodes: [ChargeCode] = [], logs: [DayLog] = []) {
        self.chargeCodes = chargeCodes
        self.logs = logs
    }
}
