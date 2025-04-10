// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "skipapp-notes",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(name: "SkipNotes", type: .dynamic, targets: ["SkipNotes"]),
        .library(name: "SkipNotesModel", type: .dynamic, targets: ["SkipNotesModel"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.4.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.2.13"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-keychain.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/swift-sqlcipher.git", from: "1.2.1"),
        .package(url: "https://source.skip.tools/skip-kit.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-device.git", "0.0.0"..<"2.0.0"),
        //.package(url: "https://source.skip.tools/skip-bluetooth.git", "0.0.0"..<"2.0.0"),
        //.package(url: "https://source.skip.tools/skip-sql.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(name: "SkipNotes", dependencies: [
            "SkipNotesModel",
            .product(name: "SkipKit", package: "skip-kit"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "SkipNotesModel", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SQLiteDB", package: "swift-sqlcipher"),
            .product(name: "SkipFuse", package: "skip-fuse"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SkipDevice", package: "skip-device"),
            //.product(name: "SkipBluetooth", package: "skip-bluetooth"),
            //.product(name: "SkipSQLPlus", package: "skip-sql"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipNotesModelTests", dependencies: [
            "SkipNotesModel",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
