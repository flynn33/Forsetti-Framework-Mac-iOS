import SwiftUI
import ForsettiCore

public struct ForsettiHostRootView: View {
    @ObservedObject private var controller: ForsettiHostController
    private let injectionRegistry: ForsettiViewInjectionRegistry

    @State private var isSettingsPresented = false
    @State private var isFrameworkChromeVisible = true

    public init(
        controller: ForsettiHostController,
        injectionRegistry: ForsettiViewInjectionRegistry = ForsettiViewInjectionRegistry()
    ) {
        self.controller = controller
        self.injectionRegistry = injectionRegistry
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if isFrameworkChromeVisible {
                    frameworkChrome
                }

                if let selectedModule = controller.selectedModuleItem() {
                    moduleWorkspace(module: selectedModule)
                } else {
                    frameworkHome
                }
            }

            if !isFrameworkChromeVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFrameworkChromeVisible = true
                    }
                } label: {
                    Label("Show Menus", systemImage: "line.3.horizontal")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thickMaterial, in: Capsule())
                }
                .padding(12)
                .accessibilityLabel("Show Forsetti framework controls")
            }
        }
        .task {
            await controller.bootIfNeeded()
        }
        .refreshable {
            await controller.refreshModuleState()
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
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

    private var frameworkChrome: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    controller.goHome()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel("Forsetti Home")

                GuideInfoButton(
                    text: "Home always returns to the default Forsetti module dashboard."
                )
            }

            Spacer()

            Text(controller.selectedModuleID == nil ? "Forsetti Home" : "Module Workspace")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                GuideInfoButton(
                    text: "Settings is a fixed framework control and remains in the top-right corner."
                )

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel("Forsetti Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var frameworkHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modulesOverview
                frameworkActions
            }
            .padding(16)
        }
    }

    private var modulesOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed Modules")
                    .font(.title3.bold())

                GuideInfoButton(
                    text: "Activate modules to run them concurrently. Open a module to move into its workspace view."
                )
            }

            if controller.serviceModules.isEmpty, controller.uiModules.isEmpty {
                Text("No modules discovered.")
                    .foregroundStyle(.secondary)
            }

            if !controller.serviceModules.isEmpty {
                Text("Service Modules")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(controller.serviceModules) { module in
                    serviceModuleCard(module: module)
                }
            }

            if !controller.uiModules.isEmpty {
                Text("UI Modules (Multi-Active)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(controller.uiModules) { module in
                    uiModuleCard(module: module)
                }
            }
        }
    }

    private var frameworkActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Framework Actions")
                    .font(.title3.bold())

                GuideInfoButton(
                    text: "These controls are provided by Forsetti and apply globally to all modules."
                )
            }

            HStack(spacing: 8) {
                Button("Refresh Entitlements") {
                    Task {
                        await controller.refreshEntitlements()
                    }
                }
                GuideInfoButton(
                    text: "Re-queries module unlock state from Forsetti entitlement services."
                )
            }

            if hasPurchasableModules {
                HStack(spacing: 8) {
                    Button("Restore Purchases") {
                        Task {
                            await controller.restorePurchases()
                        }
                    }
                    GuideInfoButton(
                        text: "Runs the restore flow and refreshes paid module access."
                    )
                }
            }

            if let lastAction = controller.lastToolbarActionDescription {
                Text("Last module action: \(lastAction)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func serviceModuleCard(module: ForsettiHostModuleItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    isOn: Binding(
                        get: { module.isActive },
                        set: { isEnabled in
                            Task {
                                await controller.setServiceModuleEnabled(moduleID: module.moduleID, isEnabled: isEnabled)
                            }
                        }
                    )
                ) {
                    Text(module.displayName)
                        .font(.headline)
                }
                .disabled(!module.canActivate && !module.isActive)

                GuideInfoButton(
                    text: "Service module activation controls background module runtime state."
                )
            }

            moduleMeta(module: module)

            HStack(spacing: 8) {
                Button("Open") {
                    Task {
                        await controller.openModule(moduleID: module.moduleID)
                    }
                }
                .disabled(!module.canActivate && !module.isActive)

                GuideInfoButton(
                    text: "Open moves into the module workspace while preserving Forsetti shell controls."
                )
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func uiModuleCard(module: ForsettiHostModuleItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    isOn: Binding(
                        get: { module.isActive },
                        set: { isEnabled in
                            Task {
                                await controller.setUIModuleEnabled(moduleID: module.moduleID, isEnabled: isEnabled)
                            }
                        }
                    )
                ) {
                    Text(module.displayName)
                        .font(.headline)
                }
                .disabled(!module.canActivate && !module.isActive)

                GuideInfoButton(
                    text: "UI module activation can run alongside other UI modules; activation does not force replacement."
                )
            }

            moduleMeta(module: module)

            HStack(spacing: 8) {
                Button("Open") {
                    Task {
                        await controller.openModule(moduleID: module.moduleID)
                    }
                }
                .disabled(!module.canActivate && !module.isActive)

                GuideInfoButton(
                    text: "Open sets this module as the current workspace without deactivating other modules."
                )
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func moduleMeta(module: ForsettiHostModuleItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(module.moduleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ModuleAvailabilityBadge(availability: module.availability)
            }

            if let reason = module.availability.userFacingReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moduleWorkspace(module: ForsettiHostModuleItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(module.displayName)
                            .font(.title2.bold())
                        Spacer()
                        ModuleAvailabilityBadge(availability: module.availability)
                    }

                    Text(module.moduleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isFrameworkChromeVisible = false
                            }
                        } label: {
                            Label("Hide Framework Menus", systemImage: "rectangle.compress.vertical")
                        }

                        GuideInfoButton(
                            text: "Modules may temporarily hide framework chrome, but users can always reveal it from the top-left Show Menus control."
                        )
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if module.moduleType == .ui {
                    moduleUISection(moduleID: module.moduleID)
                } else {
                    Text("This service module is running in the framework runtime. Use Home to switch modules.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func moduleUISection(moduleID: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Module Controls")
                    .font(.title3.bold())
                GuideInfoButton(
                    text: "All module controls are executed through Forsetti routing/event APIs."
                )
            }

            if let contributions = controller.uiContributions(for: moduleID) {
                if !contributions.toolbarItems.isEmpty {
                    Text("Module Actions")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(contributions.toolbarItems, id: \.itemID) { item in
                        HStack(spacing: 8) {
                            Button {
                                controller.handleToolbarAction(item.action)
                            } label: {
                                HStack {
                                    if let systemImageName = item.systemImageName {
                                        Image(systemName: systemImageName)
                                    }
                                    Text(item.title)
                                    Spacer()
                                    Text(toolbarActionText(item.action))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            GuideInfoButton(
                                text: "Runs a module-provided command through Forsetti, not direct module networking."
                            )
                        }
                    }
                }

                if let schema = contributions.overlaySchema {
                    Text("Module Routes")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(schema.pointers, id: \.pointerID) { pointer in
                        HStack(spacing: 8) {
                            Button("Open Pointer: \(pointer.label)") {
                                controller.handleToolbarAction(.navigate(pointerID: pointer.pointerID))
                            }
                            GuideInfoButton(
                                text: "Resolves pointer navigation inside Forsetti routing policy."
                            )
                        }
                    }

                    ForEach(schema.routes, id: \.routeID) { route in
                        HStack(spacing: 8) {
                            Button("Open Route: \(route.path)") {
                                controller.handleToolbarAction(.openOverlay(routeID: route.routeID))
                            }
                            GuideInfoButton(
                                text: "Opens route through Forsetti routing controls."
                            )
                        }
                    }
                }

                if !contributions.viewInjections.isEmpty {
                    let moduleWorkspaceInjections = contributions.viewInjections.filter { descriptor in
                        descriptor.slot == SlotCatalog.moduleWorkspace || descriptor.slot == SlotCatalog.overlayMain
                    }

                    if !moduleWorkspaceInjections.isEmpty {
                        Text("Module Views")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(
                            moduleWorkspaceInjections.sorted(by: { lhs, rhs in
                                if lhs.slot == rhs.slot {
                                    return lhs.priority > rhs.priority
                                }
                                return lhs.slot < rhs.slot
                            }),
                            id: \.injectionID
                        ) { injection in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Slot: \(injection.slot)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Priority \(injection.priority)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let injectedView = injectionRegistry.resolve(viewID: injection.viewID) {
                                    injectedView
                                } else {
                                    Text("No host view registered for \(injection.viewID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            } else {
                Text("No active module UI contributions are available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Framework") {
                    HStack {
                        Text("Forsetti Version")
                        Spacer()
                        Text(controller.runtime.forsettiVersion.description)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text(controller.runtime.platform.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Runtime") {
                    HStack {
                        Text("Active Service Modules")
                        Spacer()
                        Text("\(controller.enabledServiceModuleIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Active UI Modules")
                        Spacer()
                        Text("\(controller.enabledUIModuleIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isSettingsPresented = false
                    }
                }
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

private struct ModuleAvailabilityBadge: View {
    let availability: ForsettiHostModuleAvailability

    var body: some View {
        switch availability {
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

private struct GuideInfoButton: View {
    let text: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .accessibilityLabel("Guide")
    }
}
