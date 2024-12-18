import Foundation
import Observation
import SkipFuse
import SkipKeychain
import SQLiteDB

fileprivate let logger: Logger = Logger(subsystem: "SkipNotesModel", category: "SkipNotesModel")

/// The Observable ViewModel used by the application.
@Observable public class ViewModel {
    public static let shared = try! ViewModel(dbPath: URL.applicationSupportDirectory.appendingPathComponent("notesdb.sqlite"))

    private static let orderOffset = 100.0
    private let db: Connection

    // the current notes filter, which will be bound to a search field in the user interface
    public var filter = "" {
        didSet {
            do {
                try reloadRows()
            } catch {
                logger.error("error reloading rows: \(error.localizedDescription)")
            }
        }
    }

    public private(set) var items: [Item] = []
    public var errorMessage: String? = nil

    init(dbPath: URL) throws {
        // make sure the application support folder exists
        logger.info("connecting to database: \(dbPath.path)")
        try FileManager.default.createDirectory(at: dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.db = try Connection(dbPath.path)
        #if DEBUG
        self.db.trace { logger.info("SQL: \($0)") }
        #endif
        try initializeSchema()
        try reloadRows()
    }

    /// Public constructor for bridging testing
    public static func create(withURL url: URL) throws -> ViewModel {
        try ViewModel(dbPath: url)
    }

    private func initializeSchema() throws {
        if db.userVersion == 0 {
            // create the database for the initial schema version
            try db.run(Item.table.create { builder in
                builder.column(Item.idColumn, primaryKey: true)
                builder.column(Item.dateColumn)
                builder.column(Item.favoriteColumn)
                builder.column(Item.orderColumn)
                builder.column(Item.titleColumn)
                builder.column(Item.notesColumn)
            })
            db.userVersion = 1
        }

        // schema migrations update the userVersion each time they change the DB
        if db.userVersion == 1 {
            try db.run(Item.table.createIndex(Item.dateColumn, unique: false))
            try db.run(Item.table.createIndex(Item.favoriteColumn, unique: false))
            try db.run(Item.table.createIndex(Item.orderColumn, unique: false))
            db.userVersion = 2
        }

        // create full-text search index
        if db.userVersion == 2 {
            try db.run(Item.table.createIndex(Item.titleColumn, unique: false))
            try db.run(Item.table.createIndex(Item.notesColumn, unique: false))

            // alternatively, we could create a FTS index, but we would need to also create a trigger to keep the seach table updated
            /*
            let config = FTS5Config()
                .column(Item.titleColumn)
                .column(Item.notesColumn)

            // CREATE VIRTUAL TABLE "contents" USING fts5("title", "notes")
            try db.run(Item.contentsSearchTable.create(.FTS5(config)))
            */

            db.userVersion = 3
        }

    }

    /// Loads all the rows from the database
    func reloadRows() throws {
        var query: SchemaType = Item.table
        if !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // this could be where we use the FTS index for efficient search rather than brute-force LIKE
            let like = "%" + filter.lowercased() + "%"
            query = query.filter(Item.titleColumn.lowercaseString.like(like) || Item.notesColumn.lowercaseString.like(like))
        }
        query = query.order(Item.orderColumn.desc, Item.dateColumn.desc)
        self.items = try db.prepare(query).map({ try $0.decode() })
    }

    /// Perform the given operation and reload all the rows afterwards
    @discardableResult func reloading<T>(_ f: () throws -> T) -> Swift.Result<T, Error> {
        defer { try? reloadRows() }
        do {
            return try .success(f())
        } catch {
            logger.error("error performing operation: \(error)")
            self.errorMessage = error.localizedDescription
            return .failure(error)
        }
    }

    @discardableResult public func addItem() -> Item? {
        try? reloading {
            self.filter = "" // clear any search filters on insert
            var item = Item()
            // set the order to be the max plus 1.0
            item.order = (items.map(\.order).max() ?? 0.0) + Self.orderOffset
            try db.run(Item.table.insert(item))
            return item
        }.get()
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
            // update the "order" column to be halfway between the two adjacent items, or max+100.0 for moving to the first row
            let dorder = destination == 0 ? (items[destination].order + Self.orderOffset)
                : destination == items.count ? (items[destination - 1].order - Self.orderOffset)
                : (items[destination].order + ((items[destination - 1].order - items[destination].order) / 2.0))
            let sourceItems = source.map({
                var item = items[$0]
                item.order = dorder
                return item
            })
            for sourceItem in sourceItems {
                try db.run(Item.table.filter(Item.idColumn == sourceItem.id).update(sourceItem))
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
            // perform an upsert because we don't know if this is a new item or an existing one
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

    // Full-text search index for title & notes
    //static let contentsSearchTable = VirtualTable("contents")

    public init(id: UUID = UUID(), date: Date = .now, order: Double = 0.0, favorite: Bool = false, title: String = "", notes: String = "") {
        self.id = id
        self.date = date
        self.order = order
        self.favorite = favorite
        self.title = title
        self.notes = notes
    }

    /// Fall back to "New Note" when the item title is empty
    public var itemTitle: String {
        !title.isEmpty ? title : "New Note"
    }

    public var dateString: String {
        date.formatted(date: .complete, time: .omitted)
    }

    public var dateTimeString: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
