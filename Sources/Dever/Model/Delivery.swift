import Foundation

/// Where each of a project's Linear issues stands on its way to production, joining
/// Linear's state with the GitHub pull requests linked to the issue. This is Dever's
/// own view: it shows the gap between code that shipped and tickets that say so.
struct Delivery: Equatable {
    var done = 0
    /// Merged pull request, issue still open in Linear: the ticket needs closing.
    var merged = 0
    /// Open pull request.
    var review = 0
    /// Started in Linear, no pull request yet.
    var building = 0
    var todo = 0

    var total: Int { done + merged + review + building + todo }

    /// Issues whose code has landed, closed or not.
    var shipped: Int { done + merged }

    enum Stage: CaseIterable {
        case done, merged, review, building, todo

        var label: String {
            switch self {
            case .done: "Done"
            case .merged: "Merged, not closed"
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

    /// - Parameters:
    ///   - issues: identifier and Linear state type of each issue.
    ///   - openPR: identifiers with an open pull request.
    ///   - mergedPR: identifiers with a merged pull request.
    init(issues: [(identifier: String, stateType: String)], openPR: Set<String>, mergedPR: Set<String>) {
        for issue in issues {
            switch issue.stateType {
            case "canceled": continue
            case "completed": done += 1
            default:
                if mergedPR.contains(issue.identifier) { merged += 1 }
                else if openPR.contains(issue.identifier) { review += 1 }
                else if issue.stateType == "started" { building += 1 }
                else { todo += 1 }
            }
        }
    }

    init() {}
}
