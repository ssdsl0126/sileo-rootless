//
//  DatabaseManager.swift
//  Sileo
//
//  Created by Andromeda on 8/17/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//
import Foundation
import SQLite
import Evander

enum DatabaseSchemaVersion: Int {
    case versionNil = 0
    case version01000 = 1
    case version01004 = 2
    case version02000 = 3
    case version02111 = 4
}

class DatabaseManager {
    
    static let shared = DatabaseManager()
    
    private let database: Connection
    
    private var packages = ContiguousArray<Package>()
    private let stateLock = NSLock()
    private var isPaused = false
    private let databaseQueue = DispatchQueue(label: "org.coolstar.SileoStore.package-database", qos: .userInitiated)
    private var pendingWrites: [() throws -> Void] = []

    private enum AccessError: Error {
        case paused
    }
    
    init() {
        let sileoURL = EvanderNetworking._cacheDirectory.appendingPathComponent("Database")
        try? FileManager.default.createDirectory(at: sileoURL,
                                                 withIntermediateDirectories: true,
                                                 attributes: [
                                                    FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                                                 ])
        let databaseURL = sileoURL.appendingPathComponent("sileo.sqlite3")
        
        guard let database = try? Connection(databaseURL.path) else {
            fatalError("Database Connection failed")
        }
        self.database = database
        
        if self.schemaVersion < DatabaseSchemaVersion.version02111.rawValue { // 2.x database is not compatible with 1.x
            _ = try? database.run("DROP table Packages")
        } else if self.schemaVersion < DatabaseSchemaVersion.version02000.rawValue {
            _ = try? database.run("DROP table NewsArticle")
            _ = try? database.run("DROP table PackageStub")
        }
        self.schemaVersion = Int32(DatabaseSchemaVersion.version02111.rawValue)
        PackageStub.createTable(database: database)
    }
    
    private var schemaVersion: Int32 {
        get {
            database.userVersion ?? 0
        }
        set {
            database.userVersion = newValue
        }
    }
    
    public func serializePackages(_ packages: [Package]) -> Set<[String: String]> {
        Set(packages.map { ["package": $0.package, "version": $0.version] })
    }
    
    public func addToSaveQueue(packages: [Package]) {
        stateLock.withLock {
            self.packages += packages
        }
    }

    func pauseForSuspension() {
        // 先禁止打开新的读写，再中断 SQLite，等正在执行的语句释放数据库锁。
        stateLock.withLock { isPaused = true }
        database.interrupt()
        databaseQueue.sync {}
    }

    func resumeAfterSuspension() {
        stateLock.withLock { isPaused = false }
        databaseQueue.async {
            self.flushWrites()
        }
    }

    private var databaseIsPaused: Bool {
        stateLock.withLock { isPaused }
    }

    private func enqueueWrite(_ work: @escaping () throws -> Void) {
        pendingWrites.append(work)
        flushWrites()
    }

    private func flushWrites() {
        while !databaseIsPaused, let work = pendingWrites.first {
            do {
                try work()
            } catch {
                // 被挂起打断的操作留在队首，回到前台后按原顺序重试。
                if databaseIsPaused { return }
            }
            pendingWrites.removeFirst()
        }
    }
    
    public func saveQueue() {
        databaseQueue.sync {
            let batch = stateLock.withLock {
                let batch = packages
                packages.removeAll()
                return batch
            }
            guard !batch.isEmpty else { return }
            let timestamp = Int64(Date().timeIntervalSince1970)
            enqueueWrite { [unowned self] in
                try self.insertStubs(batch.lazy.map { PackageStub(from: $0) }, firstSeenAt: timestamp)
            }
        }
    }
    
    public func saveStubs(stubs: [PackageStub]) {
        guard !stubs.isEmpty else { return }
        databaseQueue.sync {
            enqueueWrite { [unowned self] in
                try self.insertStubs(stubs)
            }
        }
    }

    private func insertStubs<Stubs: Sequence>(_ stubs: Stubs, firstSeenAt timestamp: Int64? = nil) throws
    where Stubs.Element == PackageStub {
        let guid = Expression<String>("guid")
        let package = Expression<String>("package")
        let version = Expression<String>("version")
        let firstSeen = Expression<Int64>("firstSeen")
        let userRead = Expression<Int64>("userRead")
        let repoURL = Expression<String>("repoURL")
        let table = Table("Packages")

        try database.transaction {
            for stub in stubs {
                if databaseIsPaused { throw AccessError.paused }
                try database.run(table.insert(or: .ignore,
                    guid <- "\(stub.package)-\(stub.version)",
                    package <- stub.package,
                    version <- stub.version,
                    firstSeen <- (timestamp ?? Int64(stub.firstSeenDate.timeIntervalSince1970)),
                    userRead <- stub.userReadDate ?? 0,
                    repoURL <- stub.repoURL
                ))
            }
        }
    }
    
    func packageStubs() -> [PackageStub]? {
        databaseQueue.sync {
            guard !databaseIsPaused else { return nil }
            let package = Expression<String>("package")
            let version = Expression<String>("version")
            let firstSeen = Expression<Int64>("firstSeen")
            let userRead = Expression<Int64>("userRead")
            let repoURL = Expression<String>("repoURL")
            let query = Table("Packages").select(package, version, firstSeen, userRead, repoURL)

            var stubs: [PackageStub] = []
            do {
                // 一次读取完整快照，SQLite 中断时让可抛错的迭代器退出并释放游标。
                let rows = try database.prepareRowIterator(query)
                while !databaseIsPaused, let row = try rows.failableNext() {
                    var stub = PackageStub(packageName: row[package], version: row[version], source: row[repoURL])
                    let timestamp = row[firstSeen]
                    stub.firstSeenDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                    stub.firstSeen = timestamp
                    stub.userReadDate = row[userRead]
                    stubs.append(stub)
                }
            } catch {
                if databaseIsPaused { return nil }
            }
            return databaseIsPaused ? nil : stubs
        }
    }
    
    public func markAsSeen(_ dataPackage: Package) {
        let packageID = dataPackage.packageID
        databaseQueue.async {
            self.enqueueWrite { [unowned self] in
                let package = Expression<String>("package")
                let userRead = Expression<Int64>("userRead")
                let rows = Table("Packages").filter(package == packageID)
                try self.database.run(rows.update(userRead <- 1))
            }
        }
    }
   
    public func deleteRepo(repo: Repo) {
        let file = RepoManager.shared.cacheFile(named: "Packages", for: repo).lastPathComponent
        databaseQueue.sync {
            enqueueWrite { [unowned self] in
                let repoURL = Expression<String>("repoURL")
                let rows = Table("Packages").filter(repoURL == file)
                try self.database.run(rows.delete())
            }
        }
    }
    
}
