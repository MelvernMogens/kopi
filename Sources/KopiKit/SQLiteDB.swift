import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DBError: Error, CustomStringConvertible {
    case open(String), prepare(String), step(String)
    public var description: String {
        switch self {
        case .open(let m): return "open: \(m)"
        case .prepare(let m): return "prepare: \(m)"
        case .step(let m): return "step: \(m)"
        }
    }
}

/// Minimal SQLite wrapper. Not thread-safe: callers own a single queue (ClipStore uses the main thread).
public final class SQLiteDB: @unchecked Sendable {
    let handle: OpaquePointer

    public init(path: String, readOnly: Bool = false) throws {
        var h: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &h, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h { sqlite3_close(h) }
            throw DBError.open(msg)
        }
        handle = h
    }

    deinit { sqlite3_close(handle) }

    var errmsg: String { String(cString: sqlite3_errmsg(handle)) }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? errmsg
            sqlite3_free(err)
            throw DBError.step(m)
        }
    }

    public enum Value {
        case int(Int64), double(Double), text(String), blob(Data), null
    }

    public final class Row {
        let stmt: OpaquePointer
        init(_ s: OpaquePointer) { stmt = s }
        public func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        public func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        public func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        public func text(_ i: Int32) -> String? {
            guard let p = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: p)
        }
        public func blob(_ i: Int32) -> Data? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let p = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    private func prepare(_ sql: String, _ args: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw DBError.prepare("\(errmsg) — \(sql)") }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    @discardableResult
    public func run(_ sql: String, _ args: [Value] = []) throws -> Int64 {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(errmsg) }
        return sqlite3_last_insert_rowid(handle)
    }

    public func query(_ sql: String, _ args: [Value] = [], _ each: (Row) throws -> Void) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        let row = Row(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { try each(row) } else if rc == SQLITE_DONE { break } else { throw DBError.step(errmsg) }
        }
    }

    public func scalar(_ sql: String, _ args: [Value] = []) throws -> Int64 {
        var v: Int64 = 0
        try query(sql, args) { v = $0.int(0) }
        return v
    }

    public var changes: Int { Int(sqlite3_changes(handle)) }
}

extension SQLiteDB.Value {
    static func opt(_ s: String?) -> SQLiteDB.Value { s.map { .text($0) } ?? .null }
    static func opt(_ d: Data?) -> SQLiteDB.Value { d.map { .blob($0) } ?? .null }
}
