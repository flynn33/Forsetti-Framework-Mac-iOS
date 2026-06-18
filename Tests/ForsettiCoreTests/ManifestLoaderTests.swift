import Foundation
import XCTest
@testable import ForsettiCore

final class ManifestLoaderTests: XCTestCase {
    func testDecodesLegacyManifestWithSafeRequirementDefaults() throws {
        let legacyJSON = """
        {
          "schemaVersion": "1.0",
          "moduleID": "com.forsetti.module.legacy",
          "displayName": "Legacy Module",
          "moduleVersion": { "major": 1, "minor": 0, "patch": 0 },
          "moduleType": "service",
          "supportedPlatforms": ["iOS", "macOS"],
          "minForsettiVersion": { "major": 0, "minor": 1, "patch": 0 },
          "maxForsettiVersion": null,
          "capabilitiesRequested": [],
          "iapProductID": null,
          "entryPoint": "LegacyModule"
        }
        """

        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(manifest.manifestTemplateVersion, .v1_0)
        XCTAssertNil(manifest.defaultModuleRole)
        XCTAssertTrue(manifest.runtimeRequirements.io.isEmpty)
        XCTAssertNil(manifest.runtimeRequirements.ui)
        XCTAssertEqual(manifest.runtimeRequirements.dataIsolation.mode, .privateToModule)
    }

    func testRejectsIORequirementWithoutMatchingCapability() throws {
        let manifest = ModuleManifest(
            schemaVersion: ModuleManifest.currentSchemaVersion,
            manifestTemplateVersion: .v1_1,
            moduleID: "com.forsetti.module.storage-reader",
            displayName: "Storage Reader",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: .service,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: ForsettiVersion.current,
            maxForsettiVersion: nil,
            capabilitiesRequested: [],
            iapProductID: nil,
            entryPoint: "StorageReaderModule",
            defaultModuleRole: nil,
            runtimeRequirements: ModuleRuntimeRequirements(
                io: [
                    ModuleIORequirement(
                        requirementID: "storage.private-state",
                        kind: .storage,
                        access: .readWrite,
                        required: true
                    )
                ]
            )
        )
        let tempRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manifestURL = tempRoot.appendingPathComponent("StorageReader.json")
        try writeManifest(manifest, to: manifestURL)

        XCTAssertThrowsError(
            try ManifestLoader().loadManifests(resourceURLs: [manifestURL])
        ) { error in
            guard case let ManifestLoaderError.validationFailed(_, reason) = error else {
                return XCTFail("Expected validation failure, received \(error).")
            }
            XCTAssertTrue(reason.contains("storage.private-state"))
            XCTAssertTrue(reason.contains(Capability.storage.rawValue))
        }
    }

    func testRejectsUnsupportedManifestTemplateVersionJSON() throws {
        let rawManifest = """
        {
          "schemaVersion": "1.1",
          "manifestTemplateVersion": "2.0",
          "moduleID": "com.forsetti.module.invalid-template",
          "displayName": "Invalid Template",
          "moduleVersion": { "major": 1, "minor": 0, "patch": 0 },
          "moduleType": "service",
          "supportedPlatforms": ["iOS", "macOS"],
          "minForsettiVersion": { "major": 0, "minor": 1, "patch": 0 },
          "maxForsettiVersion": null,
          "capabilitiesRequested": [],
          "iapProductID": null,
          "entryPoint": "InvalidTemplateModule",
          "defaultModuleRole": null,
          "runtimeRequirements": {
            "io": [],
            "ui": null,
            "dataIsolation": { "mode": "private_to_module", "ownedStoreIDs": [], "requiredDefaultRoles": [] }
          }
        }
        """
        let tempRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let manifestURL = tempRoot.appendingPathComponent("InvalidTemplate.json")
        try Data(rawManifest.utf8).write(to: manifestURL)

        XCTAssertThrowsError(
            try ManifestLoader().loadManifests(resourceURLs: [manifestURL])
        ) { error in
            guard case let ManifestLoaderError.validationFailed(_, reason) = error else {
                return XCTFail("Expected validation failure, received \(error).")
            }
            XCTAssertTrue(reason.contains("invalid manifest JSON"))
        }
    }

