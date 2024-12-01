import Foundation
import Observation
import SkipFuse
import SkipKeychain
import SQLiteDB

fileprivate let logger: Logger = Logger(subsystem: "SkipNotesModel", category: "SkipNotesModel")

/// The Observable ViewModel used by the application.
@Observable public class ViewModel {
    public static let shared = try! ViewModel()

    private static let dbPath = URL.applicationSupportDirectory.appendingPathComponent("notes.sqlite")

    private let db: Connection

    public var name = "Skipper"
    public private(set) var items: [Item] = []
    public var errorMessage: String? = nil

    private init() throws {
        // make sure the application support folder exists
        logger.info("connecting to database: \(Self.dbPath.path)")
        try FileManager.default.createDirectory(at: Self.dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.db = try Connection(Self.dbPath.path)
        self.db.trace { logger.info("SQL: \($0)") }

        // TODO: check whether table exists first
        _ = try? db.run(Item.table.create { builder in
            builder.column(Item.idColumn, primaryKey: true)
            builder.column(Item.dateColumn)
            builder.column(Item.favoriteColumn)
            builder.column(Item.orderColumn)
            builder.column(Item.titleColumn)
            builder.column(Item.notesColumn)
        })

        try reloadRows()
    }

    /// Loads all the rows from the database
    func reloadRows() throws {
        self.items = try db.prepare(Item.table.order(Item.orderColumn.desc, Item.dateColumn.desc)).map({ try $0.decode() })
    }

    func reloading(_ f: () throws -> ()) {
        defer { try? reloadRows() }
        do {
            try f()
        } catch {
            logger.error("error performing operation: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }

    public func addItem() {
        reloading {
            var item = Item()
            // set the order to be the max plus 1.0
            item.order = (items.map(\.order).max() ?? 0.0) + 1.0
            try db.run(Item.table.insert(item))
        }
    }

    public func remove(atOffsets offsets: Array<Int>) {
        reloading {
            let ids = offsets.map({ items[$0].id })
            let query = Item.table.filter(ids.contains(Item.idColumn))
            try db.run(query.delete())
        }
    }

    public func move(fromOffsets source: Array<Int>, toOffset destination: Int) {
        reloading {
            // update the "order" column to be halfway between the two adjacent item, or max+1.0 for moving to the first row
            let dorder = destination == 0 ? (items[destination].order + 1.0)
            : destination == items.count ? (items[destination - 1].order - 1.0)
            : (items[destination].order + ((items[destination - 1].order - items[destination].order) / 2.0))
            let sourceItems = source.map({
                var item = items[$0]
                item.order = dorder
                return item
            })
            for sourceItem in sourceItems {
                try db.run(Item.table.upsert(sourceItem, onConflictOf: Item.idColumn))
            }
        }
    }

    public func isUpdated(_ item: Item) -> Bool {
        item != items.first { i in
            i.id == item.id
        }
    }

    public func save(item: Item) {
        reloading {
            try db.run(Item.table.upsert(item, onConflictOf: Item.idColumn))
        }
    }
}

/// An individual item held by the ViewModel
public struct Item : Identifiable, Hashable, Codable {
    static let table = Table("item")

    public let id: UUID
    static let idColumn = SQLExpression<UUID>("id")

    public var date: Date
    static let dateColumn = SQLExpression<Date>("date")

    public var order: Double
    static let orderColumn = SQLExpression<Double>("order")

    public var favorite: Bool
    static let favoriteColumn = SQLExpression<Bool>("favorite")

    public var title: String
    static let titleColumn = SQLExpression<String>("title")

    public var notes: String
    static let notesColumn = SQLExpression<String>("notes")

    public init(id: UUID = UUID(), date: Date = .now, order: Double = 0.0, favorite: Bool = false, title: String = "", notes: String = "") {
        self.id = id
        self.date = date
        self.order = order
        self.favorite = favorite
        self.title = title
        self.notes = notes
    }

    public var itemTitle: String {
        !title.isEmpty ? title : dateString
    }

    public var dateString: String {
        date.formatted(date: .complete, time: .omitted)
    }

    public var dateTimeString: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
