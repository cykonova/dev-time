import Foundation
import Combine
import IOKit

final class TimerManager: ObservableObject {
    @Published var isTracking = false
    @Published var isAway = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var todayTotalSeconds: TimeInterval = 0
    @Published var awayStartTime: Date?
    @Published var showAwayPrompt = false
    @Published var awayDuration: TimeInterval = 0

    let storage = Storage()

    @Published var appData: AppData
    @Published var activeChargeCodeId: UUID?
    private var activeEntry: TimeEntry?

    private var tickTimer: Timer?
    private var saveTimer: Timer?
    private var idleCheckTimer: Timer?

    @Published var awayThresholdMinutes: Double = 5 {
        didSet { saveSettings() }
    }
    var awayThresholdSeconds: TimeInterval { awayThresholdMinutes * 60 }

    private let settingsURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DevTime", isDirectory: true)
        return dir.appendingPathComponent("settings.json")
    }()

    var emoji: String {
        if isAway { return "\u{1F4A4}" } // zzz

        let hours = todayTotalSeconds / 3600
        if hours < 4 { return "\u{1F600}" }      // smile
        if hours < 8 { return "\u{1F643}" }      // upside down
        if hours < 10 { return "\u{1F633}" }     // wide eyes
        return "\u{1F480}"                        // skull
    }

    var clockString: String {
        let h = Int(elapsedSeconds) / 3600
        let m = (Int(elapsedSeconds) % 3600) / 60
        let s = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var totalClockString: String {
        let h = Int(todayTotalSeconds) / 3600
        let m = (Int(todayTotalSeconds) % 3600) / 60
        let s = Int(todayTotalSeconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var menuBarTitle: String {
        if !isTracking { return "\(emoji) --:--:--" }
        return "\(emoji) \(totalClockString)"
    }

    init() {
        self.appData = AppData()
        self.appData = storage.load()
        loadSettings()
        recalcTodayTotal()
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let minutes = dict["awayThresholdMinutes"] as? Double else { return }
        awayThresholdMinutes = minutes
    }

    private func saveSettings() {
        let dict: [String: Any] = ["awayThresholdMinutes": awayThresholdMinutes]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    func start(chargeCodeId: UUID) {
        guard !isTracking else { return }
        activeChargeCodeId = chargeCodeId
        let entry = TimeEntry(chargeCodeId: chargeCodeId)
        activeEntry = entry
        isTracking = true
        isAway = false
        elapsedSeconds = 0

        startTimers()
    }

    func switchTask(to chargeCodeId: UUID) {
        guard isTracking, chargeCodeId != activeChargeCodeId else { return }
        finalizeEntry()
        activeChargeCodeId = chargeCodeId
        let entry = TimeEntry(chargeCodeId: chargeCodeId)
        activeEntry = entry
        elapsedSeconds = 0
        recalcTodayTotal()
    }

    func stop() {
        guard isTracking else { return }
        finalizeEntry()
        isTracking = false
        isAway = false
        stopTimers()
        elapsedSeconds = 0
        recalcTodayTotal()
    }

    func keepAwayTime() {
        // Away time counts as work (meeting, etc.)
        showAwayPrompt = false
        isAway = false
        awayStartTime = nil
        awayDuration = 0
    }

    func discardAwayTime() {
        // Remove away time from current entry
        showAwayPrompt = false
        isAway = false
        if awayDuration > 0 {
            activeEntry?.awaySeconds += awayDuration
        }
        awayStartTime = nil
        awayDuration = 0
        recalcElapsed()
    }

    // MARK: - Idle Detection

    private func getSystemIdleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator)
        guard result == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleObj = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleObj) / 1_000_000_000
    }

    // MARK: - Timer Callbacks

    private func startTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.autoSave()
        }
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    private func stopTimers() {
        tickTimer?.invalidate()
        saveTimer?.invalidate()
        idleCheckTimer?.invalidate()
        tickTimer = nil
        saveTimer = nil
        idleCheckTimer = nil
    }

    private func tick() {
        recalcElapsed()
        recalcTodayTotal()
    }

    private func recalcElapsed() {
        guard let entry = activeEntry else { return }
        elapsedSeconds = entry.activeSeconds
    }

    private func checkIdle() {
        let idle = getSystemIdleSeconds()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if !self.isAway && idle >= self.awayThresholdSeconds {
                // User went away
                self.isAway = true
                self.awayStartTime = Date().addingTimeInterval(-idle)
                self.awayDuration = idle
            } else if self.isAway && idle < 10 {
                // User came back
                if let start = self.awayStartTime {
                    self.awayDuration = Date().timeIntervalSince(start)
                }
                // Defer to next run loop to avoid triggering window creation mid-layout
                DispatchQueue.main.async {
                    self.showAwayPrompt = true
                }
            } else if self.isAway {
                // Still away, update duration
                if let start = self.awayStartTime {
                    self.awayDuration = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func autoSave() {
        saveCurrentState()
    }

    func saveCurrentState() {
        guard isTracking, let entry = activeEntry else {
            storage.save(appData)
            return
        }

        var snapshot = entry
        snapshot.endTime = Date()

        ensureLog(for: snapshot.startTime)
        if let idx = appData.logs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: snapshot.startTime) }) {
            // Update or append the active entry
            if let entryIdx = appData.logs[idx].entries.firstIndex(where: { $0.id == snapshot.id }) {
                appData.logs[idx].entries[entryIdx] = snapshot
            } else {
                appData.logs[idx].entries.append(snapshot)
            }
        }
        storage.save(appData)
    }

    private func finalizeEntry() {
        guard var entry = activeEntry else { return }
        entry.endTime = Date()
        activeEntry = entry

        ensureLog(for: entry.startTime)
        if let idx = appData.logs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: entry.startTime) }) {
            if let entryIdx = appData.logs[idx].entries.firstIndex(where: { $0.id == entry.id }) {
                appData.logs[idx].entries[entryIdx] = entry
            } else {
                appData.logs[idx].entries.append(entry)
            }
        }

        storage.save(appData)
        activeEntry = nil
    }

    private func ensureLog(for date: Date) {
        if !appData.logs.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            appData.logs.append(DayLog(date: date))
        }
    }

    private func recalcTodayTotal() {
        var total: TimeInterval = 0
        if let todayLog = appData.logs.first(where: { Calendar.current.isDateInToday($0.date) }) {
            total = todayLog.totalActiveSeconds
        }
        if let entry = activeEntry,
           !(appData.logs.first(where: { Calendar.current.isDateInToday($0.date) })?.entries.contains(where: { $0.id == entry.id }) ?? false) {
            total += entry.activeSeconds
        }
        todayTotalSeconds = total
    }

    // MARK: - Charge Code Management

    func addChargeCode(name: String, code: String) {
        let cc = ChargeCode(name: name, code: code)
        appData.chargeCodes.append(cc)
        storage.save(appData)
    }

    func removeChargeCode(_ id: UUID) {
        appData.chargeCodes.removeAll { $0.id == id }
        storage.save(appData)
    }

    func chargeCodeName(for id: UUID) -> String {
        appData.chargeCodes.first { $0.id == id }?.name ?? "Unknown"
    }

    // MARK: - Entry CRUD

    func insertEntry(into logDate: Date, chargeCodeId: UUID, start: Date, end: Date) {
        ensureLog(for: logDate)
        guard let idx = appData.logs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: logDate) }) else { return }

        let newEntry = TimeEntry(chargeCodeId: chargeCodeId, startTime: start, endTime: end)
        appData.logs[idx].entries = resolveOverlaps(existing: appData.logs[idx].entries, inserting: newEntry)
        storage.save(appData)
        recalcTodayTotal()
    }

    func updateEntry(in logDate: Date, entryId: UUID, chargeCodeId: UUID, start: Date, end: Date) {
        guard let idx = appData.logs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: logDate) }) else { return }

        let originalAway = appData.logs[idx].entries.first(where: { $0.id == entryId })?.awaySeconds ?? 0
        let updated = TimeEntry(id: entryId, chargeCodeId: chargeCodeId, startTime: start, endTime: end, awaySeconds: originalAway)
        appData.logs[idx].entries = resolveOverlaps(existing: appData.logs[idx].entries, inserting: updated)
        storage.save(appData)
        recalcTodayTotal()
    }

    func deleteEntry(from logDate: Date, entryId: UUID) {
        guard let idx = appData.logs.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: logDate) }) else { return }
        appData.logs[idx].entries.removeAll { $0.id == entryId }
        // Remove empty day logs
        if appData.logs[idx].entries.isEmpty {
            appData.logs.remove(at: idx)
        }
        storage.save(appData)
        recalcTodayTotal()
    }

    // MARK: - Overlap Resolution

    private func resolveOverlaps(existing: [TimeEntry], inserting: TimeEntry) -> [TimeEntry] {
        let iStart = inserting.startTime
        let iEnd = inserting.endTime ?? Date()

        var result: [TimeEntry] = []

        for entry in existing {
            // Skip the entry being replaced (edit case)
            if entry.id == inserting.id { continue }
            // Don't touch live/active entries (no endTime)
            if entry.endTime == nil {
                result.append(entry)
                continue
            }

            let eStart = entry.startTime
            let eEnd = entry.endTime!

            // No overlap — keep as-is
            if eEnd <= iStart || eStart >= iEnd {
                result.append(entry)
                continue
            }

            // Left fragment: entry started before the insertion
            if eStart < iStart {
                let fragment = TimeEntry(chargeCodeId: entry.chargeCodeId, startTime: eStart, endTime: iStart,
                                         awaySeconds: proportionalAway(original: entry, fragmentStart: eStart, fragmentEnd: iStart))
                result.append(fragment)
            }

            // Right fragment: entry extends past the insertion
            if eEnd > iEnd {
                let fragment = TimeEntry(chargeCodeId: entry.chargeCodeId, startTime: iEnd, endTime: eEnd,
                                         awaySeconds: proportionalAway(original: entry, fragmentStart: iEnd, fragmentEnd: eEnd))
                result.append(fragment)
            }
            // Fully contained entries are dropped (no append)
        }

        result.append(inserting)
        result.sort { $0.startTime < $1.startTime }
        return result
    }

    private func proportionalAway(original: TimeEntry, fragmentStart: Date, fragmentEnd: Date) -> TimeInterval {
        let originalDuration = (original.endTime ?? Date()).timeIntervalSince(original.startTime)
        guard originalDuration > 0 else { return 0 }
        let fragmentDuration = fragmentEnd.timeIntervalSince(fragmentStart)
        return original.awaySeconds * (fragmentDuration / originalDuration)
    }
}
