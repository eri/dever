import Foundation

/// How the Overview lists the projects: the order, the grouping, the density, the columns,
/// and which projects stay out of the way. Saved with the rest of the settings
/// (`AppState.overview`); the page reads it, Settings › Overview and the page's own
/// View control write it.
struct OverviewSettings: Codable, Equatable {
    /// Pinned projects always come first. `forYou` then puts the projects where something waits
    /// for you, then the most recently active; the others drop the waiting step.
    enum Sort: String, CaseIterable, Identifiable, Codable {
        case forYou, activity, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .forYou: "For you"
            case .activity: "Activity"
            case .name: "Name"
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

    /// The optional columns between the project's name and its status, in the order they are
    /// drawn. The status at the trailing edge (what blocks, or issues shipped) always shows.
    enum Column: String, CaseIterable, Identifiable, Codable {
        case slack, linear, github, preview, target
        var id: String { rawValue }
        var label: String {
            switch self {
            case .slack: "Slack"
            case .linear: "Issues shipped"
            case .github: "GitHub"
            case .preview: "Preview"
            case .target: "Due date"
            }
        }
        /// The column's name on a Settings chip, where the tool's name is enough.
        var chip: String {
            switch self {
            case .slack: "Slack"
            case .linear: "Linear"
            case .github: "GitHub"
            case .preview: "Preview"
            case .target: "Due date"
            }
        }
        /// What the column shows, for the Settings row and the column header's tooltip.
        var detail: String {
            switch self {
            case .slack: "Unread messages in the channel"
            case .linear: "Linear issues done, or merged in GitHub, out of all"
            case .github: "Pipeline, open pull requests"
            case .preview: "The followed pull request's preview"
            case .target: "The Linear project's target date"
            }
        }
        /// The column's width in points; the project column takes the rest.
        var width: CGFloat {
            switch self {
            case .slack: 88
            case .linear: 124
            case .github: 120
            case .preview: 80
            case .target: 72
            }
        }
    }

    var sort: Sort = .forYou
    var group: Group = .none
    var density: Density = .comfortable
    /// Slack's unread count only: what blocks and what shipped are in the status already.
    var columns: Set<Column> = [.slack]
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
