import Foundation
import Observation
import SkipFuse
import SkipSQLPlus
import SkipKeychain
@preconcurrency import SkipDevice

let logger: Logger = Logger(subsystem: "skip.notes", category: "SkipNotesModel")

/// The Observable ViewModel used by the application.
@Observable public final class ViewModel : @unchecked Sendable {
    public static let shared = try! ViewModel(dbPath: URL.applicationSupportDirectory.appendingPathComponent("notesdb.sqlite"))

    private static let orderOffset = 100.0
    private let dbPath: URL
    private var db: SQLContext
    /// The database encryption key
    private var dbkey: String? = nil
    private static let dbkeyProp = "dbkey"

    /// Whether the database is currently being encrypted to decrypted
    public var crypting: Bool = false

    /// Information about the current location
    public var locationDescription = ""

    /// Whether or not this database is encrypted; setting it to true will encrypt the database with a new random key, which will be stored in the Keychain
    public var encrypted: Bool {
        get {
            self.dbkey != nil
        }

        set {
            self.crypting = true
            Task.detached {
                var newKey: String?
                do {
                    newKey = try self.cryptDatabase(encrypt: newValue)
                } catch {
                    logger.error("error setting encryption: \(error)")
                }
                Task { @MainActor in
                    self.dbkey = newKey
                    self.crypting = false
                }
            }
        }
    }

    /// Whether to enable location services to annotate notes based on the current location
    public var useLocation: Bool = UserDefaults.standard.bool(forKey: "useLocation") {
        didSet {
            UserDefaults.standard.set(useLocation, forKey: "useLocation")
            if useLocation == true {
                Task.detached {
                    do {
                        // TODO: on Android, we need to explicitly request location permission, but this needs SkipKit.PermissionManager which is only imported by the UI layer
                        let location = try await self.fetchLocation()
                        Task { @MainActor in
                            self.locationDescription = "\(location)"
                        }
                    } catch {
                        self.locationDescription = "Error fetching location: \(error)"
                    }
                }
            }
        }
    }

    // the current notes filter, which will be bound to a search field in the user interface
    public var filter = "" {
        didSet {
            do {
                try reloadRows()
            } catch {
                logger.error("error reloading rows: \(error)")
            }
        }
    }

    public private(set) var items: [Item] = []
    public var errorMessage: String? = nil

    init(dbPath: URL) throws {
        // make sure the application support folder exists
        logger.info("connecting to database: \(dbPath.path)")
        self.dbPath = dbPath
        try FileManager.default.createDirectory(at: dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            self.dbkey = try Keychain.shared.string(forKey: Self.dbkeyProp)
        } catch {
            // if the keychain cannot be loaded (e.g., we are running in Robolectric) then just log an error
            logger.error("error loading keychain: \(error)")
        }
        self.db = try Self.connect(url: dbPath)

        if let key = self.dbkey {
            logger.info("dbkey: \(key)")
            try db.key(key)
        }

        try initializeSchema()
        try reloadRows()
    }


    private static func connect(url: URL) throws -> SQLContext {
        let db = try SQLContext(path: url.path, flags: [.create, .readWrite], configuration: .plus)
        #if DEBUG
        db.trace { logger.info("SQL: \($0)") }
        #endif
        return db
    }

    private func cryptDatabase(encrypt: Bool) throws -> String? {
        if encrypt {
            let newKey = UUID().uuidString
            try Keychain.shared.set(newKey, forKey: Self.dbkeyProp)
            try self.rekey(newKey)
            return newKey
        } else {
            try Keychain.shared.removeValue(forKey: Self.dbkeyProp)
            try self.rekey(nil)
            return nil
        }
    }

    /// Public constructor for bridging testing
    public static func create(withURL url: URL, key: String? = nil) throws -> ViewModel {
        try ViewModel(dbPath: url)
    }

