import Foundation
import SwiftUI

enum ServiceKind: String, CaseIterable, Identifiable, Codable {
    case slack, linear, github
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slack: "Slack"
        case .linear: "Linear"
        case .github: "GitHub"
        }
    }
    var symbol: String {
        switch self {
        case .slack: "number"
        case .linear: "checklist"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    case unauthorized(ServiceKind)
    case notConnected(ServiceKind)

    var errorDescription: String? {
        switch self {
        case .message(let m): m
        case .unauthorized(let s): "\(s.label): session expired, please reconnect the account."
        case .notConnected(let s): "\(s.label) is not connected."
        }
    }
}

struct Project: Codable, Identifiable, Hashable {
    struct SlackLink: Codable, Hashable { var id: String; var name: String }
    struct LinearLink: Codable, Hashable { var id: String; var name: String; var url: String }

    var id = UUID()
    var name: String
    var slack: SlackLink?
    var linear: LinearLink?
    var githubRepo: String?
    /// nil/false: only PRs linked to the project's Linear issues (shared repositories).
    var githubWholeRepo: Bool?
    var createdAt = Date()

    /// Whether to show every PR of the repository rather than those of the project's issues.
    var showsWholeRepository: Bool { githubWholeRepo == true || linear == nil }

    /// A project is trackable once both Slack and Linear are linked.
    var isComplete: Bool { slack != nil && linear != nil }
}

/// Slack channel naming convention: `<prefix><slug>`.
enum Naming {
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-").prefix(80).description
    }

    static func channelName(for project: String, prefix: String) -> String {
        String((prefix + slug(project)).prefix(80))
    }

    /// Readable project name from a channel: `proj-acme-corp` → `Acme Corp`.
    static func projectName(fromChannel channel: String, prefix: String) -> String {
        var base = channel
        if !prefix.isEmpty, base.hasPrefix(prefix) { base.removeFirst(prefix.count) }
        return base.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        slug(a) == slug(b)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var github: GitHubCredentials? { didSet { saveCredentials() } }
    @Published var slack: SlackCredentials? { didSet { saveCredentials() } }
    @Published var linear: LinearCredentials? { didSet { saveCredentials() } }
    @Published var projects: [Project] = [] { didSet { saveProjects() } }
    @Published var lastError: String?

    private let projectsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dever", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }()

    init() {
        if let stored = Keychain.load(StoredCredentials.self, for: Self.credentialsKey) {
            github = stored.github
            slack = stored.slack
            linear = stored.linear
        } else {
            // One-time migration from the former one-item-per-service layout.
            github = Keychain.load(GitHubCredentials.self, for: "github")
            slack = Keychain.load(SlackCredentials.self, for: "slack.oauth")
            linear = Keychain.load(LinearCredentials.self, for: "linear.oauth")
            saveCredentials()
            ["github", "slack.oauth", "linear.oauth", "slack", "linear"].forEach(Keychain.delete)
        }
        if let data = try? Data(contentsOf: projectsURL),
           let list = try? JSONDecoder().decode([Project].self, from: data) {
            projects = list
        }
    }

    func isConnected(_ s: ServiceKind) -> Bool {
        switch s {
        case .slack: slack != nil
        case .linear: linear != nil
        case .github: github != nil
        }
    }

    // MARK: Clients

    func githubClient() throws -> GitHubClient {
        guard let github else { throw AppError.notConnected(.github) }
        return GitHubClient(token: github.token)
    }

    func withSlack<T>(_ body: (SlackClient) async throws -> T) async throws -> T {
        guard let slack else { throw AppError.notConnected(.slack) }
        return try await body(SlackClient(creds: slack))
    }

    /// One refresh at a time: Linear rotates the refresh token, so two concurrent
    /// refreshes would invalidate the session.
    private var linearRefresh: Task<LinearCredentials, Error>?

    private func refreshedLinear(force: Bool) async throws -> LinearCredentials {
        guard let linear else { throw AppError.notConnected(.linear) }
        if !force && !linear.needsRefresh { return linear }
        if let linearRefresh { return try await linearRefresh.value }
        let task = Task { try await LinearAuth.refresh(linear) }
        linearRefresh = task
        defer { linearRefresh = nil }
        do {
            let fresh = try await task.value
            self.linear = fresh
            return fresh
        } catch AppError.unauthorized(.linear) {
            self.linear = nil
            throw AppError.unauthorized(.linear)
        }
    }

    func withLinear<T>(_ body: (LinearClient) async throws -> T) async throws -> T {
        let creds = try await refreshedLinear(force: false)
        do {
            return try await body(LinearClient(token: creds.accessToken))
        } catch AppError.unauthorized(.linear) {
            let fresh = try await refreshedLinear(force: true)
            return try await body(LinearClient(token: fresh.accessToken))
        }
    }

    func disconnect(_ s: ServiceKind) {
        switch s {
        case .github: github = nil
        case .slack: slack = nil
        case .linear: linear = nil
        }
    }

    // MARK: Projects

    func upsert(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
    }

    var linkedSlackIDs: Set<String> { Set(projects.compactMap { $0.slack?.id }) }
    var linkedLinearIDs: Set<String> { Set(projects.compactMap { $0.linear?.id }) }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: Persistence

    /// All tokens live in a single Keychain item, so macOS asks for access at most once.
    private struct StoredCredentials: Codable {
        var github: GitHubCredentials?
        var slack: SlackCredentials?
        var linear: LinearCredentials?
    }

    private static let credentialsKey = "credentials"

    private func saveCredentials() {
        try? Keychain.save(StoredCredentials(github: github, slack: slack, linear: linear), for: Self.credentialsKey)
    }

    private func saveProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: projectsURL, options: .atomic)
        }
    }
}
