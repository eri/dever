import Foundation
import UserNotifications

/// Things that need someone to act, each with its own on/off setting.
enum AlertKind: String, CaseIterable, Identifiable {
    case pipelineFailing, pastTarget, mergedButOpen

    var id: String { rawValue }
    var settingKey: String { "notify.\(rawValue)" }

    var settingLabel: String {
        switch self {
        case .pipelineFailing: "Notify when a project's pipeline starts failing"
        case .pastTarget: "Notify when a project passes its target date"
        case .mergedButOpen: "Notify when issues have merged pull requests but aren't done"
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }
}

/// One alert for one project. `key` identifies the situation: the same key is
/// notified once, and only again after it cleared and came back.
struct ProjectAlert: Hashable {
    var kind: AlertKind
    var key: String
    var title: String
    var body: String
}

extension Project {
    func alerts(_ s: ProjectSnapshot) -> [ProjectAlert] {
        var out: [ProjectAlert] = []
        if s.github?.pipeline == .failing {
            out.append(.init(kind: .pipelineFailing, key: "pipeline", title: "\(name): pipeline failing",
                             body: s.github?.scoped == true
                                 ? "A pull request branch of this project fails its checks."
                                 : "The default branch fails its checks."))
        }
        if let l = s.linear, let target = l.targetDate,
           target < Calendar.current.startOfDay(for: Date()), l.done < l.total {
            out.append(.init(kind: .pastTarget, key: "target:\(target.timeIntervalSince1970)",
                             title: "\(name): past target date",
                             body: Plural.text("^[\(l.total - l.done) issue](inflect: true) still open after \(target.formatted(date: .abbreviated, time: .omitted)).")))
        }
        if let stale = s.github?.mergedButOpen, !stale.isEmpty {
            // Keyed by the issue list, so a newly affected issue notifies again.
            out.append(.init(kind: .mergedButOpen, key: "merged:" + stale.joined(separator: ","),
                             title: "\(name): " + Plural.text("^[\(stale.count) issue](inflect: true) to close"),
                             body: "Merged but not done in Linear: \(stale.prefix(5).joined(separator: ", "))\(stale.count > 5 ? "…" : "")."))
        }
        return out
    }
}

/// Posts macOS notifications for alerts that newly appear.
@MainActor
final class Notifier {
    static let shared = Notifier()
    nonisolated static let projectIDKey = "projectID"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Compares each project's alerts with those already notified and posts the new ones.
    /// A project seen for the first time only records its alerts, so launching the app
    /// doesn't replay every known problem.
    func process(projects: [Project], snapshots: [UUID: ProjectSnapshot]) {
        for project in projects {
            guard let snapshot = snapshots[project.id] else { continue }
            let storageKey = "notified.\(project.id.uuidString)"
            let current = project.alerts(snapshot)
            let previous = defaults.stringArray(forKey: storageKey).map(Set.init)
            defaults.set(current.map(\.key), forKey: storageKey)
            guard let previous else { continue }
            for alert in current where !previous.contains(alert.key) && alert.kind.isEnabled {
                post(alert, project: project)
            }
        }
    }

    private func post(_ alert: ProjectAlert, project: Project) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = project.id.uuidString
        content.userInfo = [Self.projectIDKey: project.id.uuidString]
        center.add(UNNotificationRequest(identifier: "\(project.id.uuidString).\(alert.key)",
                                         content: content, trigger: nil))
    }
}

extension Notification.Name {
    /// Posted with the project's UUID as `object` when a notification is clicked.
    static let openProject = Notification.Name("dever.openProject")
}
