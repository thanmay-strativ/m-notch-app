import Foundation
import Testing
@testable import MNotchCore

final class ServerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [HookServer.Status] = []
    private var responders: [HookResponder] = []
    private var events: [HookEvent] = []
    private var finishedCommands: [FinishedCommand] = []

    func record(_ status: HookServer.Status) { lock.withLock { statuses.append(status) } }
    func record(_ command: FinishedCommand) { lock.withLock { finishedCommands.append(command) } }
    func record(_ event: HookEvent, _ responder: HookResponder?) {
        lock.withLock {
            events.append(event)
            if let responder { responders.append(responder) }
        }
    }

    var readyPort: UInt16? {
        lock.withLock {
            statuses.lazy.compactMap { if case .ready(let port) = $0 { return port } else { return nil } }.first
        }
    }
    var firstResponder: HookResponder? { lock.withLock { responders.first } }
    var eventNames: [String] { lock.withLock { events.map(\.name) } }
    var commandLines: [String] { lock.withLock { finishedCommands.map(\.command) } }
}

@Suite(.serialized)
struct HookServerTests {
    private func startServer() async throws -> (HookServer, ServerProbe, UInt16) {
        let probe = ServerProbe()
        let server = HookServer(port: 0, token: "secret",
                                onEvent: { probe.record($0, $1) },
                                onShellCommand: { probe.record($0) },
                                onPeerClosed: { _ in },
                                onStatus: { probe.record($0) })
        server.start()
        for _ in 0..<100 where probe.readyPort == nil { try await Task.sleep(for: .milliseconds(20)) }
        let port = try #require(probe.readyPort)
        return (server, probe, port)
    }

    private func post(port: UInt16, path: String = "/m_notch/claude", token: String? = "secret",
                      origin: String? = nil, body: String) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    private let promptBody = #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp"}"#

    @Test func rejectsMissingTokenAndBrowserOrigins() async throws {
        let (server, probe, port) = try await startServer()
        defer { server.stop() }
        #expect(try await post(port: port, token: nil, body: promptBody).0 == 401)
        #expect(try await post(port: port, token: "wrong", body: promptBody).0 == 401)
        #expect(try await post(port: port, origin: "https://evil.example", body: promptBody).0 == 403)
        #expect(try await post(port: port, path: "/other", body: promptBody).0 == 404)
        #expect(try await post(port: port, body: #"{"no":"event"}"#).0 == 400)
        #expect(probe.eventNames.isEmpty)
    }

    @Test func ordinaryEventsAreAcknowledgedRightAway() async throws {
        let (server, probe, port) = try await startServer()
        defer { server.stop() }
        let (status, body) = try await post(port: port, body: promptBody)
        #expect(status == 200)
        #expect(body.isEmpty)
        #expect(probe.eventNames == ["UserPromptSubmit"])
    }

    @Test func terminalHookReportsReachTheApp() async throws {
        let (server, probe, port) = try await startServer()
        defer { server.stop() }
        let body = "command=npm%20test&exit=1&seconds=42&cwd=%2Fwork%2Fweb-app"
        #expect(try await post(port: port, path: "/m_notch/shell", token: nil, body: body).0 == 401)
        #expect(try await post(port: port, path: "/m_notch/shell", body: "exit=0&seconds=42").0 == 400)
        #expect(try await post(port: port, path: "/m_notch/shell", body: body).0 == 200)
        for _ in 0..<50 where probe.commandLines.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(probe.commandLines == ["npm test"])
    }

    @Test func permissionRequestWaitsForTheAppsReply() async throws {
        let (server, probe, port) = try await startServer()
        defer { server.stop() }
        let body = #"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}"#
        async let result = post(port: port, body: body)
        for _ in 0..<100 where probe.firstResponder == nil { try await Task.sleep(for: .milliseconds(20)) }
        let responder = try #require(probe.firstResponder)
        responder.reply(HookReply.permission(.allow, suggestions: nil))
        let (status, reply) = try await result
        #expect(status == 200)
        #expect(reply.contains(#""behavior":"allow""#))
    }
}
