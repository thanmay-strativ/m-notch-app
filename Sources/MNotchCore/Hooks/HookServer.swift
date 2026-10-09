import Foundation
import Network
import os

/// Answers one held hook request. The app replies once, or the peer goes away first.
public protocol HookResponder: AnyObject, Sendable {
    var id: UUID { get }
    func reply(_ body: Data?)
}

/// A held HTTP connection, confined to the server queue.
final class ConnectionResponder: HookResponder, @unchecked Sendable {
    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onPeerClosed: @Sendable (UUID) -> Void
    private var isFinished = false

    init(connection: NWConnection, queue: DispatchQueue, onPeerClosed: @escaping @Sendable (UUID) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onPeerClosed = onPeerClosed
    }

    func reply(_ body: Data?) {
        queue.async { [self] in
            guard !isFinished else { return }
            isFinished = true
            let response = HTTPMessage.response(status: 200, body: body ?? Data())
            connection.send(content: response, completion: .contentProcessed { [connection] _ in connection.cancel() })
        }
    }

    func peerClosed() {
        guard !isFinished else { return }
        isFinished = true
        connection.cancel()
        onPeerClosed(id)
    }
}

/// Local HTTP endpoint for Claude Code http hooks and the Codex curl hook.
public final class HookServer: @unchecked Sendable {
    public enum Status: Sendable, Equatable {
        case starting
        case ready(port: UInt16)
        case failed(String)
    }

    public static let defaultPort: UInt16 = 47823
    static let claudePath = "/m_notch/claude"
    static let claudeQuestionPath = "/m_notch/claude/ask"
    static let codexPath = "/m_notch/codex"
    static let statusLinePath = StatusLineRelay.path
    static let shellPath = ShellHook.path

    private let logger = Logger(subsystem: "local.mnotch", category: "hooks")
    private let queue = DispatchQueue(label: "local.mnotch.hookserver")
    private let requestedPort: UInt16
    private let token: String
    private let onEvent: @Sendable (HookEvent, HookResponder?) -> Void
    private let onStatusLine: @Sendable (StatusLineInfo) -> Void
    private let onShellCommand: @Sendable (FinishedCommand) -> Void
    private let onPeerClosed: @Sendable (UUID) -> Void
    private let onStatus: @Sendable (Status) -> Void
    private var listener: NWListener?

    public init(port: UInt16, token: String,
                onEvent: @escaping @Sendable (HookEvent, HookResponder?) -> Void,
                onStatusLine: @escaping @Sendable (StatusLineInfo) -> Void = { _ in },
                onShellCommand: @escaping @Sendable (FinishedCommand) -> Void = { _ in },
                onPeerClosed: @escaping @Sendable (UUID) -> Void,
                onStatus: @escaping @Sendable (Status) -> Void) {
        self.requestedPort = port
        self.token = token
        self.onEvent = onEvent
        self.onStatusLine = onStatusLine
        self.onShellCommand = onShellCommand
        self.onPeerClosed = onPeerClosed
        self.onStatus = onStatus
    }

    public func start() {
        queue.async { [self] in
            onStatus(.starting)
            guard let port = NWEndpoint.Port(rawValue: requestedPort) else {
                onStatus(.failed("Port \(requestedPort) is not valid"))
                return
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            do {
                let listener = try NWListener(using: parameters)
                listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                logger.error("Hook server could not listen on port \(self.requestedPort, privacy: .public): \(error.localizedDescription, privacy: .public)")
                onStatus(.failed("Port \(requestedPort): \(error.localizedDescription)"))
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue ?? requestedPort
            logger.info("Hook server listening on 127.0.0.1:\(port, privacy: .public)")
            onStatus(.ready(port: port))
        case .failed(let error):
            logger.error("Hook server on port \(self.requestedPort, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(.failed("Port \(requestedPort) is used by another app (\(error.localizedDescription))"))
            listener?.cancel()
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPMessage.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            case .complete(let request):
                self.route(request, on: connection)
            case .invalid(let reason):
                self.logger.warning("Rejected malformed hook request: \(reason, privacy: .public)")
                self.respond(status: 400, on: connection)
            case .tooLarge(let size):
                self.logger.warning("Rejected hook request body of \(size, privacy: .public) bytes")
                self.respond(status: 413, on: connection)
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.method == "POST" else {
            logger.warning("Rejected hook request with method \(request.method, privacy: .public) on \(request.path, privacy: .public)")
            return respond(status: 405, on: connection)
        }
        guard request.headers["origin"] == nil else {
            logger.warning("Rejected hook request from browser origin \(request.headers["origin"] ?? "", privacy: .public)")
            return respond(status: 403, on: connection)
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            logger.warning("Rejected hook request on \(request.path, privacy: .public) with a missing or wrong token")
            return respond(status: 401, on: connection)
        }
        if request.path == Self.statusLinePath {
            respond(status: 200, on: connection)
            if let body = JSONValue.decode(request.body) { onStatusLine(StatusLineInfo(body: body)) }
            return
        }
        if request.path == Self.shellPath {
            guard let command = FinishedCommand(formBody: request.body, finishedAt: Date()) else {
                logger.warning("Rejected terminal hook body: \(request.body.count, privacy: .public) bytes without command, exit or seconds")
                return respond(status: 400, on: connection)
            }
            respond(status: 200, on: connection)
            onShellCommand(command)
            return
        }
        let agent: AgentKind
        let isQuestionHook: Bool
        switch request.path {
        case Self.claudePath: (agent, isQuestionHook) = (.claude, false)
        case Self.claudeQuestionPath: (agent, isQuestionHook) = (.claude, true)
        case Self.codexPath: (agent, isQuestionHook) = (.codex, false)
        default:
            logger.warning("Rejected hook request on unknown path \(request.path, privacy: .public)")
            return respond(status: 404, on: connection)
        }
        guard let body = JSONValue.decode(request.body),
              let event = HookEvent(agent: agent, body: body, hints: HostHints(headers: request.headers),
                                    isQuestionHook: isQuestionHook) else {
            logger.warning("Rejected hook body on \(request.path, privacy: .public): \(request.body.count, privacy: .public) bytes without hook_event_name or session_id")
            return respond(status: 400, on: connection)
        }
        guard event.holdsConnection else {
            respond(status: 200, on: connection)
            onEvent(event, nil)
            return
        }
        let responder = ConnectionResponder(connection: connection, queue: queue, onPeerClosed: onPeerClosed)
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: responder.peerClosed()
            default: break
            }
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil { responder.peerClosed() }
        }
        onEvent(event, responder)
    }

    private func respond(status: Int, on connection: NWConnection) {
        connection.send(content: HTTPMessage.response(status: status),
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
