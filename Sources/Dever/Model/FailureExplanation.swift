import Foundation

// Why a pipeline failed (docs/on-device-ai.md, 5.6): the failed job's name and step as GitHub
// gives them, and one generated sentence from the end of its log. What the model is known to
// get wrong is settled in code: which part of the log it reads, whether that part states an
// error at all, and whether the line it says it rests on is really in the log.

/// The end of a job's log, as GitHub Actions writes it, cut down to the step that failed.
enum PipelineLog {
    /// Bytes read from the end of a log, at most: the failing step's last output and the
    /// clean-up after it fit many times over.
    static let tailBytes = 64_000

    /// What the failed step ran and what it printed last.
    struct Excerpt: Equatable, Sendable {
        /// The step's command, from its "Run …" header; nil when the tail does not reach it.
        var command: String?
        /// The step's output, oldest first, without the runner's own lines.
        var output: [String]
        /// What the runner said the step failed on ("Process completed with exit code 1.").
        var errors: [String]
    }

    /// The log's lines without what the runner adds: the time at the head of each line, colour
    /// codes, a first line cut in two by the byte range.
    static func lines(_ data: Data, cut: Bool) -> [String] {
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        if cut, !lines.isEmpty { lines.removeFirst() }
        return lines.map { line in
            line.replacingOccurrences(of: "\u{FEFF}", with: "")
                .replacingOccurrences(of: #"^\d{4}-\d\d-\d\dT[\d:.]+Z ?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        }
    }

    private static let error = "##[error]"

    /// The step that failed: the last error the runner reports before its clean-up, the command
    /// of the step it closes, and that step's output. Nil when the runner reports no error in
    /// what was read.
    static func excerpt(_ lines: [String]) -> Excerpt? {
        let end = lines.firstIndex { $0.hasPrefix("Post job cleanup.") } ?? lines.count
        guard let last = lines[..<end].lastIndex(where: { $0.hasPrefix(error) }) else { return nil }
        var first = last
        while first > 0, lines[first - 1].hasPrefix(error) { first -= 1 }
        let errors = lines[first...last].map { String($0.dropFirst(error.count)) }

        var command: String?
        var start = 0
        if let header = lines[..<first].lastIndex(where: { $0.hasPrefix("##[group]Run ") }) {
            command = String(lines[header].dropFirst("##[group]Run ".count)).trimmingCharacters(in: .whitespaces)
            // The header lists the script, the shell and the environment, then closes.
            start = lines[header..<first].firstIndex { $0.hasPrefix("##[endgroup]") }.map { $0 + 1 } ?? header + 1
        }
        let output = lines[start..<first]
            .filter { !$0.hasPrefix("##[") && !$0.hasPrefix("[command]") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Excerpt(command: command?.isEmpty == true ? nil : command, output: output, errors: errors)
    }

    /// The runner's own last word, which says that the step failed and never why.
    static func isExitCode(_ line: String) -> Bool {
        line.range(of: #"^(Error: )?Process completed with exit code \d+\.?$"#, options: .regularExpression) != nil
    }

    private static let failureWords = try! NSRegularExpression(
        pattern: #"\berr(or)?\b|\bfail(ed|ure|ures|ing)?\b|exception|\bfatal\b|\bpanic|traceback|\bnot ok\b|✗|✘|\bcannot\b|\bcan't\b|could not|couldn't|unable to|denied|not found|no such|timed? ?out|exceeded|cancel+ed|\bkilled\b|\babort|unexpected|undefined|unresolved|\bmissing\b|\binvalid\b|✖|(?-i:\bE[A-Z]{4,}\b)"#,
        options: [.caseInsensitive])

    /// A warning or a deprecation notice that reports no error.
    static func isWarning(_ line: String) -> Bool {
        line.range(of: #"\bwarn(ing)?\b|deprecat"#, options: [.regularExpression, .caseInsensitive]) != nil
            && line.range(of: #"\berror\b|\bfail"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// A line that reports something going wrong, in the words tools use for it.
    static func reportsFailure(_ line: String) -> Bool {
        guard !isExitCode(line), !isWarning(line) else { return false }
        // "0 errors", "no failures", "0 failed": a count of none is a success.
        let plain = line.replacingOccurrences(of: #"\b(0|no) (errors?|failures?|failed|warnings?)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        return failureWords.firstMatch(in: plain, range: NSRange(plain.startIndex..., in: plain)) != nil
    }

    /// The excerpt holds a line that says what went wrong. Without one (a step that prints its
    /// progress, then exits 1) there is nothing to explain, and the model is not asked: it
    /// invents a cause when given none.
    static func statesAnError(_ excerpt: Excerpt) -> Bool {
        excerpt.errors.contains { !isExitCode($0) } || excerpt.output.contains(where: reportsFailure)
    }
}

/// What the model says of a failed step.
struct FailureAnswer: Equatable, Sendable {
    /// The log states the error that made the step fail.
    var stated: Bool
    /// The line of the log that states it, copied.
    var line: String
    /// What failed and why, in one sentence.
    var sentence: String
}

enum FailureExplanation {
    /// The longest sentence shown; a longer one is cut at its last whole sentence or dropped.
    static let longest = 220
    /// Lines of the step's output given to the model, at most, from the end.
    static let longestOutput = 60
    /// A line of log longer than this is cut: minified code, a base64 blob.
    static let longestLine = 300

    static let instructions = """
        You read the end of the log of one failed step of a continuous integration job, and you say why the step failed.
        First decide whether the log states the error that made the step fail: a line that reports a failed test, a compiler or type error, a command that cannot run, a network failure, a time limit that was passed, or the like. A step that only stops with an exit code, with no line that says what went wrong, does not state it. Warnings and deprecation notices are not the error. A line that reports a success is not the error.
        When the log states the error: copy the one line of the log that states it, exactly as it is written, then say in one sentence of at most 25 words what went wrong, in plain English, using the words of that line. The reader already sees the name of the job and of the step: say only what went wrong, and do not say which step, build or run failed. Name a file, a test or a package only as the log writes it. Use only what the log shows. Do not guess a cause the log does not state, and do not propose a fix.
        When the log does not state the error: leave the line and the sentence empty.
        """

    /// What the model reads: the job and the step as GitHub names them, the command, then the
    /// newest output lines that fit `room` tokens, then the runner's errors.
    static func prompt(job: String, step: String?, excerpt: PipelineLog.Excerpt, room: Int, cost: (String) async -> Int) async -> String? {
        var head = "Job: \(job)\n"
        if let step { head += "Step: \(step)\n" }
        if let command = excerpt.command { head += "Command: \(String(command.prefix(longestLine)))\n" }
        let tail = excerpt.errors.map { "Error: \(String($0.prefix(longestLine)))" }.joined(separator: "\n")
        let output = excerpt.output.suffix(longestOutput).map { String($0.prefix(longestLine)) }
        var costs: [Int] = []
        for line in output { costs.append(await cost(line) + 1) }
        let fixed = await cost(head + "Log:\n" + tail)
        guard let kept = TextBudget.newestThatFit(Array(output), costs: costs, room: room - fixed) else { return nil }
        return head + "Log:\n" + (kept + [tail]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The words of a line, for comparing what the model copied with what the log holds: the
    /// model tidies as it copies (an escaped character decoded, a space dropped).
    private static func words(_ s: String) -> [String] {
        (s.removingPercentEncoding ?? s).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// `line` is a line of the log, or all but a word in five of one.
    static func isInLog(_ line: String, excerpt: PipelineLog.Excerpt) -> Bool {
        let copied = words(line)
        guard copied.count >= 2 else { return false }
        return (excerpt.output + excerpt.errors).contains { candidate in
            let held = Set(words(candidate))
            return copied.filter(held.contains).count * 5 >= copied.count * 4
        }
    }

    /// The sentence to show, or nil when the answer cannot be trusted: the model says the log
    /// does not state the error, or the line it rests on is not in the log, or it is the
    /// runner's exit code, or there is no sentence.
    static func sentence(from answer: FailureAnswer, excerpt: PipelineLog.Excerpt) -> String? {
        guard answer.stated else { return nil }
        let line = answer.line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !PipelineLog.isExitCode(line), isInLog(line, excerpt: excerpt) else { return nil }
        // It pointed at a warning: that is not why the step failed.
        guard !PipelineLog.isWarning(line) else { return nil }
        let plain = answer.sentence.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "*", with: "")
            .split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "{}")))
        var kept = ""
        plain.enumerateSubstrings(in: plain.startIndex..., options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            if kept.count + sentence.count > longest + 1 { stop = true } else { kept += sentence }
        }
        kept = kept.trimmingCharacters(in: .whitespaces)
        guard kept.count > 12 else { return nil }
        return kept.prefix(1).uppercased() + kept.dropFirst()
    }

    /// One sentence on why the step failed, or nil when the log does not say. Asked ahead of
    /// what waits in the background: someone clicked.
    static func write(job: String, step: String?, excerpt: PipelineLog.Excerpt, with intelligence: Intelligence = .shared) async throws -> String? {
        guard PipelineLog.statesAnError(excerpt) else {
            MessageSummary.log.notice("failure: the log states no error, the model is not asked")
            return nil
        }
        return try await intelligence.perform(.onScreen) { model in
            let room = TextBudget.room(contextSize: model.contextSize, instructions: await model.tokenCount(instructions), reserve: 250)
            // Half the window at most: a log costs many tokens a line, and time with them.
            guard let prompt = await prompt(job: job, step: step, excerpt: excerpt, room: min(room, 1_600), cost: model.tokenCount) else {
                throw IntelligenceError.tooLong
            }
            let answer = try await model.explainFailure(instructions: instructions, prompt: prompt)
            let sentence = sentence(from: answer, excerpt: excerpt)
            MessageSummary.log.notice("failure: \(sentence == nil ? "silent" : "explained", privacy: .public), stated \(answer.stated), \(excerpt.output.count) lines of output")
            return sentence
        }
    }
}