    func testRejectsInvalidModuleIDAndEntryPointPatterns() throws {
        try assertValidationFailure(
            makeManifest(moduleID: "1.invalid.module"),
            contains: ["moduleID"]
        )
        try assertValidationFailure(
            makeManifest(moduleID: "com.forsetti.module.invalid", entryPoint: "Invalid Module"),
            contains: ["entryPoint"]
        )
    }

    func testRejectsDuplicateCapabilitiesAndVersionRangeMismatch() throws {
        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.duplicate-capabilities",
                capabilitiesRequested: [.storage, .storage]
            ),
            contains: ["capabilitiesRequested", "duplicates"]
        )

        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.invalid-version-range",
                minForsettiVersion: SemVer(major: 2, minor: 0, patch: 0),
                maxForsettiVersion: SemVer(major: 1, minor: 0, patch: 0)
            ),
            contains: ["maxForsettiVersion", "minForsettiVersion"]
        )
    }

    func testRejectsDuplicateRuntimeRequirementIDs() throws {
        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.duplicate-io",
                capabilitiesRequested: [.storage],
                runtimeRequirements: ModuleRuntimeRequirements(
                    io: [
                        ModuleIORequirement(
                            requirementID: "storage.state",
                            kind: .storage,
                            access: .readWrite,
                            required: true
                        ),
                        ModuleIORequirement(
                            requirementID: "storage.state",
                            kind: .storage,
                            access: .read,
                            required: false
                        )
                    ]
                )
            ),
            contains: ["Duplicate I/O requirementID", "storage.state"]
        )

        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.duplicate-ui",
                moduleType: .ui,
                capabilitiesRequested: [.toolbarItems],
                defaultModuleRole: .ui,
                runtimeRequirements: ModuleRuntimeRequirements(
                    ui: ModuleUIRequirements(toolbarItemIDs: ["action", "action"])
                )
            ),
            contains: ["toolbarItemIDs", "duplicates"]
        )
    }

    func testRejectsServiceUIRequirementsAndDefaultRoleMismatch() throws {
        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.service-ui-requirements",
                runtimeRequirements: ModuleRuntimeRequirements(
                    ui: ModuleUIRequirements(viewIDs: ["service.view"])
                )
            ),
            contains: ["service modules", "UI requirements"]
        )

        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.bad-default-role",
                moduleType: .ui,
                defaultModuleRole: .sharedDatabase
            ),
            contains: ["defaultModuleRole", "shared_database", "ui"]
        )

        try assertValidationFailure(
            makeManifest(
                moduleID: "com.forsetti.module.service-ui-role",
                defaultModuleRole: .ui
            ),
            contains: ["defaultModuleRole", "ui", "service"]
        )
    }

    func testStrictDirectoryValidationFailsForInvalidManifest() throws {
        let tempBundle = try TemporaryBundle()
        let manifestDirectory = tempBundle.bundleURL.appendingPathComponent("ForsettiManifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

        let invalidManifest = makeManifest(moduleID: "com.forsetti.module.invalid", entryPoint: "")
        let invalidManifestURL = manifestDirectory.appendingPathComponent("Invalid.json")
        try writeManifest(invalidManifest, to: invalidManifestURL)

        let loader = ManifestLoader()

        XCTAssertThrowsError(
            try loader.loadManifests(bundle: tempBundle.bundle, subdirectory: "ForsettiManifests")
        ) { error in
            guard case let ManifestLoaderError.validationFailed(file, reason) = error else {
                return XCTFail("Expected ManifestLoaderError.validationFailed, received \(error).")
            }

            XCTAssertEqual(file, "Invalid.json")
            XCTAssertTrue(reason.contains("entryPoint"))
        }
    }

    func testFallbackDiscoveryIgnoresNonManifestJSON() throws {
        let tempBundle = try TemporaryBundle()

        let configURL = tempBundle.bundleURL.appendingPathComponent("config.json")
        try Data("{\"featureFlag\":true}".utf8).write(to: configURL)

        let nestedDirectory = tempBundle.bundleURL.appendingPathComponent("Payload", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let manifestURL = nestedDirectory.appendingPathComponent("Example.json")
        try writeManifest(
            makeManifest(moduleID: "com.forsetti.module.example"),
            to: manifestURL
        )

        let manifests = try ManifestLoader().loadManifests(
            bundle: tempBundle.bundle,
            subdirectory: "ForsettiManifests"
        )

        XCTAssertEqual(manifests.count, 1)
        XCTAssertNotNil(manifests["com.forsetti.module.example"])
    }

    func testLoadManifestsDetectsDuplicateModuleIDs() throws {
        let tempRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let firstURL = tempRoot.appendingPathComponent("One.json")
        let secondURL = tempRoot.appendingPathComponent("Two.json")

        try writeManifest(
            makeManifest(moduleID: "com.forsetti.module.duplicate", entryPoint: "One"),
            to: firstURL
        )
        try writeManifest(
            makeManifest(moduleID: "com.forsetti.module.duplicate", entryPoint: "Two"),
            to: secondURL
        )

        XCTAssertThrowsError(
            try ManifestLoader().loadManifests(resourceURLs: [firstURL, secondURL])
        ) { error in
            guard case let ManifestLoaderError.duplicateModuleID(moduleID) = error else {
                return XCTFail("Expected duplicateModuleID error, received \(error).")
            }
            XCTAssertEqual(moduleID, "com.forsetti.module.duplicate")
        }
    }

    private func makeManifest(
        moduleID: String,
        entryPoint: String = "TestModule",
        moduleType: ModuleType = .service,
        minForsettiVersion: SemVer = ForsettiVersion.current,
        maxForsettiVersion: SemVer? = nil,
        capabilitiesRequested: [Capability] = [],
        defaultModuleRole: DefaultModuleRole? = nil,
        runtimeRequirements: ModuleRuntimeRequirements = .safeLegacyDefaults
    ) -> ModuleManifest {
        ModuleManifest(
            schemaVersion: ModuleManifest.currentSchemaVersion,
            manifestTemplateVersion: .current,
            moduleID: moduleID,
            displayName: "Test Module",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: moduleType,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: minForsettiVersion,
            maxForsettiVersion: maxForsettiVersion,
            capabilitiesRequested: capabilitiesRequested,
            iapProductID: nil,
            entryPoint: entryPoint,
            defaultModuleRole: defaultModuleRole,
            runtimeRequirements: runtimeRequirements
        )
    }

    private func assertValidationFailure(_ manifest: ModuleManifest, contains expectedSnippets: [String]) throws {
        let tempRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let manifestURL = tempRoot.appendingPathComponent("Invalid.json")
        try writeManifest(manifest, to: manifestURL)

        XCTAssertThrowsError(
            try ManifestLoader().loadManifests(resourceURLs: [manifestURL])
        ) { error in
            guard case let ManifestLoaderError.validationFailed(_, reason) = error else {
                return XCTFail("Expected validation failure, received \(error).")
            }
            for snippet in expectedSnippets {
                XCTAssertTrue(reason.contains(snippet), "Expected '\(reason)' to contain '\(snippet)'.")
            }
        }
    }

    private func writeManifest(_ manifest: ModuleManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForsettiManifestLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class TemporaryBundle {
    let rootURL: URL
    let bundleURL: URL
    let bundle: Bundle

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForsettiBundleTests-\(UUID().uuidString)", isDirectory: true)
        bundleURL = rootURL.appendingPathComponent("Test.bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(at: bundleURL.appendingPathComponent("Info.plist"))

        guard let resolvedBundle = Bundle(url: bundleURL) else {
            throw NSError(
                domain: "ManifestLoaderTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to initialize temporary test bundle."]
            )
        }

        bundle = resolvedBundle
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeInfoPlist(at url: URL) throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.forsetti.tests.tempbundle",
            "CFBundleName": "TempBundle",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }
}
