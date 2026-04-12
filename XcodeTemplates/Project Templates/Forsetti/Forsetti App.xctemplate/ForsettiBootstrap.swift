//___FILEHEADER___

#if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
import Foundation
import SwiftUI
import ForsettiCore
import ForsettiHostTemplate
import ForsettiPlatform

@MainActor
final class ___PACKAGENAME:identifier___ForsettiBootstrap: ObservableObject {
    let controller: ForsettiHostController
    let injectionRegistry: ForsettiViewInjectionRegistry

    init() {
        // Previous template behavior used ExampleModuleRegistry from ForsettiModulesExample.
        // New template behavior registers an app-owned starter module by default.
        let registry = ModuleRegistry()
        ___PACKAGENAME:identifier___ModuleRegistry.registerAll(into: registry)

        controller = ForsettiHostTemplateBootstrap.makeController(
            manifestsBundle: .main,
            moduleRegistry: registry,
            entitlementProvider: ForsettiEntitlementProviderFactory.makeDefault(),
            manifestsSubdirectory: "ForsettiManifests"
        )

        // View injection maps the starter module's workspace view ID to the app-owned SwiftUI view.
        injectionRegistry = ForsettiViewInjectionRegistry()
        injectionRegistry.register(viewID: ___PACKAGENAME:identifier___AppModule.Constants.primaryViewID) {
            ___PACKAGENAME:identifier___AppModuleView()
        }
    }

    func bootForProduction() async {
        await controller.bootIfNeeded()
        await controller.openModule(moduleID: ___PACKAGENAME:identifier___AppModule.Constants.moduleID)
    }
}
#else
import Foundation

@MainActor
final class ___PACKAGENAME:identifier___ForsettiBootstrap: ObservableObject {
    func bootForProduction() async {}
}
#endif
