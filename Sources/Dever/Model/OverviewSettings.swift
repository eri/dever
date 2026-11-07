import Foundation

/// How the Overview lists the projects: the order, the grouping, the density, the columns,
/// and which projects stay out of the way. Saved with the rest of the settings
/// (`AppState.overview`); the page reads it, Settings › Overview and the page's own
/// View control write it.
struct OverviewSettings: Codable, Equatable {
    enum Sort: String, CaseIterable, Identifiable, Codable {
        case name, activity, health, targetDate
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: "Name"
            case .activity: "Activity"
            case .health: "Health"
            case .targetDate: "Target date"
            }
        }
    }

    enum Group: String, CaseIterable, Identifiable, Codable {
        case none, health, repository, team
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "None"
            case .health: "Health"
            case .repository: "Repository"
            case .team: "Team"
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable, Codable {
        case comfortable, compact
        var id: String { rawValue }
        var label: String {
            switch self {
            case .comfortable: "Comfortable"
            case .compact: "Compact"
            }
        }
        /// Row height; the header row and the group rows follow.
        var rowHeight: CGFloat { self == .compact ? 44 : 56 }
    }

    /// The columns after the project's name, in the order they are drawn.
    enum Column: String, CaseIterable, Identifiable, Codable {
        case slack, linear, github, preview, target, health
        var id: String { rawValue }
        var label: String {
            switch self {
            case .slack: "Slack"
            case .linear: "Linear"
            case .github: "GitHub"
            case .preview: "Preview"
            case .target: "Target"
            case .health: "Health"
            }
        }
        /// What the column shows, for the Settings row and the column header's tooltip.
        var detail: String {
            switch self {
            case .slack: "Messages this week, last activity"
            case .linear: "Issues shipped"
            case .github: "Pipeline, open pull requests"
            case .preview: "The followed pull request's preview"
            case .target: "Linear target date"
            case .health: "Needs attention, quiet, on track"
            }
        }
        /// The column's width in points; the project column takes the rest.
        var width: CGFloat {
            switch self {
            case .slack: 76
            case .linear: 136
            case .github: 124
            case .preview: 96
            case .target: 72
            case .health: 124
            }
        }
    }

    var sort: Sort = .health
    var group: Group = .none
    var density: Density = .comfortable
    var columns: Set<Column> = Set(Column.allCases)
    /// Favourite projects first, whatever the order.
    var pinFavourites = true
    /// Projects whose every Linear issue is done leave the list.
    var hideFinished = false

    static let key = "overview"

    /// The columns to draw, in their fixed order.
    var shownColumns: [Column] { Column.allCases.filter { columns.contains($0) } }

    /// Snapshots: `DEVER_SNAPSHOT_OVERVIEW=sort=name,group=health,density=compact,columns=slack+linear,hideFinished=1`
    /// runs the page under those settings; nothing is written back.
    static var simulated: OverviewSettings? {
        guard let raw = ProcessInfo.processInfo.environment["DEVER_SNAPSHOT_OVERVIEW"] else { return nil }
        var s = OverviewSettings()
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "sort": s.sort = Sort(rawValue: pair[1]) ?? s.sort
            case "group": s.group = Group(rawValue: pair[1]) ?? s.group
            case "density": s.density = Density(rawValue: pair[1]) ?? s.density
            case "columns": s.columns = Set(pair[1].split(separator: "+").compactMap { Column(rawValue: String($0)) })
            case "pin": s.pinFavourites = pair[1] == "1"
            case "hideFinished": s.hideFinished = pair[1] == "1"
            default: break
            }
        }
        return s
    }

    static func load() -> OverviewSettings {
        if let simulated { return simulated }
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(OverviewSettings.self, from: data) else { return OverviewSettings() }
        return saved
    }

    func save() {
        guard Self.simulated == nil else { return }
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
