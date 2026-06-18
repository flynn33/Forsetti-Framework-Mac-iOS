import Foundation
import XCTest
@testable import ForsettiCore

@MainActor
final class ModuleRegistrationStoreTests: XCTestCase {
    func testDiscoveryCreatesRegistrationRecord() throws {
        let store = InMemoryModuleRegistrationStore()
        let manager = try makeManager(registrationStore: store)
        let testBundle = try RuntimeTestBundle()
        try testBundle.writeManifest(RegistrationServiceModule.moduleManifest, fileName: "RegistrationService.json")

        _ = try manager.discoverModules(bundle: testBundle.bundle, subdirectory: "ForsettiManifests")

        let record = try XCTUnwrap(store.loadRecord(moduleID: RegistrationServiceModule.moduleID))
        XCTAssertEqual(record.moduleID, RegistrationServiceModule.moduleID)
        XCTAssertEqual(record.entryPoint, RegistrationServiceModule.entryPoint)
        XCTAssertEqual(record.runtimeRequirements, RegistrationServiceModule.moduleManifest.runtimeRequirements)
    }

    func testActivationFailsWhenRegistrationRecordIsMissing() async throws {
        let store = InMemoryModuleRegistrationStore()
        let manager = try makeDiscoveredManager(registrationStore: store)
        try store.removeRecord(moduleID: RegistrationServiceModule.moduleID)

        do {
            try await manager.activateModule(moduleID: RegistrationServiceModule.moduleID)
            XCTFail("Expected registrationMissing.")
        } catch {
            guard case let ModuleManagerError.registrationMissing(moduleID) = error else {
                return XCTFail("Expected registrationMissing, received \(error).")
            }
            XCTAssertEqual(moduleID, RegistrationServiceModule.moduleID)
        }
    }

    func testActivationFailsWhenRegistrationRecordIsStale() async throws {
        let store = InMemoryModuleRegistrationStore()
        let manager = try makeDiscoveredManager(registrationStore: store)
        let record = try XCTUnwrap(store.loadRecord(moduleID: RegistrationServiceModule.moduleID))
        let staleRecord = ModuleRegistrationRecord(
            moduleID: record.moduleID,
            displayName: record.displayName,
            moduleVersion: record.moduleVersion,
            moduleType: record.moduleType,
            entryPoint: record.entryPoint,
            schemaVersion: record.schemaVersion,
            manifestTemplateVersion: record.manifestTemplateVersion,
            manifestHash: "stale",
            supportedPlatforms: record.supportedPlatforms,
            capabilitiesRequested: record.capabilitiesRequested,
            defaultModuleRole: record.defaultModuleRole,
            runtimeRequirements: record.runtimeRequirements,
            registeredAt: record.registeredAt
        )
        try store.saveRecord(staleRecord)

        do {
            try await manager.activateModule(moduleID: RegistrationServiceModule.moduleID)
            XCTFail("Expected registrationMismatch.")
        } catch {
            guard case let ModuleManagerError.registrationMismatch(moduleID, reason) = error else {
                return XCTFail("Expected registrationMismatch, received \(error).")
            }
            XCTAssertEqual(moduleID, RegistrationServiceModule.moduleID)
            XCTAssertTrue(reason.contains("stale"))
        }
    }

    func testUserDefaultsRegistrationStorePersistsRecords() throws {
        let suiteName = "ForsettiModuleRegistrationStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstStore = UserDefaultsModuleRegistrationStore(defaults: defaults)
        let record = try ModuleRegistrationRecord.make(manifest: RegistrationServiceModule.moduleManifest)
        try firstStore.saveRecord(record)

        let secondStore = UserDefaultsModuleRegistrationStore(defaults: defaults)
        let persistedRecord = try XCTUnwrap(secondStore.loadRecord(moduleID: RegistrationServiceModule.moduleID))

        XCTAssertEqual(persistedRecord, record)
    }

    private func makeDiscoveredManager(registrationStore: InMemoryModuleRegistrationStore) throws -> ModuleManager {
        let manager = try makeManager(registrationStore: registrationStore)
        let testBundle = try RuntimeTestBundle()
        try testBundle.writeManifest(RegistrationServiceModule.moduleManifest, fileName: "RegistrationService.json")
        _ = try manager.discoverModules(bundle: testBundle.bundle, subdirectory: "ForsettiManifests")
        return manager
    }

    private func makeManager(registrationStore: any ModuleRegistrationStore) throws -> ModuleManager {
        let registry = ModuleRegistry()
        try registry.register(entryPoint: RegistrationServiceModule.entryPoint) {
            RegistrationServiceModule()
        }

        return ModuleManager(
            manifestLoader: ManifestLoader(),
            moduleRegistry: registry,
            compatibilityChecker: CompatibilityChecker(
                runtimePlatform: .macOS,
                forsettiVersion: ForsettiVersion.current,
                capabilityPolicy: AllowAllCapabilityPolicy()
            ),
            activationStore: SharedInMemoryActivationStore(),
            registrationStore: registrationStore,
            entitlementProvider: StaticEntitlementProvider(),
            uiSurfaceManager: UISurfaceManager(),
            context: ForsettiContext(
                eventBus: InMemoryEventBus(),
                services: ForsettiServiceContainer(),
                logger: ConsoleForsettiLogger(),
                router: NoopOverlayRouter()
            )
        )
    }
}

private final class RegistrationServiceModule: ForsettiModule {
    static let moduleID = "com.forsetti.module.registration-service"
    static let entryPoint = "RegistrationServiceModule"
    static let moduleManifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: moduleID,
        displayName: "Registration Service",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        capabilitiesRequested: [],
        entryPoint: entryPoint,
        runtimeRequirements: ModuleRuntimeRequirements()
    )

    let descriptor = ModuleDescriptor(
        moduleID: moduleID,
        displayName: "Registration Service",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service
    )

    let manifest = RegistrationServiceModule.moduleManifest

    func start(context _: any ForsettiModuleContext) throws {}
    func stop(context _: any ForsettiModuleContext) {}
}
