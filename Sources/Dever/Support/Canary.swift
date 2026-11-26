import Foundation
import SwiftUI

/// Dever Canary: a build of Dever with made-up data, to see every state of the app without a
/// project in progress (`CANARY=1 ./scripts/build-app.sh` → `build/Dever Canary.app`). It is its
/// own app: another bundle identifier (so its own settings), its own Keychain entry and its own
/// folder, so it never reads or writes the real app's tokens, projects or caches; it sends nothing
/// to Slack, Linear or GitHub, and listens to no agent.
enum Canary {
    static let isOn: Bool = Bundle.main.bundleIdentifier?.hasSuffix(".canary") == true
        || ProcessInfo.processInfo.environment["DEVER_CANARY"] == "1"

    /// The folder under Application Support, and the Keychain service.
    static var folder: String { isOn ? "Dever Canary" : "Dever" }
    static var keychainService: String { isOn ? "io.github.eri.dever.canary" : "io.github.eri.dever" }

    /// The mark's colour in Canary: a canary yellow, so the two apps are never mistaken.
    static let tint = Color(red: 1.0, green: 0.80, blue: 0.24)

    /// What every call to a service answers in Canary.
    static let refusal = "Dever Canary shows made-up data: nothing is sent to Slack, Linear or GitHub"

    /// The made-up project the app opens on.
    static let projectID = UUID(uuidString: "5C0FFEE0-CA4A-4E00-8000-000000000001")!

    /// Before anything reads them: the demo switches the screens already know, and the app opens on the project.
    static func prepare() {
        guard isOn else { return }
        for (key, value) in ["DEVER_SNAPSHOT_DELIVERY": "canary", "DEVER_SNAPSHOT_AGENT_SESSION": "canary",
                             "DEVER_SNAPSHOT_AGENT_USAGE": "1"] where ProcessInfo.processInfo.environment[key] == nil {
            setenv(key, value, 1)
        }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "onboardingDone")
        if defaults.string(forKey: "displayName") == nil { defaults.set("Sam", forKey: "displayName") }
        defaults.set(Preferences.Landing.lastProject.rawValue, forKey: Preferences.landingKey)
        defaults.set(projectID.uuidString, forKey: Preferences.lastProjectKey)
        if defaults.string(forKey: AgentPreferences.preferredKey) == nil {
            defaults.set(AgentChoice.tool(.claudeCode).stored, forKey: AgentPreferences.preferredKey)
        }
    }

    /// The project Canary shows; made up, like everything in it.
    static var project: Project {
        var project = Project(name: "Checkout revamp")
        project.id = projectID
        project.linear = .init(id: "canary-linear", name: "Checkout revamp", url: "https://linear.app")
        project.githubRepos = ["demo/app"]
        return project
    }
}