    private func initializeSchema() throws {
        logger.info("db.userVersion: \(self.db.userVersion)")

        if db.userVersion == 0 {
            for ddl in Item.table.createTableSQL() {
                try db.exec(ddl)
            }
            db.userVersion = 4
        }

//        if db.userVersion == 0 {
//            // create the database for the initial schema version
//            try db.run(Item.table.create { builder in
//                builder.column(Item.idColumn, primaryKey: true)
//                builder.column(Item.dateColumn)
//                builder.column(Item.favoriteColumn)
//                builder.column(Item.orderColumn)
//                builder.column(Item.titleColumn)
//                builder.column(Item.notesColumn)
//            })
//            db.userVersion = 1
//        }
//
//        // schema migrations update the userVersion each time they change the DB
//        if db.userVersion == 1 {
//            try db.run(Item.table.createIndex(Item.dateColumn, unique: false))
//            try db.run(Item.table.createIndex(Item.favoriteColumn, unique: false))
//            try db.run(Item.table.createIndex(Item.orderColumn, unique: false))
//            db.userVersion = 2
//        }
//
//        // create indices
//        if db.userVersion == 2 {
//            try db.run(Item.table.createIndex(Item.titleColumn, unique: false))
//            try db.run(Item.table.createIndex(Item.notesColumn, unique: false))
//            db.userVersion = 3
//        }
//
//        // create full-text search index
//        if db.userVersion == 3 {
//            let config = FTS4Config()
//                .externalContent(Item.table)
//                .column(Item.titleColumn)
//                .column(Item.notesColumn)
//                .tokenizer(.Unicode61(removeDiacritics: true))
//            try db.run(Item.FTSIndex.table.create(.FTS4(config)))
//
//            // initialize triggers needed to keep the index up to date
//            for trigger in config.createFTSTriggers(docid: Item.FTSIndex.docidColumnName, tableName: Item.tableName, ftsTableName: Item.FTSIndex.tableName, columns: Item.titleColumnName, Item.notesColumnName) {
//                try db.run(trigger)
//            }
//
//            db.userVersion = 4
//        }
    }

    /// Loads all the rows from the database
    public func reloadRows() throws {

        var query: SQLPredicate? = nil

        if !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // brute-force LIKE
            let like = "%" + filter.lowercased() + "%"
            query = .like(Item.title, SQLValue(like))

            // TODO: restore FTS search
//        var query: SchemaType = Item.table.select(Item.allColumns) // cannot just select all in case there is a join to the FTS table, which raises error reloading rows: Ambiguous column `"title"` (please disambiguate: ["\"fts_item\".\"title\"", "\"item\".\"title\""])
//            //query = query.filter(Item.titleColumn.lowercaseString.like(like) || Item.notesColumn.lowercaseString.like(like))
//
//            // FTS table join query
//            query = query
//                .join(Item.FTSIndex.table, on: Item.table[Item.rowIdColumn] == Item.FTSIndex.table[Item.FTSIndex.docidColumn])
//                .filter(Item.FTSIndex.table.match(filter + "*")) // always add the wildcard for FTS filters
        }
//        query = query.order(Item.orderColumn.desc, Item.dateColumn.desc)
//        self.items = try db.prepare(query).map({ try $0.decode() })


        self.items = try db.query(Item.self)
            .where(query)
            .orderBy(Item.order, order: .descending)
            .orderBy(Item.date, order: .descending)
            .eval()
            .load()
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
            return try db.insert(item)
        }.get()
    }

    public func remove(atOffsets offsets: Array<Int>) {
        reloading {
            let ids = offsets.map({ SQLValue(items[$0].id.uuidString) })
            try db.delete(Item.self, where: SQLPredicate.in(Item.id, ids))
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
                try db.update(sourceItem)
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
            try db.insert(item, upsert: true)
        }
    }

    /// Set the encryption key of the database, or clear it if nil
    public func rekey(_ key: String?) throws {
        logger.info("\(key == nil ? "decrypting" : "encrypting") database")
        try convertKey(key)
    }

    /// Convert between an encrypted and unencryped database by attaching to a new database and exporting with `cipher_export`
    ///
    /// TODO: we don't need to export and rename the database if we are changing from one key to another
    private func convertKey(_ key: String?) throws {
        let v = db.userVersion
        let tmpDBURL = dbPath.appendingPathExtension("rekey")

        // create a new temporary location to encrypt the database
        try db.export(tmpDBURL.path, key: key ?? "")

        try db.close() // disconnect the current DB so we can safely overwrite it

        // move the encrypted database to the new path
        try FileManager.default.removeItem(at: dbPath)
        try FileManager.default.moveItem(at: tmpDBURL, to: dbPath)

        db = try Self.connect(url: dbPath) // reconnect to the newly converted database
        if let key = key {
            try db.key(key)
        }

        // re-set the userVersion, which is not copied by pragma sqlcipher_export
        // “sqlcipher_export does not alter the user_version of the target database. Applications are free to do this themselves.” – https://www.zetetic.net/sqlcipher/sqlcipher-api/#notes-export
        db.userVersion = v
    }
}

extension ViewModel {
    /// Fetches the current location
    public func fetchLocation() async throws -> LocationEvent {
        try await LocationProvider().fetchCurrentLocation()
    }
}

