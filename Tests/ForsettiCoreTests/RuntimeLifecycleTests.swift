import Foundation
import XCTest
@testable import ForsettiCore
@testable import ForsettiModulesExample

final class RuntimeLifecycleTests: XCTestCase {
    @MainActor
    func testRuntimeShutdownDoesNotClearPersistedActivationState() async throws {
        let serviceModuleID = "com.forsetti.module.example-service"
        let uiModuleID = "com.forsetti.module.example-ui"
        let uiProductID = "com.forsetti.iap.example-ui"

        let activationStore = SharedInMemoryActivationStore()
        let entitlementProvider = StaticEntitlementProvider(
            unlockedModuleIDs: [serviceModuleID],
            unlockedProductIDs: [uiProductID]
        )

        let firstRegistry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: firstRegistry)

        let firstRuntime = ForsettiRuntime(
            platform: .macOS,
            services: ForsettiServiceContainer(),
            entitlementProvider: entitlementProvider,
            activationStore: activationStore,
            moduleRegistry: firstRegistry
        )

        _ = try await firstRuntime.boot(
            bundle: ExampleModuleResources.bundle,
            restoreActivationState: false
        )
        try await firstRuntime.moduleManager.activateModule(moduleID: serviceModuleID)
        try await firstRuntime.moduleManager.activateModule(moduleID: uiModuleID)
        firstRuntime.shutdown()

        let storedStateAfterShutdown = activationStore.loadState()
        XCTAssertTrue(storedStateAfterShutdown.enabledServiceModuleIDs.contains(serviceModuleID))
        XCTAssertTrue(storedStateAfterShutdown.enabledUIModuleIDs.contains(uiModuleID))
        XCTAssertEqual(storedStateAfterShutdown.activeUIModuleID, uiModuleID)

