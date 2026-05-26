// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
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
        .package(url: "https://source.skip.tools/skip.git", from: "1.7.4"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.3.13"),
        .package(url: "https://source.skip.tools/skip-model.git", from: "1.7.1"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.50.0"),
        .package(url: "https://source.skip.tools/skip-keychain.git", "0.3.2"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-kit.git",  from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-device.git", "0.4.2"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-sql.git", "0.14.0"..<"2.0.0"),
        .package(url: "https://github.com/appfair/appfair-app.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SkipNotes", dependencies: [
            "SkipNotesModel",
            .product(name: "AppFairUI", package: "appfair-app"),
            .product(name: "SkipKit", package: "skip-kit"),
            .product(name: "SkipUI", package: "skip-ui"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "SkipNotesModel", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipModel", package: "skip-model"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SkipDevice", package: "skip-device"),
            .product(name: "SkipSQLPlus", package: "skip-sql"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipNotesModelTests", dependencies: [
            "SkipNotesModel",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)

if let dependencyRoot = Context.environment["SKIP_DEPENDENCY_ROOT"] {
    package.dependencies = package.dependencies.map { dep in
        switch dep.kind {
        case .sourceControl(_, let location, _):
            // turn "https://source.skip.tools/skip-foundation.git" into "skip-foundation"
            guard let baseName = location.split(separator: "/").last?.split(separator: ".").first else {
                return dep
            }
            guard baseName.hasPrefix("skip-") else {
                return dep
            }
            return Package.Dependency.package(path: dependencyRoot + "/" + baseName)
        default:
            return dep
        }
    }
}
