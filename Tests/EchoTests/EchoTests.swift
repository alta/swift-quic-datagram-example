import CommonCrypto
// import CryptoKit
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
		if allowInsecure {
			sec_protocol_options_set_verify_block(
				options.securityProtocolOptions,
				{ _, trustRef, complete in
					let serverTrust: SecTrust = sec_trust_copy_ref(trustRef).takeRetainedValue()
					let certs = SecTrustCopyCertificateChain(serverTrust) as! [SecCertificate]
					let certificateCount = certs.count
					print("Number of certificates: \(certificateCount)")

					// let certs = SecTrustCopyCertificateChain(serverTrust)

					// https://medium.com/@gauravharkhani01/ssl-pinning-implementation-in-ios-a-beginners-guide-589d4efcdf42
					for (i, cert) in certs.enumerated() {
						guard let publicKey = SecCertificateCopyKey(cert)
						else {
							continue
						}
						print("Certificate \(i): \(cert)")

						if let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as? Data {
							let keyHash = sha256(keyData)
							print("Public key \(i): \(keyHash)")
							// if pinnedPublicKeyHashes.contains(keyHash) {
							// 	publicKeyFound = true
							// 	break
							// }
						}
					}

					complete(true)
				}, Self.queue)
		}

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

private func sha256(_ data: Data) -> String {
	var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
	data.withUnsafeBytes {
		_ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
	}
	return Data(hash).base64EncodedString()
}
