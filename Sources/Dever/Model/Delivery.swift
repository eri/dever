import Foundation

/// Where each of a project's Linear issues stands on its way to production, joining
/// Linear's state with the GitHub pull requests linked to the issue. This is Dever's
/// own view: it shows the gap between code that shipped and tickets that say so.
struct Delivery: Equatable {
    var done = 0
    /// Merged pull request, but the ticket still says work is going on: it should move on.
    var merged = 0
    /// In a review or QA state in Linear, or with an open pull request.
    var review = 0
    /// Started in Linear, no pull request yet.
    var building = 0
    var todo = 0

    var total: Int { done + merged + review + building + todo }

    /// Issues whose code has landed: done, or with a merged pull request whatever their state.
    private(set) var shipped = 0

    enum Stage: CaseIterable {
        case done, merged, review, building, todo

        /// For a list: what needs a hand first, what is finished last.
        static let attentionOrder: [Stage] = [.merged, .review, .building, .todo, .done]

        var label: String {
            switch self {
            case .done: "Done"
            case .merged: "Merged, ticket not moved"
            case .review: "In review"
            case .building: "In progress"
            case .todo: "To do"
            }
        }
    }

    func count(_ stage: Stage) -> Int {
        switch stage {
        case .done: done
        case .merged: merged
        case .review: review
        case .building: building
        case .todo: todo
        }
    }

    /// Linear has no "review" state type: review and QA columns are "started" states,
    /// so they are recognised by name ("In Review", "QA", "To test", "Recette"…).
    static func isReviewState(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["review", "qa", "test", "validat", "verif", "recette", "staging", "approval"].contains { n.contains($0) }
    }

    /// Whether an issue with a merged pull request still sits in a state that says work is
    /// ongoing (not done, not in review): its ticket has fallen behind the code.
    static func isBehind(stateType: String, stateName: String, merged: Bool) -> Bool {
        merged && !["completed", "canceled"].contains(stateType) && !isReviewState(stateName)
    }

    /// The stage of one issue, joining its Linear state with its pull requests; nil when
    /// canceled. The counts and the rows of the project page both come from here, so
    /// they cannot disagree.
    static func stage(stateType: String, stateName: String, openPR: Bool, mergedPR: Bool) -> Stage? {
        switch stateType {
        case "canceled": nil
        case "completed": .done
        default:
            if isReviewState(stateName) { .review }
            else if mergedPR { .merged }
            else if openPR { .review }
            else if stateType == "started" { .building }
            else { .todo }
        }
    }

    /// - Parameters:
    ///   - issues: identifier, Linear state type and state name of each issue.
    ///   - openPR: identifiers with an open pull request.
    ///   - mergedPR: identifiers with a merged pull request.
    init(issues: [(identifier: String, stateType: String, stateName: String)], openPR: Set<String>, mergedPR: Set<String>) {
        for issue in issues {
            let hasMerged = mergedPR.contains(issue.identifier)
            guard let stage = Self.stage(stateType: issue.stateType, stateName: issue.stateName,
                                         openPR: openPR.contains(issue.identifier), mergedPR: hasMerged) else { continue }
            if stage == .done || hasMerged { shipped += 1 }
            switch stage {
            case .done: done += 1
            case .merged: merged += 1
            case .review: review += 1
            case .building: building += 1
            case .todo: todo += 1
            }
        }
    }

    init() {}
}
