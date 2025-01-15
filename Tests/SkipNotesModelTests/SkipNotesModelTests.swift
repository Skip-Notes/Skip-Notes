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
        let notesContent = "This is an example of a note"

        let dbPath = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let vm = try ViewModel.create(withURL: dbPath)
        XCTAssertEqual(0, vm.items.count)

        var item1 = try XCTUnwrap(vm.addItem())
        XCTAssertEqual("", vm.items.first?.title)
        item1.title = "ABC"
        item1.notes = notesContent
        vm.save(item: item1)
        XCTAssertEqual(1, vm.items.count)
        XCTAssertEqual("ABC", vm.items.first?.title)

        var item2 = try XCTUnwrap(vm.addItem())
        XCTAssertEqual("", vm.items.first?.title)
        item2.title = "XYZ"
        vm.save(item: item2)
        XCTAssertEqual(2, vm.items.count)
        XCTAssertEqual("XYZ", vm.items.first?.title)

        var item3 = try XCTUnwrap(vm.addItem())
        XCTAssertEqual("", vm.items.first?.title)
        item3.title = "QRS"
        vm.save(item: item3)
        XCTAssertEqual(3, vm.items.count)
        XCTAssertEqual("QRS", vm.items.first?.title)

        XCTAssertEqual(["QRS", "XYZ", "ABC"], vm.items.map(\.title))

        vm.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(["XYZ", "ABC", "QRS"], vm.items.map(\.title))

        vm.move(fromOffsets: [1], toOffset: 2) // no change
        XCTAssertEqual(["XYZ", "ABC", "QRS"], vm.items.map(\.title))

        vm.move(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(["QRS", "XYZ", "ABC"], vm.items.map(\.title))

        // MARK: Search

        vm.filter = "DOESNOTEXIST"
        XCTAssertEqual(0, vm.items.count)

        vm.filter = "example"
        XCTAssertEqual(1, vm.items.count, "filtered list should have matched notes content")

        // update item3 to also match, ensure that the FTS index is updated and the filter works
        item3.notes = notesContent
        vm.save(item: item3)
        XCTAssertEqual(2, vm.items.count)

        // check for diacritics-insensitive matching
        item3.notes = "Jérôme enjoys piñatas, crème brûlée, jalapeños, and the occasional smörgåsbord in a quaint café."
        vm.save(item: item3)

        vm.filter = "Jérôme"
        XCTAssertEqual(1, vm.items.count)
        vm.filter = "jérôme"
        XCTAssertEqual(1, vm.items.count)
        vm.filter = "jerome"
        XCTAssertEqual(1, vm.items.count)

        vm.filter = "pina"
        XCTAssertEqual(1, vm.items.count)

        vm.filter = "pinatas"
        XCTAssertEqual(1, vm.items.count)
        vm.filter = "jalapenos"
        XCTAssertEqual(1, vm.items.count)

        vm.filter = "brûlée"
        XCTAssertEqual(1, vm.items.count)
        vm.filter = "brulée"
        XCTAssertEqual(1, vm.items.count)
        vm.filter = "brulee"
        XCTAssertEqual(1, vm.items.count)

        item3.notes = ""
        vm.save(item: item3)

        vm.filter = ""
        XCTAssertEqual(3, vm.items.count, "cleared filter should have reset search")


        // MARK: encryption
        let notesData = notesContent.data(using: .utf8)!

        XCTAssertTrue(try Data(contentsOf: dbPath).contains(notesData), "decrypted database should contain notesContent")

        let key = UUID().uuidString
        try vm.rekey(key) // encrypt the database

        XCTAssertFalse(try Data(contentsOf: dbPath).contains(notesData), "encrypted database should not contain notesContent")

        try vm.reloadRows()
        XCTAssertEqual(3, vm.items.count)

        let key2 = UUID().uuidString
        try vm.rekey(key2) // re-encrypt the database
        XCTAssertEqual(3, vm.items.count)

        try vm.rekey(nil) // decrypt the database

        XCTAssertTrue(try Data(contentsOf: dbPath).contains(notesData), "decrypted database should contain notesContent")

        try vm.reloadRows()
        XCTAssertEqual(3, vm.items.count)


        // MARK: delete
        vm.remove(atOffsets: [1])
        XCTAssertEqual(2, vm.items.count)

        vm.remove(atOffsets: Array(0..<vm.items.count))
        XCTAssertEqual(0, vm.items.count)
    }
}
