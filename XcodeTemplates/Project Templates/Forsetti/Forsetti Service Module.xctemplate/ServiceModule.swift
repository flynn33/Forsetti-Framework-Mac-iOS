//___FILEHEADER___

#if canImport(ForsettiCore)
import Foundation
import ForsettiCore

final class ___PACKAGENAME:identifier___ServiceModule: ForsettiModule {
    enum Constants {
        static let moduleID = "com.yourcompany.___PACKAGENAME:identifier___.service-module"
        static let entryPoint = "___PACKAGENAME:identifier___ServiceModule"
        static let heartbeatStorageKey = "___PACKAGENAME:identifier___.service-module.last-heartbeat"
    }

    let descriptor = ModuleDescriptor(
        moduleID: Constants.moduleID,
        displayName: "___PACKAGENAME___ Service Module",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: Constants.moduleID,
        displayName: "___PACKAGENAME___ Service Module",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.storage, .telemetry],
        iapProductID: nil,
        entryPoint: Constants.entryPoint,
        runtimeRequirements: ModuleRuntimeRequirements(
            io: [
                ModuleIORequirement(
                    requirementID: "___PACKAGENAME:identifier___.service-module.storage.heartbeat",
                    kind: .storage,
                    access: .readWrite,
                    required: false
                ),
                ModuleIORequirement(
                    requirementID: "___PACKAGENAME:identifier___.service-module.telemetry.lifecycle",
                    kind: .telemetry,
                    access: .emit,
                    required: false
                )
            ],
            dataIsolation: ModuleDataIsolation(
                mode: .privateToModule,
                ownedStoreIDs: ["___PACKAGENAME:identifier___.service-module"]
            )
        )
    )

    private var isStarted = false

    init() {}

    func start(context: any ForsettiModuleContext) throws {
        guard !isStarted else {
            return
        }

        isStarted = true
        context.logger.info("Service module started")

        let startedAt = Date().ISO8601Format()
        if let storage = context.services.resolve(StorageService.self) {
            storage.set(startedAt, forKey: Constants.heartbeatStorageKey)
        }

        if let telemetry = context.services.resolve(TelemetryService.self) {
            telemetry.track(
                event: "service_module_started",
                properties: ["moduleID": descriptor.moduleID, "startedAt": startedAt]
            )
        }
    }

    func stop(context: any ForsettiModuleContext) {
        guard isStarted else {
            return
        }

        isStarted = false
        context.logger.info("Service module stopped")

        if let storage = context.services.resolve(StorageService.self) {
            storage.removeValue(forKey: Constants.heartbeatStorageKey)
        }
    }
}
#endif
