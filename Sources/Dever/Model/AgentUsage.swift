import Foundation

// What is left of a coding agent's plan, as the tool itself reports it (docs/agents-integration.md,
// section 2.6). Read on demand, kept in memory, shown with its age: a figure is never drawn as
// current once it is old, and never at all once its window has reset.

/// A tool's plan usage at one moment.
struct AgentUsage: Equatable {
    /// One rate-limit window: the rolling five hours, the week.
    struct Window: Equatable {
        var usedPercent: Double
        var minutes: Int
        var resetsAt: Date?

        var leftPercent: Int { max(0, min(100, Int((100 - usedPercent).rounded()))) }
        /// "5-hour window", "week", or the length in words for any other plan.
        var name: String {
            switch minutes {
            case 300: "5-hour window"
            case 10_080: "week"
            case let m where m % 1_440 == 0: "\(m / 1_440)-day window"
            case let m where m % 60 == 0: "\(m / 60)-hour window"
            default: "\(minutes)-minute window"
            }
        }
    }

    /// The windows the plan has, shortest first; a plan may have none (credits, or no fixed limit).
    var windows: [Window]
    var plan: String?
    /// The tool says the limit is reached: nothing more can run until a reset.
    var limitReached: Bool
    var unlimitedCredits = false
    var creditBalance: String?
    var readAt: Date

    /// How long a reading is shown as current.
    static let fresh: TimeInterval = 300

    /// The windows that have not reset since the reading: a reset makes its figure meaningless.
    func live(at now: Date) -> [Window] {
        windows.filter { $0.resetsAt.map { $0 > now } ?? true }
    }

    /// Nothing can be said any more: the plan has windows and every one reset since the reading.
    func lapsed(at now: Date) -> Bool { !windows.isEmpty && live(at: now).isEmpty }

    /// The tool cannot take work now, or has under a tenth of a window left.
    func tight(at now: Date) -> Bool {
        !lapsed(at: now) && (limitReached || live(at: now).contains { $0.leftPercent < 10 })
    }

    /// One short line for a menu row: "62% left · resets 14:10".
    func short(at now: Date, zone: TimeZone = .current) -> String {
        if lapsed(at: now) { return "Usage unknown since its window reset" }
        let live = live(at: now)
        var parts: [String]
        if limitReached {
            parts = ["Limit reached"]
            if let reset = live.compactMap(\.resetsAt).min() { parts.append("resets \(Self.clock(reset, now: now, zone: zone))") }
        } else if let first = live.first {
            parts = ["\(first.leftPercent)% left"]
            if let reset = first.resetsAt { parts.append("resets \(Self.clock(reset, now: now, zone: zone))") }
        } else {
            parts = [limitless]
        }
        return (parts + age(at: now)).joined(separator: " · ")
    }

    /// The whole reading for Settings: "62% of the 5-hour window left, resets 14:10 · week 80% left".
    func line(at now: Date, zone: TimeZone = .current) -> String {
        if lapsed(at: now) { return "Usage unknown since its window reset" }
        let live = live(at: now)
        var parts: [String] = []
        if limitReached {
            let reset = live.compactMap(\.resetsAt).min().map { ", resets \(Self.clock($0, now: now, zone: zone))" } ?? ""
            parts.append("Limit reached\(reset)")
        }
        for (index, window) in live.enumerated() {
            let reset = window.resetsAt.map { ", resets \(Self.clock($0, now: now, zone: zone))" } ?? ""
            // The first window is the sentence; the others are short.
            parts.append(index == 0 && !limitReached ? "\(window.leftPercent)% of the \(window.name) left\(reset)"
                                                     : "\(window.name) \(window.leftPercent)% left")
        }
        if live.isEmpty && !limitReached { parts.append(limitless) }
        return (parts + age(at: now)).joined(separator: " · ")
    }

    private var limitless: String {
        if unlimitedCredits { return "No fixed limit" }
        if let creditBalance { return "Credits: \(creditBalance)" }
        return "No plan limit reported"
    }

    /// "read 20 min ago" once the reading is no longer fresh.
    private func age(at now: Date) -> [String] {
        let seconds = now.timeIntervalSince(readAt)
        guard seconds > Self.fresh else { return [] }
        let minutes = Int(seconds / 60)
        return [minutes < 60 ? "read \(minutes) min ago" : "read \(minutes / 60) h ago"]
    }

    /// "14:10" today, "Mon 14:10" another day.
    static func clock(_ date: Date, now: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return formatter.string(from: date)
    }
}

extension AgentUsage {
    /// The answer of Codex's app server to `account/rateLimits/read` (its `result`).
    private struct CodexAnswer: Decodable {
        struct Window: Decodable {
            var usedPercent: Double
            var windowDurationMins: Int?
            var resetsAt: Double?
        }
        struct Credits: Decodable {
            var hasCredits: Bool?
            var unlimited: Bool?
            var balance: String?
        }
        struct Limits: Decodable {
            var primary: Window?
            var secondary: Window?
            var credits: Credits?
            var planType: String?
            var rateLimitReachedType: String?
        }
        var rateLimits: Limits
        var ordinaryUsageAllowed: Bool?
    }

