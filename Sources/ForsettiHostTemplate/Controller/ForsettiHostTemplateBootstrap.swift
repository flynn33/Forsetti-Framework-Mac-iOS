import Foundation
import ForsettiCore
import ForsettiPlatform

@MainActor
public enum ForsettiHostTemplateBootstrap {
    public static func makeController(
        manifestsBundle: Bundle,
        moduleRegistry: ModuleRegistry,
        entitlementProvider: any ForsettiEntitlementProvider = ForsettiEntitlementProviderFactory.makeDefault(),
        capabilityPolicy: any CapabilityPolicy = AllowAllCapabilityPolicy(),
        activationStore: any ActivationStore = UserDefaultsActivationStore(),
        manifestsSubdirectory: String = "ForsettiManifests",
        slotCatalog: [String] = SlotCatalog.all
    ) -> ForsettiHostController {
        let platformServices = DefaultForsettiPlatformServices()

        let runtime = ForsettiRuntime(
            services: platformServices.container,
            entitlementProvider: entitlementProvider,
            capabilityPolicy: capabilityPolicy,
            activationStore: activationStore,
            moduleRegistry: moduleRegistry
        )

        return ForsettiHostController(
            runtime: runtime,
            entitlementProvider: entitlementProvider,
            manifestsBundle: manifestsBundle,
            manifestsSubdirectory: manifestsSubdirectory,
            slotCatalog: slotCatalog
        )
    }
}
