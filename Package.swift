// swift-tools-version:5.6
import PackageDescription

let package = Package(
	name: "SwiftQUICDatagramExample",
	platforms: [
		.macOS("12"),
		.iOS("15"),
		.macCatalyst("15"),
	],
	products: [
		.library(
			name: "Echo",
			targets: ["Echo"]
		),
	],
	dependencies: [
		// Dependencies declare other packages that this package depends on.
	],
	targets: [
		.target(
			name: "Echo"
		),
		.testTarget(
			name: "EchoTests",
			dependencies: ["Echo"]
		),
	]
)
