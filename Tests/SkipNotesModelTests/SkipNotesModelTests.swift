import XCTest
import OSLog
import Foundation
@testable import SkipNotesModel

let logger: Logger = Logger(subsystem: "SkipNotesModel", category: "Tests")

@available(macOS 13, *)
final class SkipNotesModelTests: XCTestCase {
    func testSkipNotesModel() throws {
        logger.log("running testSkipNotesModel")
    }
}
