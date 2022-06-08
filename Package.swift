// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "SwiftQUICDatagramExample",
	platforms: [
		.macOS("13"),
		.iOS("16"),
		.macCatalyst("16"),
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
