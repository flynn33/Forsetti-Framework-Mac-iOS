//___FILEHEADER___

import SwiftUI

#if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
import ForsettiCore
import ForsettiHostTemplate
import ForsettiPlatform
#endif

struct ContentView: View {
    @StateObject private var bootstrap = ___PACKAGENAME:identifier___ForsettiBootstrap()

    var body: some View {
        #if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
        Group {
            switch ___PACKAGENAME:identifier___DeploymentMode.current {
            case .development:
                ForsettiHostRootView(
                    controller: bootstrap.controller,
                    injectionRegistry: bootstrap.injectionRegistry,
                    showDeveloperControls: true
                )
            case .production:
                ___PACKAGENAME:identifier___AppModuleView()
                    .task {
                        await bootstrap.bootForProduction()
                    }
            }
        }
        #else
        MissingForsettiProductsView()
        #endif
    }
}

#Preview {
    ContentView()
}

private struct MissingForsettiProductsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Forsetti Starter Template Installed")
                .font(.title2.bold())

            Text("Add Forsetti package products to this app target to enable runtime bootstrapping.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Required products: ForsettiCore, ForsettiPlatform, ForsettiHostTemplate")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
