import Network
import XCTest

class EchoTests: XCTestCase {
	static let host: NWEndpoint.Host = "localhost"
	static let port = NWEndpoint.Port(rawValue: .random(in: 1025 ..< .max))!
	static let server = Process()
	static let queue = DispatchQueue(label: "echo")

	override class func setUp() {
		super.setUp()

		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // EchoTests.swift
			.deletingLastPathComponent() // EchoTests
			.deletingLastPathComponent() // Tests

		server.currentDirectoryURL = directory
		server.executableURL = URL(fileURLWithPath: "/bin/sh")
		server.arguments = ["-c", "go run ./cmd/server -qlog -a \(host):\(port)"]
		server.environment = ProcessInfo.processInfo.environment

		do {
			try server.run()
		} catch {
			XCTFail("Failed to start QUIC server.")
		}

		// Give the server a chance to start up
		sleep(3)
	}

	override class func tearDown() {
		server.terminate()
		super.tearDown()
	}

	func testEcho() throws {
		let endpoint: NWEndpoint = .hostPort(host: Self.host, port: Self.port)
		let descriptor = try NWMultiplexGroup(to: endpoint)
		let options = NWProtocolQUIC.Options(alpn: ["echo"])

		let allowInsecure = true
		sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, sec_trust, sec_protocol_verify_complete in
			let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
			var error: CFError?
			if SecTrustEvaluateWithError(trust, &error) {
				sec_protocol_verify_complete(true)
			} else {
				if allowInsecure == true {
					sec_protocol_verify_complete(true)
				} else {
					sec_protocol_verify_complete(false)
				}
			}
		}, Self.queue)

		let parameters = NWParameters(quic: options)
		let group = NWConnectionGroup(with: descriptor, using: parameters)

		let payloadReceived = expectation(description: "payload received")
		group.setReceiveHandler { _, content, _ in
			if let content = content {
				print("Received datagram: \(content)")
				payloadReceived.fulfill()
			}
		}

		let groupReady = expectation(description: "NWConnectionGroup ready")
		group.stateUpdateHandler = { newState in
			print("Connection: \(newState)")
			if newState == .ready {
				groupReady.fulfill()
			}
		}

		group.start(queue: Self.queue)

		wait(for: [groupReady], timeout: 1)

		// For some reason, this always fails, despite it being in the WWDC QUIC example:
		// https://developer.apple.com/videos/play/wwdc2021/10094/?time=907
		// let connection = NWConnection(from: group)!

//		let connection = NWConnection(to: endpoint, using: parameters)
//		connection.stateUpdateHandler = { newState in
//			switch newState {
//			case .ready:
//				print("Connected using QUIC!")
//			default:
//				print("stateUpdateHandler: \(newState)")
//			}
//		}
//		connection.start(queue: Self.queue)

		let payload = "Hello QUIC!"

		let payloadSent = expectation(description: "payload sent")
		group.send(content: payload.data(using: .utf8)!, to: endpoint) { error in
			if let error = error {
				print("Error: group.send: \(error)")
			} else {
				print("Sent payload: \(payload)")
				payloadSent.fulfill()
			}
		}

		wait(for: [payloadSent], timeout: 1)

		wait(for: [payloadReceived], timeout: 1)
	}
}