        let secondRegistry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: secondRegistry)

        let secondRuntime = ForsettiRuntime(
            platform: .macOS,
            services: ForsettiServiceContainer(),
            entitlementProvider: entitlementProvider,
            activationStore: activationStore,
            moduleRegistry: secondRegistry
        )

        _ = try await secondRuntime.boot(bundle: ExampleModuleResources.bundle, restoreActivationState: true)

        XCTAssertTrue(secondRuntime.moduleManager.enabledServiceModuleIDs.contains(serviceModuleID))
        XCTAssertEqual(secondRuntime.moduleManager.activeUIModuleID, uiModuleID)

        secondRuntime.shutdown()
    }

    @MainActor
    func testModuleTypeMismatchDoesNotStartModule() async throws {
        MismatchServiceModule.startInvocationCount = 0

        let testBundle = try RuntimeTestBundle()
        let manifestsDirectory = testBundle.bundleURL.appendingPathComponent("ForsettiManifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestsDirectory, withIntermediateDirectories: true)

        let mismatchManifest = ModuleManifest(
            schemaVersion: ModuleManifest.supportedSchemaVersion,
            moduleID: "com.forsetti.module.mismatch-ui",
            displayName: "Mismatch UI",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: .ui,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: ForsettiVersion.current,
            maxForsettiVersion: nil,
            capabilitiesRequested: [],
            iapProductID: nil,
            entryPoint: "MismatchServiceModule"
        )

        let manifestURL = manifestsDirectory.appendingPathComponent("Mismatch.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(mismatchManifest).write(to: manifestURL, options: .atomic)

        let registry = ModuleRegistry()
        registry.register(entryPoint: "MismatchServiceModule") { MismatchServiceModule() }

        let manager = ModuleManager(
            manifestLoader: ManifestLoader(),
            moduleRegistry: registry,
            compatibilityChecker: CompatibilityChecker(
                runtimePlatform: .macOS,
                forsettiVersion: ForsettiVersion.current,
                capabilityPolicy: AllowAllCapabilityPolicy()
            ),
            activationStore: SharedInMemoryActivationStore(),
            entitlementProvider: StaticEntitlementProvider(),
            uiSurfaceManager: UISurfaceManager(),
            context: ForsettiContext(
                eventBus: InMemoryEventBus(),
                services: ForsettiServiceContainer(),
                logger: ConsoleForsettiLogger(),
                router: NoopOverlayRouter()
            )
        )

        _ = try manager.discoverModules(bundle: testBundle.bundle, subdirectory: "ForsettiManifests")

        do {
            try await manager.activateModule(moduleID: mismatchManifest.moduleID)
            XCTFail("Expected notUIModule error.")
        } catch let error as ModuleManagerError {
            guard case let .notUIModule(moduleID) = error else {
                return XCTFail("Expected notUIModule error, received \(error).")
            }
            XCTAssertEqual(moduleID, mismatchManifest.moduleID)
        } catch {
            XCTFail("Expected ModuleManagerError.notUIModule, received \(error).")
        }

        XCTAssertEqual(MismatchServiceModule.startInvocationCount, 0)
    }

    @MainActor
    func testMultipleUIModulesCanRemainActiveConcurrently() async throws {
        let moduleAID = "com.forsetti.module.ui.a"
        let moduleBID = "com.forsetti.module.ui.b"

        let testBundle = try RuntimeTestBundle()
        let manifestsDirectory = testBundle.bundleURL.appendingPathComponent("ForsettiManifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestsDirectory, withIntermediateDirectories: true)

        let manifestA = ModuleManifest(
            schemaVersion: ModuleManifest.supportedSchemaVersion,
            moduleID: moduleAID,
            displayName: "UI A",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: .ui,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: ForsettiVersion.current,
            maxForsettiVersion: nil,
            capabilitiesRequested: [.toolbarItems],
            iapProductID: nil,
            entryPoint: "TestUIModuleA"
        )

        let manifestB = ModuleManifest(
            schemaVersion: ModuleManifest.supportedSchemaVersion,
            moduleID: moduleBID,
            displayName: "UI B",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: .ui,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: ForsettiVersion.current,
            maxForsettiVersion: nil,
            capabilitiesRequested: [.toolbarItems],
            iapProductID: nil,
            entryPoint: "TestUIModuleB"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifestA).write(
            to: manifestsDirectory.appendingPathComponent("UIA.json"),
            options: .atomic
        )
        try encoder.encode(manifestB).write(
            to: manifestsDirectory.appendingPathComponent("UIB.json"),
            options: .atomic
        )

        let registry = ModuleRegistry()
        registry.register(entryPoint: "TestUIModuleA") { TestUIModuleA() }
        registry.register(entryPoint: "TestUIModuleB") { TestUIModuleB() }

        let manager = ModuleManager(
            manifestLoader: ManifestLoader(),
            moduleRegistry: registry,
            compatibilityChecker: CompatibilityChecker(
                runtimePlatform: .macOS,
                forsettiVersion: ForsettiVersion.current,
                capabilityPolicy: AllowAllCapabilityPolicy()
            ),
            activationStore: SharedInMemoryActivationStore(),
            entitlementProvider: StaticEntitlementProvider(),
            uiSurfaceManager: UISurfaceManager(),
            context: ForsettiContext(
                eventBus: InMemoryEventBus(),
                services: ForsettiServiceContainer(),
                logger: ConsoleForsettiLogger(),
                router: NoopOverlayRouter()
            )
        )

        _ = try manager.discoverModules(bundle: testBundle.bundle, subdirectory: "ForsettiManifests")

        try await manager.activateModule(moduleID: moduleAID)
        try await manager.activateModule(moduleID: moduleBID)

        XCTAssertEqual(manager.enabledUIModuleIDs, Set([moduleAID, moduleBID]))
        XCTAssertTrue(manager.isActive(moduleID: moduleAID))
        XCTAssertTrue(manager.isActive(moduleID: moduleBID))
        XCTAssertEqual(manager.activeUIModuleID, moduleAID)

        try manager.setSelectedUIModule(moduleID: moduleBID)
        XCTAssertEqual(manager.activeUIModuleID, moduleBID)

        try manager.deactivateModule(moduleID: moduleBID)
        XCTAssertEqual(manager.enabledUIModuleIDs, Set([moduleAID]))
        XCTAssertEqual(manager.activeUIModuleID, moduleAID)
    }
}

private final class SharedInMemoryActivationStore: ActivationStore, @unchecked Sendable {
    private var state = ActivationState()

    func loadState() -> ActivationState {
        state
    }

    func saveState(_ state: ActivationState) {
        self.state = state
    }
}

private final class MismatchServiceModule: ForsettiModule {
    static var startInvocationCount = 0

    let descriptor = ModuleDescriptor(
        moduleID: "com.forsetti.module.mismatch-service",
        displayName: "Mismatch Service",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.forsetti.module.mismatch-service",
        displayName: "Mismatch Service",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        maxForsettiVersion: nil,
        capabilitiesRequested: [],
        iapProductID: nil,
        entryPoint: "MismatchServiceModule"
    )

    func start(context _: ForsettiContext) throws {
        Self.startInvocationCount += 1
    }

    func stop(context _: ForsettiContext) {}
}

private final class TestUIModuleA: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.forsetti.module.ui.a",
        displayName: "UI A",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.forsetti.module.ui.a",
        displayName: "UI A",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        maxForsettiVersion: nil,
        capabilitiesRequested: [.toolbarItems],
        iapProductID: nil,
        entryPoint: "TestUIModuleA"
    )

    let uiContributions = UIContributions(
        toolbarItems: [
            ToolbarItemDescriptor(
                itemID: "ui.a.action",
                title: "A Action",
                action: .publishEvent(type: "ui.a.action", payload: nil)
            )
        ]
    )

    func start(context _: ForsettiContext) throws {}
    func stop(context _: ForsettiContext) {}
}

private final class TestUIModuleB: ForsettiUIModule {
    let descriptor = ModuleDescriptor(
        moduleID: "com.forsetti.module.ui.b",
        displayName: "UI B",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.forsetti.module.ui.b",
        displayName: "UI B",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        maxForsettiVersion: nil,
        capabilitiesRequested: [.toolbarItems],
        iapProductID: nil,
        entryPoint: "TestUIModuleB"
    )

    let uiContributions = UIContributions(
        toolbarItems: [
            ToolbarItemDescriptor(
                itemID: "ui.b.action",
                title: "B Action",
                action: .publishEvent(type: "ui.b.action", payload: nil)
            )
        ]
    )

    func start(context _: ForsettiContext) throws {}
    func stop(context _: ForsettiContext) {}
}

private final class RuntimeTestBundle {
    let rootURL: URL
    let bundleURL: URL
    let bundle: Bundle

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForsettiRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        bundleURL = rootURL.appendingPathComponent("RuntimeTests.bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Self.writeInfoPlist(at: bundleURL.appendingPathComponent("Info.plist"))

        guard let resolvedBundle = Bundle(url: bundleURL) else {
            throw NSError(
                domain: "RuntimeLifecycleTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to initialize temporary runtime test bundle."]
            )
        }

        bundle = resolvedBundle
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeInfoPlist(at url: URL) throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.forsetti.tests.runtimebundle",
            "CFBundleName": "RuntimeTests",
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
