import XCTest
import OSLog
import Foundation
import SkipBridgeKt
@testable import SkipNotesModel

let logger: Logger = Logger(subsystem: "SkipNotesModel", category: "Tests")

@available(macOS 13, *)
final class SkipNotesModelTests: XCTestCase {
    override func setUp() {
        #if SKIP
        loadPeerLibrary(packageName: "skipapp-notes", moduleName: "SkipNotesModel")
        #endif
    }

    func testSkipNotesModel() throws {
        logger.log("running testSkipNotesModel")
        let vm = try ViewModel.create(withURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite"))
        XCTAssertEqual(0, vm.items.count)
        var item = try XCTUnwrap(vm.addItem())
        XCTAssertEqual("", vm.items.first?.title)

        item.title = "ABC"
        vm.save(item: item)
        XCTAssertEqual(1, vm.items.count)
        XCTAssertEqual("ABC", vm.items.first?.title)

        vm.remove(atOffsets: Array(0..<vm.items.count))
        XCTAssertEqual(0, vm.items.count)
    }
}
