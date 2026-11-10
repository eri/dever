import Foundation
import ServiceManagement

/// Settings that live in UserDefaults and are read outside of views: the refresh cadence,
/// where the app opens, launch at login. Each key is named here once.
enum Preferences {
    static let refreshMinutesKey = "refreshMinutes"
    static let landingKey = "landing"
    static let lastProjectKey = "lastProjectID"

    /// Minutes between two refreshes of every project; 5 unless set.
    static var refreshMinutes: Int {
        get { UserDefaults.standard.object(forKey: refreshMinutesKey) as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: refreshMinutesKey) }
    }
    static let refreshChoices = [1, 5, 15, 30]

    /// Days without a Slack message before a project reads "Quiet"; 14 unless set.
    static let quietAfterDaysKey = "quietAfterDays"
    static let quietChoices = [7, 14, 30]
    static var quietAfterDays: Int {
        get { UserDefaults.standard.object(forKey: quietAfterDaysKey) as? Int ?? 14 }
        set { UserDefaults.standard.set(newValue, forKey: quietAfterDaysKey) }
    }

    /// Which screen the window opens on.
    enum Landing: String, CaseIterable, Identifiable {
        case overview, lastProject
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .lastProject: "Last project"
            }
        }
    }

    static var landing: Landing {
        get { Landing(rawValue: UserDefaults.standard.string(forKey: landingKey) ?? "") ?? .overview }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: landingKey) }
    }

    /// The project last opened, for the "Last project" landing.
    static var lastProjectID: UUID? {
        get { UserDefaults.standard.string(forKey: lastProjectKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastProjectKey) }
    }

    // MARK: Launch at login (macOS 13+ login items; registered from the app's own bundle)

    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turns the login item on or off; throws when macOS refuses (an unsigned build, or
    /// the user disabled the app under System Settings › Login Items).
    static func setLaunchAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
