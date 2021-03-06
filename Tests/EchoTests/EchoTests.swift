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
		server.arguments = ["-c", "go run ./cmd/server -a \(host):\(port)"]
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
		let descriptor = NWMultiplexGroup(to: endpoint)
		let options = NWProtocolQUIC.Options(alpn: ["echo"])

		options.isDatagram = true
		options.maxDatagramFrameSize = 1220

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
		// group.setReceiveHandler(maximumMessageSize: 1220, rejectOversizedMessages: true) { _, content, _ in
		group.setReceiveHandler { _, content, _ in
			if let content = content {
				let str = String(decoding: content, as: UTF8.self)
				print("Received datagram: \(str)")
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

		// if let metadata = group.metadata(definition: NWProtocolQUIC.definition) as? NWProtocolQUIC.Metadata {
		// 	// Do something with metadata here
		// }

		wait(for: [groupReady], timeout: 1)

		let connection = NWConnection(from: group)!
		connection.stateUpdateHandler = { newState in
			switch newState {
			case .ready:
				print("New QUIC stream connected!")
			default:
				print("stateUpdateHandler: \(newState)")
			}
		}
		connection.start(queue: Self.queue)

		let payload = "Hello QUIC!"

		let payloadSent = expectation(description: "payload sent")
		group.send(content: payload.data(using: .utf8)!) { error in
			if let error = error {
				print("Error: group.send: \(error)")
			} else {
				print("Sent payload: \(payload)")
				payloadSent.fulfill()
			}
		}

		wait(for: [payloadSent], timeout: 1)

		wait(for: [payloadReceived], timeout: 2)
	}
}
