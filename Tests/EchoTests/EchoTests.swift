import Network
import XCTest

class PingTests: XCTestCase {
    static let host: NWEndpoint.Host = "localhost"
    static let port = NWEndpoint.Port(rawValue: .random(in: 1025 ..< .max))!
	static let server = Process()

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
		sleep(1)
	}

	override class func tearDown() {
		server.terminate()
		super.tearDown()
	}

	func testEcho() throws {
        let descriptor = try NWMultiplexGroup(to: .hostPort(host: Self.host, port: Self.port))
        let parameters = NWParameters(quic: .init(alpn: ["echo"]))
		let group = NWConnectionGroup(with: descriptor, using: parameters)

		let message = "Hello QUIC!"
	}
}
