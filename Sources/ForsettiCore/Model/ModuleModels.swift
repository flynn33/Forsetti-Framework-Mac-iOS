import Foundation

public enum Platform: String, Codable, CaseIterable, Sendable {
    case iOS
    case macOS

    public static var current: Platform {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #else
        fatalError("Forsetti supports only iOS and macOS")
        #endif
    }
}

public enum Capability: String, Codable, CaseIterable, Hashable, Sendable {
    case networking
    case storage
    case secureStorage = "secure_storage"
    case fileExport = "file_export"
    case cryptoUtilities = "crypto_utilities"
    case telemetry
    case routingOverlay = "routing_overlay"
    case uiThemeMask = "ui_theme_mask"
    case toolbarItems = "toolbar_items"
    case viewInjection = "view_injection"
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security
}

public enum ModuleType: String, Codable, Sendable {
    case service
    case ui
    /// A complete single-application module that includes its own UI.
    case app
}

public struct ModuleDescriptor: Codable, Hashable, Sendable {
    public let moduleID: String
    public let displayName: String
    public let moduleVersion: SemVer
    public let moduleType: ModuleType

    public init(
        moduleID: String,
        displayName: String,
        moduleVersion: SemVer,
        moduleType: ModuleType
    ) {
        self.moduleID = moduleID
        self.displayName = displayName
        self.moduleVersion = moduleVersion
        self.moduleType = moduleType
    }
}

// swiftlint:disable identifier_name
public enum ManifestTemplateVersion: String, Codable, CaseIterable, Sendable {
    case v1_0 = "1.0"
    case v1_1 = "1.1"

    public static let current = ManifestTemplateVersion.v1_1
}
// swiftlint:enable identifier_name

public enum DefaultModuleRole: String, Codable, CaseIterable, Hashable, Sendable {
    case ui
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security

    public func isValid(for moduleType: ModuleType) -> Bool {
        switch self {
        case .ui:
            return moduleType == .ui || moduleType == .app
        case .sharedDatabase, .authentication, .diagnostics, .api, .security:
            return moduleType == .service
        }
    }

    public var requiredCapability: Capability? {
        switch self {
        case .ui:
            return nil
        case .sharedDatabase:
            return .sharedDatabase
        case .authentication:
            return .authentication
        case .diagnostics:
            return .diagnostics
        case .api:
            return .api
        case .security:
            return .security
        }
    }
}

public enum ModuleIOKind: String, Codable, CaseIterable, Hashable, Sendable {
    case networking
    case storage
    case secureStorage = "secure_storage"
    case fileExport = "file_export"
    case telemetry
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security

    public var requiredCapability: Capability {
        switch self {
        case .networking:
            return .networking
        case .storage:
            return .storage
        case .secureStorage:
            return .secureStorage
        case .fileExport:
            return .fileExport
        case .telemetry:
            return .telemetry
        case .sharedDatabase:
            return .sharedDatabase
        case .authentication:
            return .authentication
        case .diagnostics:
            return .diagnostics
        case .api:
            return .api
        case .security:
            return .security
        }
    }
}

public enum ModuleIOAccess: String, Codable, CaseIterable, Sendable {
    case read
    case write
    case readWrite = "read_write"
    case execute
    case emit
    case consume
}

public enum ModuleDataIsolationMode: String, Codable, CaseIterable, Sendable {
    case privateToModule = "private_to_module"
    case frameworkMediatedShared = "framework_mediated_shared"
}

public struct ModuleIORequirement: Codable, Hashable, Sendable {
    public let requirementID: String
    public let kind: ModuleIOKind
    public let access: ModuleIOAccess
    public let required: Bool
    public let description: String?

    public init(
        requirementID: String,
        kind: ModuleIOKind,
        access: ModuleIOAccess,
        required: Bool,
        description: String? = nil
    ) {
        self.requirementID = requirementID
        self.kind = kind
        self.access = access
        self.required = required
        self.description = description
    }
}

public struct ModuleUIRequirements: Codable, Hashable, Sendable {
    public let controlSchemeID: String?
    public let layoutID: String?
    public let themeIDs: [String]
    public let viewIDs: [String]
    public let slotIDs: [String]
    public let toolbarItemIDs: [String]
    public let routeIDs: [String]
    public let pointerIDs: [String]

    public init(
        controlSchemeID: String? = nil,
        layoutID: String? = nil,
        themeIDs: [String] = [],
        viewIDs: [String] = [],
        slotIDs: [String] = [],
        toolbarItemIDs: [String] = [],
        routeIDs: [String] = [],
        pointerIDs: [String] = []
    ) {
        self.controlSchemeID = controlSchemeID
        self.layoutID = layoutID
        self.themeIDs = themeIDs
        self.viewIDs = viewIDs
        self.slotIDs = slotIDs
        self.toolbarItemIDs = toolbarItemIDs
        self.routeIDs = routeIDs
        self.pointerIDs = pointerIDs
    }

    private enum CodingKeys: String, CodingKey {
        case controlSchemeID
        case layoutID
        case themeIDs
        case viewIDs
        case slotIDs
        case toolbarItemIDs
        case routeIDs
        case pointerIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlSchemeID = try container.decodeIfPresent(String.self, forKey: .controlSchemeID)
        layoutID = try container.decodeIfPresent(String.self, forKey: .layoutID)
        themeIDs = try container.decodeIfPresent([String].self, forKey: .themeIDs) ?? []
        viewIDs = try container.decodeIfPresent([String].self, forKey: .viewIDs) ?? []
        slotIDs = try container.decodeIfPresent([String].self, forKey: .slotIDs) ?? []
        toolbarItemIDs = try container.decodeIfPresent([String].self, forKey: .toolbarItemIDs) ?? []
        routeIDs = try container.decodeIfPresent([String].self, forKey: .routeIDs) ?? []
        pointerIDs = try container.decodeIfPresent([String].self, forKey: .pointerIDs) ?? []
    }
}

