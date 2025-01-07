// swift-tools-version: 5.9
// This is a Skip (https://skip.tools) package,
// containing a Swift Package Manager project
// that will use the Skip build plugin to transpile the
// Swift Package, Sources, and Tests into an
// Android Gradle Project with Kotlin sources and JUnit tests.
import PackageDescription

let package = Package(
    name: "skipapp-notes",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(name: "SkipNotesApp", type: .dynamic, targets: ["SkipNotes"]),
        .library(name: "SkipNotesModel", type: .dynamic, targets: ["SkipNotesModel"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.2.0"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-keychain.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/swift-sqlcipher.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SkipNotes", dependencies: [
            "SkipNotesModel",
            .product(name: "SkipUI", package: "skip-ui")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipNotesTests", dependencies: [
            "SkipNotes",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "SkipNotesModel", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipFuse", package: "skip-fuse"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SQLiteDB", package: "swift-sqlcipher"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipNotesModelTests", dependencies: [
            "SkipNotesModel",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
