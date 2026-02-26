import XCTest
@testable import ForsettiCore
@testable import ForsettiModulesExample
@testable import ForsettiHostTemplate

final class ForsettiHostControllerTests: XCTestCase {
    @MainActor
    func testBootLoadsServiceAndUIModuleLists() async {
        let controller = makeController(
            unlockedModules: [
                "com.forsetti.module.example-service"
            ],
            unlockedProducts: [
                "com.forsetti.iap.example-ui"
            ]
        )

        await controller.boot(restoreActivationState: false)

        XCTAssertEqual(controller.serviceModules.count, 1)
        XCTAssertEqual(controller.uiModules.count, 1)
        XCTAssertTrue(controller.errorMessage == nil)
    }

    @MainActor
    func testServiceToggleAndUIModuleSelection() async {
        let controller = makeController(
            unlockedModules: [
                "com.forsetti.module.example-service"
            ],
            unlockedProducts: [
                "com.forsetti.iap.example-ui"
            ]
        )

        await controller.boot(restoreActivationState: false)

        XCTAssertTrue(controller.enabledServiceModuleIDs.contains("com.forsetti.module.example-service"))
        XCTAssertTrue(controller.enabledUIModuleIDs.contains("com.forsetti.module.example-ui"))

        await controller.selectUIModule(moduleID: "com.forsetti.module.example-ui")
        XCTAssertEqual(controller.activeUIModuleID, "com.forsetti.module.example-ui")
        XCTAssertEqual(controller.selectedModuleID, "com.forsetti.module.example-ui")

        await controller.selectUIModule(moduleID: nil)
        XCTAssertNil(controller.selectedModuleID)
        XCTAssertTrue(controller.enabledUIModuleIDs.contains("com.forsetti.module.example-ui"))

        controller.shutdown()
    }

    @MainActor
    func testLockedModuleCannotActivate() async {
        let controller = makeController(
            unlockedModules: [
                "com.forsetti.module.example-service"
            ]
        )

        await controller.boot(restoreActivationState: false)
        await controller.selectUIModule(moduleID: "com.forsetti.module.example-ui")

        XCTAssertNil(controller.activeUIModuleID)
        XCTAssertFalse(controller.enabledUIModuleIDs.contains("com.forsetti.module.example-ui"))
        XCTAssertNotNil(controller.errorMessage)

        let uiModule = controller.uiModules.first { $0.moduleID == "com.forsetti.module.example-ui" }
        XCTAssertNotNil(uiModule)
        XCTAssertEqual(uiModule?.availability, .locked(productID: "com.forsetti.iap.example-ui"))

        controller.shutdown()
    }

    @MainActor
    func testRestorePurchasesUnlocksUIModule() async {
        let registry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: registry)

        let entitlements = StaticEntitlementProvider(
            unlockedModuleIDs: ["com.forsetti.module.example-service"],
            unlockedProductIDs: []
        )
        let runtime = ForsettiRuntime(
            platform: .macOS,
            services: ForsettiServiceContainer(),
            entitlementProvider: entitlements,
            activationStore: InMemoryActivationStore(),
            moduleRegistry: registry
        )
        let controller = ForsettiHostController(
            runtime: runtime,
            entitlementProvider: entitlements,
            manifestsBundle: ExampleModuleResources.bundle
        )

        await controller.boot(restoreActivationState: false)
        await controller.selectUIModule(moduleID: "com.forsetti.module.example-ui")
        XCTAssertFalse(controller.enabledUIModuleIDs.contains("com.forsetti.module.example-ui"))

        entitlements.setUnlockedProducts(["com.forsetti.iap.example-ui"])
        await controller.restorePurchases()

        await controller.selectUIModule(moduleID: "com.forsetti.module.example-ui")
        XCTAssertEqual(controller.activeUIModuleID, "com.forsetti.module.example-ui")
        XCTAssertTrue(controller.enabledUIModuleIDs.contains("com.forsetti.module.example-ui"))
        XCTAssertNotNil(controller.runtime.moduleManager.manifestsByID["com.forsetti.module.example-ui"])

        controller.shutdown()
    }

    @MainActor
    func testToolbarRouteActionUsesHostOverlayRouterResolution() async {
        let registry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: registry)

        let controller = ForsettiHostTemplateBootstrap.makeController(
            manifestsBundle: ExampleModuleResources.bundle,
            moduleRegistry: registry,
            entitlementProvider: StaticEntitlementProvider(
                unlockedModuleIDs: ["com.forsetti.module.example-service"],
                unlockedProductIDs: ["com.forsetti.iap.example-ui"]
            ),
            activationStore: InMemoryActivationStore()
        )

        await controller.boot(restoreActivationState: false)
        await controller.selectUIModule(moduleID: "com.forsetti.module.example-ui")

        controller.handleToolbarAction(.openOverlay(routeID: "example-overlay"))

        XCTAssertEqual(
            controller.lastToolbarActionDescription,
            "Route 'example-overlay' resolved to overlay slot 'overlay.main'."
        )

        controller.shutdown()
    }

    @MainActor
    private func makeController(
        unlockedModules: Set<String>,
        unlockedProducts: Set<String> = []
    ) -> ForsettiHostController {
        let registry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: registry)

        let entitlements = StaticEntitlementProvider(
            unlockedModuleIDs: unlockedModules,
            unlockedProductIDs: unlockedProducts
        )
        let runtime = ForsettiRuntime(
            platform: .macOS,
            services: ForsettiServiceContainer(),
            entitlementProvider: entitlements,
            activationStore: InMemoryActivationStore(),
            moduleRegistry: registry
        )

        return ForsettiHostController(
            runtime: runtime,
            entitlementProvider: entitlements,
            manifestsBundle: ExampleModuleResources.bundle
        )
    }
}

private final class InMemoryActivationStore: ActivationStore, @unchecked Sendable {
    private var state = ActivationState()

    func loadState() -> ActivationState {
        state
    }

    func saveState(_ state: ActivationState) {
        self.state = state
    }
}