public struct ModuleDataIsolation: Codable, Hashable, Sendable {
    public let mode: ModuleDataIsolationMode
    public let ownedStoreIDs: [String]
    public let requiredDefaultRoles: [DefaultModuleRole]

    public init(
        mode: ModuleDataIsolationMode,
        ownedStoreIDs: [String] = [],
        requiredDefaultRoles: [DefaultModuleRole] = []
    ) {
        self.mode = mode
        self.ownedStoreIDs = ownedStoreIDs
        self.requiredDefaultRoles = requiredDefaultRoles
    }

    public static let privateToModule = ModuleDataIsolation(mode: .privateToModule)

    private enum CodingKeys: String, CodingKey {
        case mode
        case ownedStoreIDs
        case requiredDefaultRoles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ModuleDataIsolationMode.self, forKey: .mode)
        ownedStoreIDs = try container.decodeIfPresent([String].self, forKey: .ownedStoreIDs) ?? []
        requiredDefaultRoles = try container.decodeIfPresent(
            [DefaultModuleRole].self,
            forKey: .requiredDefaultRoles
        ) ?? []
    }
}

public struct ModuleRuntimeRequirements: Codable, Hashable, Sendable {
    public let io: [ModuleIORequirement]
    public let ui: ModuleUIRequirements?
    public let dataIsolation: ModuleDataIsolation

    public init(
        io: [ModuleIORequirement] = [],
        ui: ModuleUIRequirements? = nil,
        dataIsolation: ModuleDataIsolation = .privateToModule
    ) {
        self.io = io
        self.ui = ui
        self.dataIsolation = dataIsolation
    }

    public static let safeLegacyDefaults = ModuleRuntimeRequirements()
}

public struct ModuleManifest: Codable, Hashable, Sendable {
    public static let supportedSchemaVersion = "1.0"
    public static let currentSchemaVersion = "1.1"
    public static let supportedSchemaVersions: Set<String> = [supportedSchemaVersion, currentSchemaVersion]
    public static let supportedManifestTemplateVersions: Set<ManifestTemplateVersion> = [.v1_0, .v1_1]

    public let schemaVersion: String
    public let manifestTemplateVersion: ManifestTemplateVersion
    public let moduleID: String
    public let displayName: String
    public let moduleVersion: SemVer
    public let moduleType: ModuleType
    public let supportedPlatforms: [Platform]
    public let minForsettiVersion: SemVer
    public let maxForsettiVersion: SemVer?
    public let capabilitiesRequested: [Capability]
    public let iapProductID: String?
    public let entryPoint: String
    public let defaultModuleRole: DefaultModuleRole?
    public let runtimeRequirements: ModuleRuntimeRequirements

    public init(
        schemaVersion: String,
        manifestTemplateVersion: ManifestTemplateVersion? = nil,
        moduleID: String,
        displayName: String,
        moduleVersion: SemVer,
        moduleType: ModuleType,
        supportedPlatforms: [Platform],
        minForsettiVersion: SemVer,
        maxForsettiVersion: SemVer? = nil,
        capabilitiesRequested: [Capability],
        iapProductID: String? = nil,
        entryPoint: String,
        defaultModuleRole: DefaultModuleRole? = nil,
        runtimeRequirements: ModuleRuntimeRequirements = .safeLegacyDefaults
    ) {
        self.schemaVersion = schemaVersion
        self.manifestTemplateVersion = manifestTemplateVersion ?? (schemaVersion == Self.currentSchemaVersion ? .v1_1 : .v1_0)
        self.moduleID = moduleID
        self.displayName = displayName
        self.moduleVersion = moduleVersion
        self.moduleType = moduleType
        self.supportedPlatforms = supportedPlatforms
        self.minForsettiVersion = minForsettiVersion
        self.maxForsettiVersion = maxForsettiVersion
        self.capabilitiesRequested = capabilitiesRequested
        self.iapProductID = iapProductID
        self.entryPoint = entryPoint
        self.defaultModuleRole = defaultModuleRole
        self.runtimeRequirements = runtimeRequirements
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case manifestTemplateVersion
        case moduleID
        case displayName
        case moduleVersion
        case moduleType
        case supportedPlatforms
        case minForsettiVersion
        case maxForsettiVersion
        case capabilitiesRequested
        case iapProductID
        case entryPoint
        case defaultModuleRole
        case runtimeRequirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        manifestTemplateVersion = try container.decodeIfPresent(
            ManifestTemplateVersion.self,
            forKey: .manifestTemplateVersion
        ) ?? .v1_0
        moduleID = try container.decode(String.self, forKey: .moduleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        moduleVersion = try container.decode(SemVer.self, forKey: .moduleVersion)
        moduleType = try container.decode(ModuleType.self, forKey: .moduleType)
        supportedPlatforms = try container.decode([Platform].self, forKey: .supportedPlatforms)
        minForsettiVersion = try container.decode(SemVer.self, forKey: .minForsettiVersion)
        maxForsettiVersion = try container.decodeIfPresent(SemVer.self, forKey: .maxForsettiVersion)
        capabilitiesRequested = try container.decode([Capability].self, forKey: .capabilitiesRequested)
        iapProductID = try container.decodeIfPresent(String.self, forKey: .iapProductID)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        defaultModuleRole = try container.decodeIfPresent(DefaultModuleRole.self, forKey: .defaultModuleRole)
        runtimeRequirements = try container.decodeIfPresent(
            ModuleRuntimeRequirements.self,
            forKey: .runtimeRequirements
        ) ?? .safeLegacyDefaults
    }
}
