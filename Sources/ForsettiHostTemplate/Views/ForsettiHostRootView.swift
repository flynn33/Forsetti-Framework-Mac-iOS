import SwiftUI
import ForsettiCore

public struct ForsettiHostRootView: View {
    @ObservedObject private var controller: ForsettiHostController
    @ObservedObject private var uiSurfaceManager: UISurfaceManager
    private let injectionRegistry: ForsettiViewInjectionRegistry

    public init(
        controller: ForsettiHostController,
        injectionRegistry: ForsettiViewInjectionRegistry = ForsettiViewInjectionRegistry()
    ) {
        self.controller = controller
        uiSurfaceManager = controller.runtime.uiSurfaceManager
        self.injectionRegistry = injectionRegistry
    }

    public var body: some View {
        NavigationStack {
            List {
                moduleControlSection
                toolbarSection
                overlaySchemaSection
                injectionSlotsSection
                themeSection
            }
            .navigationTitle("Forsetti Host")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ForEach(uiSurfaceManager.toolbarItems, id: \.itemID) { item in
                        Button {
                            controller.handleToolbarAction(item.action)
                        } label: {
                            if let systemImageName = item.systemImageName {
                                Label(item.title, systemImage: systemImageName)
                            } else {
                                Text(item.title)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await controller.bootIfNeeded()
        }
        .refreshable {
            await controller.refreshModuleState()
        }
        .alert(
            "Forsetti Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        controller.clearError()
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    controller.clearError()
                }
            },
            message: {
                Text(controller.errorMessage ?? "Unknown error")
            }
        )
    }

    private var moduleControlSection: some View {
        Section("Module Activation") {
            if controller.serviceModules.isEmpty, controller.uiModules.isEmpty {
                Text("No modules discovered")
                    .foregroundStyle(.secondary)
            }

            if !controller.serviceModules.isEmpty {
                Text("Service Modules")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(controller.serviceModules) { module in
                    ServiceModuleRow(module: module) { isEnabled in
                        Task {
                            await controller.setServiceModuleEnabled(moduleID: module.moduleID, isEnabled: isEnabled)
                        }
                    }
                }
            }

            if !controller.uiModules.isEmpty {
                Text("UI Module (Single Active)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await controller.selectUIModule(moduleID: nil)
                    }
                } label: {
                    HStack {
                        Image(systemName: controller.activeUIModuleID == nil ? "largecircle.fill.circle" : "circle")
                        Text("None")
                    }
                }

                ForEach(controller.uiModules) { module in
                    UIModuleRow(module: module) {
                        Task {
                            await controller.selectUIModule(moduleID: module.moduleID)
                        }
                    }
                }
            }

            Button("Refresh Entitlements") {
                Task {
                    await controller.refreshEntitlements()
                }
            }

            if hasPurchasableModules {
                Button("Restore Purchases") {
                    Task {
                        await controller.restorePurchases()
                    }
                }
            }

            if let lastAction = controller.lastToolbarActionDescription {
                Text("Last toolbar action: \(lastAction)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var toolbarSection: some View {
        Section("Toolbar Items") {
            if uiSurfaceManager.toolbarItems.isEmpty {
                Text("No active toolbar contributions")
                    .foregroundStyle(.secondary)
            }

            ForEach(uiSurfaceManager.toolbarItems, id: \.itemID) { item in
                Button {
                    controller.handleToolbarAction(item.action)
                } label: {
                    HStack {
                        if let systemImageName = item.systemImageName {
                            Image(systemName: systemImageName)
                                .frame(width: 24)
                        }
                        Text(item.title)
                        Spacer()
                        Text(toolbarActionText(item.action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var overlaySchemaSection: some View {
        Section("Overlay Schema") {
            if let schema = uiSurfaceManager.overlaySchema {
                Text("Schema: \(schema.schemaID)")
                    .font(.subheadline)

                if schema.pointers.isEmpty {
                    Text("No pointers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(schema.pointers, id: \.pointerID) { pointer in
                        HStack {
                            Text(pointer.label)
                            Spacer()
                            Text(pointer.pointerID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if schema.routes.isEmpty {
                    Text("No routes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(schema.routes, id: \.routeID) { route in
                        HStack {
                            Text(route.path)
                            Spacer()
                            Text(route.routeID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No active overlay schema")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var injectionSlotsSection: some View {
        Section("View Injections") {
            ForEach(controller.slotCatalog, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot)
                        .font(.headline)

                    if let injection = uiSurfaceManager.viewInjectionsBySlot[slot]?.first {
                        HStack {
                            Text("View ID: \(injection.viewID)")
                            Spacer()
                            Text("Priority \(injection.priority)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let injectedView = injectionRegistry.resolve(viewID: injection.viewID) {
                            injectedView
                        } else {
                            Text("No host view registered for \(injection.viewID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No active injection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var themeSection: some View {
        Section("Theme Mask") {
            if let themeMask = uiSurfaceManager.themeMask {
                Text("Theme ID: \(themeMask.themeID)")
                ForEach(themeMask.tokens, id: \.key) { token in
                    HStack {
                        Text(token.key)
                        Spacer()
                        Text(token.value)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No theme mask active")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toolbarActionText(_ action: ToolbarAction) -> String {
        switch action {
        case let .navigate(pointerID):
            return "Navigate \(pointerID)"
        case let .openOverlay(routeID):
            return "Overlay \(routeID)"
        case let .publishEvent(type, _):
            return "Event \(type)"
        }
    }

    private var hasPurchasableModules: Bool {
        let allModules = controller.serviceModules + controller.uiModules
        return allModules.contains { $0.manifest.iapProductID != nil }
    }
}

private struct ServiceModuleRow: View {
    let module: ForsettiHostModuleItem
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { module.isActive },
                set: { onToggle($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(module.displayName)
                    Spacer()
                    availabilityBadge
                }

                Text(module.moduleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = module.availability.userFacingReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!module.canActivate && !module.isActive)
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch module.availability {
        case .eligible:
            Text("Eligible")
                .font(.caption2)
                .foregroundStyle(.green)
        case .locked:
            Text("Locked")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .incompatible:
            Text("Incompatible")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

private struct UIModuleRow: View {
    let module: ForsettiHostModuleItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: module.isActive ? "largecircle.fill.circle" : "circle")
                    Text(module.displayName)
                    Spacer()
                    availabilityBadge
                }

                Text(module.moduleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = module.availability.userFacingReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!module.canActivate && !module.isActive)
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch module.availability {
        case .eligible:
            Text("Eligible")
                .font(.caption2)
                .foregroundStyle(.green)
        case .locked:
            Text("Locked")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .incompatible:
            Text("Incompatible")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
