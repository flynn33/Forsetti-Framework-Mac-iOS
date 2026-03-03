//___FILEHEADER___

import SwiftUI

#if canImport(ForsettiHostTemplate) && canImport(ForsettiModulesExample) && canImport(ForsettiCore) && canImport(ForsettiPlatform)
import ForsettiCore
import ForsettiHostTemplate
import ForsettiModulesExample
import ForsettiPlatform

@MainActor
final class ForsettiTemplateContainer: ObservableObject {
    let controller: ForsettiHostController
    let injectionRegistry: ForsettiViewInjectionRegistry

    init() {
        // STEP 1: Create a module registry and register your module factories.
        // Each entry maps a manifest "entryPoint" string to a factory closure
        // that returns a ForsettiModule (or ForsettiAppModule / ForsettiUIModule).
        let registry = ModuleRegistry()
        ExampleModuleRegistry.registerAll(into: registry)

        // STEP 2: Build the host controller via ForsettiHostTemplateBootstrap.
        // This wires up the runtime, services, entitlement provider, and manifest loader.
        //
        // The default provider uses StoreKit 2 on iOS and a static allowlist on macOS.
        // For debug/test builds, swap to the debug provider to bypass StoreKit entirely:
        //   entitlementProvider: ForsettiEntitlementProviderFactory.makeDebug()
        controller = ForsettiHostTemplateBootstrap.makeController(
            manifestsBundle: ExampleModuleResources.bundle,
            moduleRegistry: registry,
            entitlementProvider: ForsettiEntitlementProviderFactory.makeDefault(
                macOSUnlockedProductIDs: ["com.forsetti.iap.example-ui"]
            )
        )

        // STEP 3: (Optional) Register view injections for modules that request
        // the "viewInjection" capability. Each viewID maps to a SwiftUI view builder.
        injectionRegistry = ForsettiViewInjectionRegistry()
        registerDefaultInjections()
    }

    private func registerDefaultInjections() {
        injectionRegistry.register(viewID: "example-banner") {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                Text("Forsetti injection active")
                    .font(.headline)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        injectionRegistry.register(viewID: "example-overlay-view") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overlay Example")
                    .font(.title2.bold())
                Text("This view came from a Forsetti UI module overlay route.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct ForsettiTemplateRootView: View {
    @StateObject private var container = ForsettiTemplateContainer()

    var body: some View {
        ForsettiHostRootView(
            controller: container.controller,
            injectionRegistry: container.injectionRegistry,
            // DEPLOYMENT PATTERN CONTROL:
            // false = Production (Pattern A/B): framework runs silently, users see only your module UI.
            // true  = Development (Pattern C/D): framework controls visible for module switching.
            // See README.md section 4b for deployment pattern details.
            showDeveloperControls: true
        )
    }
}
#else
struct ForsettiTemplateRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Forsetti Template Ready")
                .font(.title2.bold())

            Text("Add the Forsetti package products to this app target to enable the framework host UI.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Required products: ForsettiCore, ForsettiPlatform, ForsettiModulesExample, ForsettiHostTemplate")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
#endif