    /// Either window may be absent: some plans have no five-hour limit, some only credits.
    /// Nothing that names the account is kept.
    static func codex(result: Data, at now: Date) throws -> AgentUsage {
        let answer = try JSONDecoder().decode(CodexAnswer.self, from: result)
        let limits = answer.rateLimits
        let windows = [limits.primary, limits.secondary].compactMap { $0 }.compactMap { window -> Window? in
            guard let minutes = window.windowDurationMins else { return nil }
            return Window(usedPercent: window.usedPercent, minutes: minutes,
                          resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) })
        }.sorted { $0.minutes < $1.minutes }
        return AgentUsage(windows: windows, plan: limits.planType,
                          limitReached: limits.rateLimitReachedType != nil || answer.ordinaryUsageAllowed == false,
                          unlimitedCredits: limits.credits?.unlimited == true,
                          creditBalance: limits.credits?.hasCredits == true ? limits.credits?.balance : nil,
                          readAt: now)
    }
}

/// What Dever knows of one tool's usage.
struct AgentUsageEntry: Equatable {
    var usage: AgentUsage?
    /// Why the last reading failed, in the tool's own words when it gave some; the last value stays.
    var problem: String?
    var loading = false
    /// The last time the tool was asked, answered or not: a refusal is not asked again within the budget either.
    var checkedAt: Date?
}

/// Whether a tool's usage can be read from outside it at all.
extension AgentTool {
    /// Codex answers on demand through its own app server. Claude Code has no outside read: its
    /// figures only arrive from inside a session (phase 2).
    var usageIsReadable: Bool { self == .codex }
}

/// Which agent has the most usage left, for the "Most usage left" choice. The two plans are not
/// amounts of the same thing, so this only compares what each tool says of its own windows: the
/// share left of the tightest one. A tool whose usage cannot be read is never ranked on a guess:
/// it is taken when the tools that can be read are nearly out, or when nothing is known at all.
enum AgentRecommendation {
    struct Pick: Equatable {
        var tool: AgentTool
        /// Why, in a few words: "62% left", "Codex is nearly out", "usage not known yet".
        var reason: String
    }

    /// Under this share of its tightest window a tool is "nearly out".
    static let low = 10

    /// The share left of the tightest window that still stands: 0 once the limit is reached, 100
    /// for a plan without a window; nil when nothing can be said (never read, or all reset since).
    static func left(_ usage: AgentUsage?, at now: Date) -> Int? {
        guard let usage, !usage.lapsed(at: now) else { return nil }
        if usage.limitReached { return 0 }
        return usage.live(at: now).map(\.leftPercent).min() ?? 100
    }

    /// `fallback` is the agent used last: the choice when nothing is known.
    static func pick(_ entries: [AgentTool: AgentUsageEntry], at now: Date, fallback: AgentTool,
                     tools: [AgentTool] = AgentTool.allCases) -> Pick {
        let known = tools.compactMap { tool in left(entries[tool]?.usage, at: now).map { (tool: tool, left: $0) } }
        let unknown = tools.filter { tool in !known.contains { $0.tool == tool } }
        guard let best = known.max(by: { ($0.left, $0.tool == fallback ? 1 : 0) < ($1.left, $1.tool == fallback ? 1 : 0) }) else {
            return Pick(tool: tools.contains(fallback) ? fallback : tools[0], reason: "usage not known yet")
        }
        if best.left < low, let other = unknown.first(where: { $0 == fallback }) ?? unknown.first {
            return Pick(tool: other, reason: "\(best.tool.label) is nearly out")
        }
        return Pick(tool: best.tool, reason: best.left == 0 ? "limit reached everywhere" : "\(best.left)% left")
    }
}

extension AgentUsage {
    /// What an agent passes to `report_usage`, read from its own usage tool. Nil when no window
    /// came with a figure: nothing is drawn from a guess.
    static func reported(_ arguments: [String: String], at now: Date) -> AgentUsage? {
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func percent(_ key: String) -> Double? {
            arguments[key].flatMap { Double($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                .map { min(max($0, 0), 100) }
        }
        func date(_ key: String) -> Date? { arguments[key].flatMap { iso.date(from: $0) ?? fractional.date(from: $0) } }
        var windows: [Window] = []
        if let used = percent("five_hour_used") { windows.append(.init(usedPercent: used, minutes: 300, resetsAt: date("five_hour_resets"))) }
        if let used = percent("week_used") { windows.append(.init(usedPercent: used, minutes: 10_080, resetsAt: date("week_resets"))) }
        guard !windows.isEmpty else { return nil }
        let plan = arguments["plan"].flatMap { $0.isEmpty ? nil : $0 }
        return AgentUsage(windows: windows, plan: plan, limitReached: windows.contains { $0.usedPercent >= 100 }, readAt: now)
    }
}
