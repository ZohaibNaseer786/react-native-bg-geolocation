//
//  TSLocationPushSocketClient.swift
//
//  A minimal Socket.IO v4 (Engine.IO v4) client implemented directly on
//  URLSessionWebSocketTask. The Location Push Service Extension runs in a tiny,
//  RN-less Swift process, so it cannot load `socket.io-client` (a JS library).
//  This emits a single `location:update` event with an ack, matching the app's
//  JS socket protocol, then tears the connection down.
//
//  Protocol (Socket.IO v4 over a single WebSocket):
//    • Connect to  wss://<host><path>/?EIO=4&transport=websocket
//    • Server → "0{...}"            Engine.IO OPEN (we ignore the body)
//    • Client → "40{auth-json}"     Socket.IO CONNECT to namespace "/" with auth
//    • Server → "40{\"sid\":...}"   CONNECT ack (success) | "44{...}" connect_error
//    • Client → "420[\"event\",payload]"  MESSAGE + EVENT with ack id 0
//    • Server → "430[ackPayload]"   ack for id 0
//    • Engine.IO PING "2" → we reply PONG "3"
//
//  Everything is bounded by `timeout` so we never blow the extension budget.
//  Extension-safe: only Foundation + URLSession.
//

import Foundation

@available(iOS 15.0, *)
final class TSLocationPushSocketClient: NSObject {

    struct Config {
        let url: URL            // base, e.g. https://host  (ws/http both accepted)
        let path: String        // socket.io path, e.g. /socket/location
        let event: String       // event name, e.g. location:update
        let authToken: String?  // sent in the CONNECT auth payload as {"token": ...}
        let timeout: TimeInterval
    }

    private let config: Config
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var completion: ((Bool) -> Void)?
    private var didFinish = false
    private var connectAcked = false
    private var payload: [String: Any] = [:]
    private var timeoutWorkItem: DispatchWorkItem?

    init(config: Config) {
        self.config = config
    }

    /// Emit one event with `payload` and resolve `true` once the server acks it,
    /// or `false` on any failure / timeout.
    func emit(_ payload: [String: Any], completion: @escaping (Bool) -> Void) {
        self.payload = payload
        self.completion = completion

        guard let wsURL = makeWebSocketURL() else {
            finish(false)
            return
        }

        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let task = session.webSocketTask(with: wsURL)
        self.task = task

        let deadline = DispatchWorkItem { [weak self] in
            TSLocationPushLog.log("socket timed out")
            self?.finish(false)
        }
        timeoutWorkItem = deadline
        DispatchQueue.global().asyncAfter(deadline: .now() + config.timeout, execute: deadline)

        task.resume()
        receiveLoop()
    }

    // MARK: - URL

    private func makeWebSocketURL() -> URL? {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme {
        case "https", "wss": components.scheme = "wss"
        default: components.scheme = "ws"
        }
        // socket.io expects the engine.io handshake at <path>/ with these query items.
        var path = config.path
        if !path.hasPrefix("/") { path = "/" + path }
        if !path.hasSuffix("/") { path += "/" }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        return components.url
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self, !self.didFinish else { return }
            switch result {
            case .failure(let error):
                TSLocationPushLog.log("socket receive error: \(error.localizedDescription)")
                self.finish(false)
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                if !self.didFinish { self.receiveLoop() }
            }
        }
    }

    private func handle(_ text: String) {
        guard let first = text.first else { return }
        switch first {
        case "0": // Engine.IO OPEN → send Socket.IO CONNECT with auth
            sendConnect()
        case "2": // Engine.IO PING → PONG
            send("3")
        case "4": // Engine.IO MESSAGE → inspect Socket.IO packet type (2nd char)
            handleSocketIO(text)
        default:
            break
        }
    }

    private func handleSocketIO(_ text: String) {
        // text[0] == "4" (MESSAGE). text[1] == Socket.IO packet type.
        let idx = text.index(text.startIndex, offsetBy: 1)
        guard idx < text.endIndex else { return }
        let type = text[idx]
        switch type {
        case "0": // CONNECT success → now emit the event
            connectAcked = true
            sendEvent()
        case "3": // ACK for our emit → success
            TSLocationPushLog.log("socket ack received")
            finish(true)
        case "4": // CONNECT_ERROR
            TSLocationPushLog.log("socket connect_error: \(text)")
            finish(false)
        default:
            break
        }
    }

    // MARK: - Send

    private func sendConnect() {
        var frame = "40"
        if let token = config.authToken, !token.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: ["token": token]),
           let json = String(data: data, encoding: .utf8) {
            frame += json
        }
        send(frame)
    }

    private func sendEvent() {
        guard let data = try? JSONSerialization.data(withJSONObject: [config.event, payload]),
              let json = String(data: data, encoding: .utf8) else {
            finish(false)
            return
        }
        // "42" = MESSAGE+EVENT, "0" = ack id we expect echoed back as "430[...]".
        send("420" + json)
    }

    private func send(_ frame: String) {
        task?.send(.string(frame)) { [weak self] error in
            if let error = error {
                TSLocationPushLog.log("socket send error: \(error.localizedDescription)")
                self?.finish(false)
            }
        }
    }

    // MARK: - Teardown

    private func finish(_ success: Bool) {
        guard !didFinish else { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        let cb = completion
        completion = nil
        cb?(success)
    }
}
