import XCTest
import OSLog
import Foundation
@testable import SkipNotesModel

let logger: Logger = Logger(subsystem: "SkipNotesModel", category: "Tests")

@available(macOS 13, *)
final class SkipNotesModelTests: XCTestCase {
    func testSkipNotesModel() throws {
        logger.log("running testSkipNotesModel")
        XCTAssertEqual(1 + 2, 3, "basic test")
        
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("SkipNotesModel", testData.testModuleName)
    }
}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
