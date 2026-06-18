import Foundation

public struct ModuleRegistrationRecord: Codable, Hashable, Sendable {
    public let moduleID: String
    public let displayName: String
    public let moduleVersion: SemVer
    public let moduleType: ModuleType
    public let entryPoint: String
    public let schemaVersion: String
    public let manifestTemplateVersion: ManifestTemplateVersion
    public let manifestHash: String
    public let supportedPlatforms: [Platform]
    public let capabilitiesRequested: [Capability]
    public let defaultModuleRole: DefaultModuleRole?
    public let runtimeRequirements: ModuleRuntimeRequirements
    public let registeredAt: Date

    public init(
        moduleID: String,
        displayName: String,
        moduleVersion: SemVer,
        moduleType: ModuleType,
        entryPoint: String,
        schemaVersion: String,
        manifestTemplateVersion: ManifestTemplateVersion,
        manifestHash: String,
        supportedPlatforms: [Platform],
        capabilitiesRequested: [Capability],
        defaultModuleRole: DefaultModuleRole?,
        runtimeRequirements: ModuleRuntimeRequirements,
        registeredAt: Date
    ) {
        self.moduleID = moduleID
        self.displayName = displayName
        self.moduleVersion = moduleVersion
        self.moduleType = moduleType
        self.entryPoint = entryPoint
        self.schemaVersion = schemaVersion
        self.manifestTemplateVersion = manifestTemplateVersion
        self.manifestHash = manifestHash
        self.supportedPlatforms = supportedPlatforms
        self.capabilitiesRequested = capabilitiesRequested
        self.defaultModuleRole = defaultModuleRole
        self.runtimeRequirements = runtimeRequirements
        self.registeredAt = registeredAt
    }

    public static func make(manifest: ModuleManifest, registeredAt: Date = Date()) throws -> ModuleRegistrationRecord {
        ModuleRegistrationRecord(
            moduleID: manifest.moduleID,
            displayName: manifest.displayName,
            moduleVersion: manifest.moduleVersion,
            moduleType: manifest.moduleType,
            entryPoint: manifest.entryPoint,
            schemaVersion: manifest.schemaVersion,
            manifestTemplateVersion: manifest.manifestTemplateVersion,
            manifestHash: try Self.manifestHash(for: manifest),
            supportedPlatforms: manifest.supportedPlatforms,
            capabilitiesRequested: manifest.capabilitiesRequested,
            defaultModuleRole: manifest.defaultModuleRole,
            runtimeRequirements: manifest.runtimeRequirements,
            registeredAt: registeredAt
        )
    }

    public func matches(manifest: ModuleManifest) throws -> Bool {
        let currentManifestHash = try Self.manifestHash(for: manifest)
        return moduleID == manifest.moduleID &&
            displayName == manifest.displayName &&
            moduleVersion == manifest.moduleVersion &&
            moduleType == manifest.moduleType &&
            entryPoint == manifest.entryPoint &&
            schemaVersion == manifest.schemaVersion &&
            manifestTemplateVersion == manifest.manifestTemplateVersion &&
            supportedPlatforms == manifest.supportedPlatforms &&
            capabilitiesRequested == manifest.capabilitiesRequested &&
            defaultModuleRole == manifest.defaultModuleRole &&
            runtimeRequirements == manifest.runtimeRequirements &&
            manifestHash == currentManifestHash
    }

    public static func manifestHash(for manifest: ModuleManifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        return fnv1a64Hex(data)
    }

    private static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}

public protocol ModuleRegistrationStore: Sendable {
    func loadRecord(moduleID: String) throws -> ModuleRegistrationRecord?
    func saveRecord(_ record: ModuleRegistrationRecord) throws
    func allRecords() throws -> [ModuleRegistrationRecord]
    func removeRecord(moduleID: String) throws
}

public final class InMemoryModuleRegistrationStore: ModuleRegistrationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var recordsByID: [String: ModuleRegistrationRecord]

    public init(records: [ModuleRegistrationRecord] = []) {
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.moduleID, $0) })
    }

    public func loadRecord(moduleID: String) throws -> ModuleRegistrationRecord? {
        lock.lock()
        defer { lock.unlock() }
        return recordsByID[moduleID]
    }

    public func saveRecord(_ record: ModuleRegistrationRecord) throws {
        lock.lock()
        recordsByID[record.moduleID] = record
        lock.unlock()
    }

    public func allRecords() throws -> [ModuleRegistrationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return recordsByID.values.sorted { $0.moduleID < $1.moduleID }
    }

    public func removeRecord(moduleID: String) throws {
        lock.lock()
        recordsByID[moduleID] = nil
        lock.unlock()
    }
}

public final class UserDefaultsModuleRegistrationStore: ModuleRegistrationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.forsetti.registration.records"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadRecord(moduleID: String) throws -> ModuleRegistrationRecord? {
        try loadRecords()[moduleID]
    }

    public func saveRecord(_ record: ModuleRegistrationRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var records = try loadRecordsUnlocked()
        records[record.moduleID] = record
        try saveRecordsUnlocked(records)
    }

    public func allRecords() throws -> [ModuleRegistrationRecord] {
        try loadRecords().values.sorted { $0.moduleID < $1.moduleID }
    }

    public func removeRecord(moduleID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var records = try loadRecordsUnlocked()
        records[moduleID] = nil
        try saveRecordsUnlocked(records)
    }

    private func loadRecords() throws -> [String: ModuleRegistrationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadRecordsUnlocked()
    }

    private func loadRecordsUnlocked() throws -> [String: ModuleRegistrationRecord] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }
        return try decoder.decode([String: ModuleRegistrationRecord].self, from: data)
    }

    private func saveRecordsUnlocked(_ records: [String: ModuleRegistrationRecord]) throws {
        let data = try encoder.encode(records)
        defaults.set(data, forKey: key)
    }
}