/// An individual item held by the ViewModel
///
/// `SQL: CREATE TABLE "item" ("id" TEXT PRIMARY KEY NOT NULL, "date" TEXT NOT NULL, "order" REAL NOT NULL, "favorite" INTEGER NOT NULL, "title" TEXT NOT NULL, "notes" TEXT NOT NULL)`
public struct Item : Identifiable, Hashable, SQLCodable {
    //public let rowid: Int64
    //static let rowid = SQLColumn(name: "rowid", type: .long)

    public let id: UUID
    static let id = SQLColumn(name: "id", type: .text, primaryKey: true, nullable: false)

    public var date: Date
    static let date = SQLColumn(name: "date", type: .text, nullable: false, index: SQLIndex(name: "idx_item_date"))

    public var order: Double
    static let order = SQLColumn(name: "order", type: .real, nullable: false, index: SQLIndex(name: "idx_item_order"))

    public var favorite: Bool
    static let favorite = SQLColumn(name: "favorite", type: .long, nullable: false, index: SQLIndex(name: "idx_item_favorite"))

    public var title: String
    static let title = SQLColumn(name: "title", type: .text, nullable: false, index: SQLIndex(name: "idx_item_title"))

    public var notes: String
    static let notes = SQLColumn(name: "notes", type: .text, nullable: false)

    // SKIP @nobridge
    public static let table = SQLTable(name: "item", columns: [id, date, order, favorite, title, notes])

    public init(id: UUID = UUID(), date: Date = .now, order: Double = 0.0, favorite: Bool = false, title: String = "", notes: String = "") {
        self.id = id
        self.date = date
        self.order = order
        self.favorite = favorite
        self.title = title
        self.notes = notes
    }

    // SKIP @nobridge
    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try UUID(uuidString: Self.id.textValueRequired(in: row)) ?? UUID()
        self.date = try Self.date.dateValueRequired(in: row)
        self.order = try Self.order.realValueRequired(in: row)
        self.favorite = try Self.favorite.longValueRequired(in: row) != 0 ? true : false
        self.title = try Self.title.textValueRequired(in: row)
        self.notes = try Self.notes.textValueRequired(in: row)
    }

    // SKIP @nobridge
    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id.uuidString)
        row[Self.date] = SQLValue(self.date.ISO8601Format())
        row[Self.order] = SQLValue(self.order)
        row[Self.favorite] = SQLValue(self.favorite ? 1 : 0)
        row[Self.title] = SQLValue(self.title)
        row[Self.notes] = SQLValue(self.notes)
    }

    public var dateString: String {
        date.formatted(date: .complete, time: .omitted)
    }

    public var dateTimeString: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

//    /// The full-text search index table for the Item
//    struct FTSIndex {
//        static let tableName = "fts_item"
//        static let table = VirtualTable(tableName)
//
//        static let docidColumn = SQLExpression<Int64>(docidColumnName)
//        static let docidColumnName = "docid"
//    }

    // Full-text search index for title & notes
    //static let contentsSearchTable = VirtualTable("contents")
}

//extension FTSConfig {
//    /// Returns the SQL that creates the triggers that are needed to keep the FTS table up to date when the source table changs
//    func createFTSTriggers(rowid: String = "rowid", docid: String, tableName: String, ftsTableName: String, columns: String..., rebuild: Bool = true) -> [String] {
//        var sql: [String] = []
//
//        for event in ["UPDATE", "DELETE"] {
//            // e.g.: CREATE TRIGGER fts_item_before_update_item BEFORE UPDATE ON item BEGIN DELETE FROM fts_item WHERE docid=old.rowid
//            sql.append("""
//            CREATE TRIGGER \(ftsTableName)_before_\(event.lowercased())_\(tableName) BEFORE \(event) ON \(tableName) BEGIN
//              DELETE FROM \(ftsTableName) WHERE \(docid)=old.\(rowid);
//            END;
//            """)
//        }
//
//        let columnNames = columns.joined(separator: ", ")
//        // new columns in values need to start with the "new" prefix
//        let newColumnNames = ([rowid] + columns).map({ "new." + $0 }).joined(separator: ", ")
//
//        for event in ["UPDATE", "INSERT"] {
//            sql.append("""
//            CREATE TRIGGER \(ftsTableName)_after_\(event.lowercased())_\(tableName) AFTER \(event) ON \(tableName) BEGIN
//              INSERT INTO \(ftsTableName)(\(docid), \(columnNames)) VALUES(\(newColumnNames));
//            END;
//            """)
//        }
//
//        if rebuild {
//            // rebuild index in case this was added after some rows were created
//            sql.append("""
//            INSERT INTO \(ftsTableName)(\(ftsTableName)) VALUES('rebuild')
//            """)
//        }
//
//        return sql
//    }
//}
