import Foundation
import Observation
import os

/// All live agent sessions, the queue of requests waiting for the user, and the last long terminal command.
@MainActor
@Observable
public final class SessionStore {
    public static let requestLifetime: TimeInterval = 290
    public static let nudgeAfter: TimeInterval = 120
    static let doneRetention: TimeInterval = 30 * 60
    static let staleRetention: TimeInterval = 2 * 60 * 60
    static let contextThrottle: TimeInterval = 5
    static let busyWindow: TimeInterval = 30 * 60
    static let maxDiffsPerSession = 20
    static let finishedCommandRetention: TimeInterval = 10 * 60

    public private(set) var sessions: [String: Session] = [:]
    public private(set) var pending: [PendingRequest] = []
    public private(set) var lastEventAt: Date?
    public private(set) var planUsage: PlanUsage?
    public private(set) var finishedCommand: FinishedCommand?

    @ObservationIgnored public var onSignal: ((StoreSignal) -> Void)?
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var resolveHost: (String, HostHints) -> (HostApp, ProjectRoot.Result) = {
        ProjectRoot.resolve(cwd: $0, hints: $1)
    }
    @ObservationIgnored var readContext: (String) -> ContextReading? = { ContextMeter.read(transcriptPath: $0) }
    @ObservationIgnored var countTools: (String) -> Int = { TranscriptStats.toolCount(transcriptPath: $0) }
    @ObservationIgnored var transcriptCreatedAt: (String) -> Date? = { TranscriptStats.createdAt(transcriptPath: $0) }
    @ObservationIgnored public var shouldHoldRequests: () -> Bool = { true }
    @ObservationIgnored private var responders: [UUID: HookResponder] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "local.mnotch", category: "sessions")

    public init() {}

    public var sortedSessions: [Session] {
        sessions.values.sorted {
            $0.state.sortRank != $1.state.sortRank ? $0.state.sortRank < $1.state.sortRank : $0.lastChange > $1.lastChange
        }
    }

    /// ponytail: a session silent for 30 min counts as idle (crashed agent, or one very long tool call); raise if long builds sleep the Mac.
    public var isAnySessionBusy: Bool {
        let current = now()
        return sessions.values.contains { $0.isBusy && current.timeIntervalSince($0.lastChange) < Self.busyWindow }
    }

    public func session(for request: PendingRequest) -> Session? { sessions[request.sessionId] }

    public func handle(_ event: HookEvent, responder: HookResponder?) {
        lastEventAt = now()
        upsertSession(for: event)
        switch event.name {
        case "UserPromptSubmit":
            update(event.sessionId) { $0.state = .thinking; $0.stepText = "Thinking"; $0.finishedLine = ""; $0.waitingNudged = false }
            dismissRequests(inSession: event.sessionId)
            onSignal?(.activity(sessionId: event.sessionId))
        case "PreToolUse":
            handlePreToolUse(event, responder: responder)
        case "PostToolUse":
            handlePostToolUse(event)
        case "Notification" where event.notificationType == "idle_prompt":
            update(event.sessionId) { $0.state = .needsYou; $0.waitingNudged = false }
            onSignal?(.activity(sessionId: event.sessionId))
        case "Stop":
            update(event.sessionId) {
                $0.state = .done
                $0.stepText = ""
                $0.finishedLine = Self.firstLine(of: event.lastAssistantMessage ?? "")
            }
            refreshContext(event.sessionId, force: true)
            dismissRequests(inSession: event.sessionId)
            onSignal?(.finished(sessionId: event.sessionId))
        case "SessionEnd":
            dismissRequests(inSession: event.sessionId)
            sessions[event.sessionId] = nil
        case "PermissionRequest":
            enqueue(event, responder: responder)
        default:
            break
        }
    }

    public func handleStatusLine(_ info: StatusLineInfo) {
        if let plan = info.plan, plan != planUsage { planUsage = plan }
        guard let sessionId = info.sessionId.flatMap({ sessions[$0] == nil ? nil : $0 })
                ?? sessions.values.first(where: { $0.transcriptPath != nil && $0.transcriptPath == info.transcriptPath })?.id,
              var session = sessions[sessionId] else { return }
        let before = session
        session.modelName = info.modelName ?? session.modelName
        session.contextUsed = info.contextUsed ?? session.contextUsed
        session.contextWindow = info.contextWindow ?? session.contextWindow
        session.hasStatusLineStats = session.hasStatusLineStats || info.contextUsed != nil
        if session != before { sessions[sessionId] = session }
    }

    public func decide(_ requestId: UUID, _ decision: PermissionDecision) {
        guard let request = pending.first(where: { $0.id == requestId }) else {
            logger.warning("Decision for request \(requestId, privacy: .public) ignored: it is no longer pending")
            return
        }
        let suggestions: JSONValue? = decision == .always && request.canAlwaysAllow ? request.suggestions : nil
        let effectiveDecision: PermissionDecision = decision == .always && !request.canAlwaysAllow ? .allow : decision
        finish(requestId, reply: HookReply.permission(effectiveDecision, suggestions: suggestions))
        update(request.sessionId) { $0.state = .working }
        logger.info("Request \(requestId, privacy: .public) for tool \(request.toolName, privacy: .public) answered: \(String(describing: effectiveDecision), privacy: .public)")
    }

    public func answer(_ requestId: UUID, selections: [[String]]) {
        guard let request = pending.first(where: { $0.id == requestId }),
              case .question(let question) = request.kind,
              let rawQuestions = request.toolInput?["questions"] else {
            logger.warning("Answer for request \(requestId, privacy: .public) ignored: no pending question with that id")
            return
        }
        let answers = AskQuestion.buildAnswers(questions: question.questions, selections: selections)
        finish(requestId, reply: HookReply.answers(questions: rawQuestions, answers: answers))
        update(request.sessionId) { $0.state = .working }
    }

    public func replyInTerminal(_ requestId: UUID) {
        finish(requestId, reply: nil)
    }

    public func peerClosed(_ requestId: UUID) {
        guard pending.contains(where: { $0.id == requestId }) else { return }
        logger.info("Request \(requestId, privacy: .public) closed by the agent, answered elsewhere")
        removeRequest(requestId)
    }

    public func handleFinishedCommand(_ command: FinishedCommand) {
        logger.info("Terminal command in \(command.folder, privacy: .public) ended with exit \(command.exitCode, privacy: .public) after \(command.seconds, privacy: .public) s")
        finishedCommand = command
        onSignal?(.commandFinished)
    }

    public func dismissFinishedCommand() { finishedCommand = nil }

    public func tick() {
        let current = now()
        if let finishedCommand, current.timeIntervalSince(finishedCommand.finishedAt) > Self.finishedCommandRetention {
            self.finishedCommand = nil
        }
        for request in pending where current.timeIntervalSince(request.createdAt) > Self.requestLifetime {
            logger.info("Request \(request.id, privacy: .public) for tool \(request.toolName, privacy: .public) timed out after \(Int(Self.requestLifetime), privacy: .public) s")
            finish(request.id, reply: nil)
        }
        for (sessionId, session) in sessions {
            let idle = current.timeIntervalSince(session.lastChange)
            if (session.state == .done && idle > Self.doneRetention) || idle > Self.staleRetention {
                sessions[sessionId] = nil
            }
        }
        nudgeIfWaiting(at: current)
    }

    private func nudgeIfWaiting(at current: Date) {
        var shouldNudge = false
        for index in pending.indices where !pending[index].nudged
            && current.timeIntervalSince(pending[index].createdAt) > Self.nudgeAfter {
            pending[index].nudged = true
            shouldNudge = true
        }
        for (sessionId, session) in sessions where session.state == .needsYou && !session.waitingNudged
            && current.timeIntervalSince(session.lastChange) > Self.nudgeAfter {
            sessions[sessionId]?.waitingNudged = true
            shouldNudge = true
        }
        if shouldNudge { onSignal?(.nudge) }
    }

    private func handlePreToolUse(_ event: HookEvent, responder: HookResponder?) {
        guard event.toolName != "AskUserQuestion" else {
            if event.isQuestionHook {
                enqueue(event, responder: responder)
            } else {
                update(event.sessionId) { $0.toolCount += 1 }
            }
            return
        }
        update(event.sessionId) { $0.state = .working; $0.stepText = event.stepText; $0.toolCount += 1 }
        onSignal?(.activity(sessionId: event.sessionId))
    }

    private func handlePostToolUse(_ event: HookEvent) {
        let inputKey = event.toolInput?.canonicalString ?? ""
        let matching = pending.filter {
            $0.sessionId == event.sessionId && $0.toolName == event.toolName && $0.inputKey == inputKey
        }
        for request in matching { finish(request.id, reply: nil) }
        if let diff = LineDiff.make(toolName: event.toolName, toolInput: event.toolInput, toolResponse: event.toolResponse) {
            update(event.sessionId) {
                $0.diffs.append(diff)
                if $0.diffs.count > Self.maxDiffsPerSession { $0.diffs.removeFirst($0.diffs.count - Self.maxDiffsPerSession) }
                $0.stepText = "\(diff.fileName) +\(diff.added) -\(diff.removed)"
            }
        }
        refreshContext(event.sessionId, force: false)
    }

    private func enqueue(_ event: HookEvent, responder: HookResponder?) {
        guard let responder, let session = sessions[event.sessionId] else {
            logger.error("Held event \(event.name, privacy: .public) for session \(event.sessionId, privacy: .public) arrived without a connection")
            return
        }
        guard shouldHoldRequests() else {
            responder.reply(nil)
            return
        }
        let toolName = event.toolName ?? "Unknown tool"
        let kind: PendingKind
        if toolName == "AskUserQuestion", let question = AskQuestion.parse(toolInput: event.toolInput) {
            kind = .question(question)
        } else if toolName == "AskUserQuestion" {
            logger.warning("AskUserQuestion in session \(event.sessionId, privacy: .public) has an unexpected shape, left to the terminal")
            responder.reply(nil)
            return
        } else if toolName == "ExitPlanMode" {
            kind = .plan(event.toolInput?["plan"]?.stringValue ?? "")
        } else {
            kind = .permission
        }
        let request = PendingRequest(
            id: responder.id, sessionId: event.sessionId, agent: event.agent, toolName: toolName,
            toolInput: event.toolInput, inputKey: event.toolInput?.canonicalString ?? "",
            summary: PendingRequest.summary(toolName: toolName, toolInput: event.toolInput),
            suggestions: event.permissionSuggestions,
            risk: kind == .permission
                ? RiskGuard.assess(toolName: toolName, toolInput: event.toolInput, projectRoot: session.projectRoot)
                : nil,
            kind: kind, createdAt: now())
        responders[request.id] = responder
        pending.append(request)
        update(event.sessionId) { $0.state = .needsYou; $0.waitingNudged = false }
        onSignal?(.requestsChanged)
    }

    private func finish(_ requestId: UUID, reply: Data?) {
        responders[requestId]?.reply(reply)
        removeRequest(requestId)
    }

    private func removeRequest(_ requestId: UUID) {
        responders[requestId] = nil
        guard let index = pending.firstIndex(where: { $0.id == requestId }) else { return }
        let sessionId = pending[index].sessionId
        pending.remove(at: index)
        if !pending.contains(where: { $0.sessionId == sessionId }), sessions[sessionId]?.state == .needsYou {
            update(sessionId) { $0.state = .working }
        }
        onSignal?(.requestsChanged)
    }

    private func dismissRequests(inSession sessionId: String) {
        for request in pending where request.sessionId == sessionId {
            finish(request.id, reply: nil)
        }
    }

    private func upsertSession(for event: HookEvent) {
        if var existing = sessions[event.sessionId] {
            existing.lastChange = now()
            if let path = event.transcriptPath { existing.transcriptPath = path }
            sessions[event.sessionId] = existing
            return
        }
        let (host, root) = resolveHost(event.cwd, event.hints)
        var session = Session(
            id: event.sessionId, agent: event.agent,
            name: URL(fileURLWithPath: root.path).lastPathComponent,
            cwd: event.cwd, projectRoot: root.path, host: host,
            lastChange: now(), transcriptPath: event.transcriptPath,
            startedAt: event.transcriptPath.flatMap(transcriptCreatedAt) ?? now())
        if let path = event.transcriptPath {
            session.toolCount = countTools(path)
            if let reading = readContext(path) {
                session.contextUsed = reading.usedTokens
                session.contextWindow = reading.window
                session.modelName = reading.modelId.map(StatsFormat.modelName(fromId:))
            }
        }
        sessions[event.sessionId] = session
        logger.info("New \(event.agent.rawValue, privacy: .public) session \(event.sessionId, privacy: .public) in \(root.path, privacy: .public) on \(host.displayName, privacy: .public)")
    }

    private func update(_ sessionId: String, _ change: (inout Session) -> Void) {
        guard var session = sessions[sessionId] else { return }
        change(&session)
        session.lastChange = now()
        sessions[sessionId] = session
    }

    private func refreshContext(_ sessionId: String, force: Bool) {
        guard let session = sessions[sessionId], session.agent == .claude, !session.hasStatusLineStats,
              let path = session.transcriptPath else { return }
        if !force, let checked = session.contextCheckedAt, now().timeIntervalSince(checked) < Self.contextThrottle { return }
        let reading = readContext(path)
        sessions[sessionId]?.contextUsed = reading?.usedTokens
        sessions[sessionId]?.contextWindow = reading?.window
        if let modelId = reading?.modelId { sessions[sessionId]?.modelName = StatsFormat.modelName(fromId: modelId) }
        sessions[sessionId]?.contextCheckedAt = now()
    }

    static func firstLine(of message: String) -> String {
        let line = message.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_` "))
    }
}
