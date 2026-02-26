import Foundation

@MainActor
public protocol OverlayRouting: Sendable {
    func openPointer(_ pointerID: String)
    func openRoute(_ routeID: String)
}

public enum ModuleCommunicationDecision: Sendable {
    case allowed
    case denied(reason: String)
}

public protocol ModuleCommunicationGuard: Sendable {
    func evaluate(
        sourceModuleID: String,
        targetModuleID: String,
        eventType: String,
        payload: [String: String]
    ) -> ModuleCommunicationDecision
}

public struct DefaultModuleCommunicationGuard: ModuleCommunicationGuard {
    public init() {}

    public func evaluate(
        sourceModuleID: String,
        targetModuleID: String,
        eventType: String,
        payload _: [String: String]
    ) -> ModuleCommunicationDecision {
        if sourceModuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .denied(reason: "Source module ID cannot be empty.")
        }

        if targetModuleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .denied(reason: "Target module ID cannot be empty.")
        }

        if sourceModuleID == targetModuleID {
            return .denied(reason: "Module relay to self is not required.")
        }

        if eventType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .denied(reason: "Event type cannot be empty.")
        }

        if eventType.hasPrefix("forsetti.internal.") {
            return .denied(reason: "Reserved event namespace cannot be used by modules.")
        }

        return .allowed
    }
}

public enum ForsettiContextError: Error, LocalizedError {
    case moduleCommunicationDenied(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .moduleCommunicationDenied(reason):
            return "Module communication denied. \(reason)"
        }
    }
}

public struct ForsettiModuleLogger: Sendable {
    public let moduleID: String
    private let logger: any ForsettiLogger

    public init(moduleID: String, logger: any ForsettiLogger) {
        self.moduleID = moduleID
        self.logger = logger
    }

    public func debug(_ message: String, metadata: [String: String] = [:]) {
        logger.log(.debug, message: message, sourceModuleID: moduleID, metadata: metadata)
    }

    public func info(_ message: String, metadata: [String: String] = [:]) {
        logger.log(.info, message: message, sourceModuleID: moduleID, metadata: metadata)
    }

    public func warning(_ message: String, metadata: [String: String] = [:]) {
        logger.log(.warning, message: message, sourceModuleID: moduleID, metadata: metadata)
    }

    public func error(
        _ message: String,
        error: (any Error)? = nil,
        metadata: [String: String] = [:]
    ) {
        if let error {
            logger.logError(
                error,
                message: message,
                sourceModuleID: moduleID,
                metadata: metadata
            )
            return
        }

        logger.log(
            .error,
            message: message,
            sourceModuleID: moduleID,
            metadata: metadata
        )
    }
}

public final class ForsettiContext: @unchecked Sendable {
    public let services: any ForsettiServiceProviding
    public let logger: any ForsettiLogger
    public let router: any OverlayRouting
    private let eventBus: ForsettiEventBus
    private let moduleCommunicationGuard: any ModuleCommunicationGuard
    private static let targetModuleIDPayloadKey = "_forsetti.targetModuleID"

    public init(
        eventBus: ForsettiEventBus,
        services: any ForsettiServiceProviding,
        logger: any ForsettiLogger,
        router: any OverlayRouting,
        moduleCommunicationGuard: any ModuleCommunicationGuard = DefaultModuleCommunicationGuard()
    ) {
        self.eventBus = eventBus
        self.services = services
        self.logger = logger
        self.router = router
        self.moduleCommunicationGuard = moduleCommunicationGuard
    }

    public func publishFrameworkEvent(
        type: String,
        payload: [String: String] = [:],
        sourceModuleID: String? = nil
    ) {
        eventBus.publish(
            event: ForsettiEvent(
                type: type,
                payload: payload,
                sourceModuleID: sourceModuleID
            )
        )
    }

    @discardableResult
    public func sendModuleMessage(
        from sourceModuleID: String,
        to targetModuleID: String,
        type eventType: String,
        payload: [String: String] = [:]
    ) throws -> ForsettiEvent {
        let decision = moduleCommunicationGuard.evaluate(
            sourceModuleID: sourceModuleID,
            targetModuleID: targetModuleID,
            eventType: eventType,
            payload: payload
        )

        if case let .denied(reason) = decision {
            reportModuleError(
                moduleID: sourceModuleID,
                message: "Blocked module-to-module communication",
                error: ForsettiContextError.moduleCommunicationDenied(reason: reason),
                metadata: [
                    "eventType": eventType,
                    "targetModuleID": targetModuleID
                ]
            )
            throw ForsettiContextError.moduleCommunicationDenied(reason: reason)
        }

        var enrichedPayload = payload
        enrichedPayload[Self.targetModuleIDPayloadKey] = targetModuleID

        let event = ForsettiEvent(
            type: eventType,
            payload: enrichedPayload,
            sourceModuleID: sourceModuleID
        )
        eventBus.publish(event: event)
        return event
    }

    public func subscribeToModuleMessages(
        moduleID: String,
        eventType: String,
        handler: @escaping @Sendable (ForsettiEvent) -> Void
    ) -> SubscriptionToken {
        eventBus.subscribe(eventType: eventType) { event in
            guard event.payload[Self.targetModuleIDPayloadKey] == moduleID else {
                return
            }
            handler(event)
        }
    }

    public func subscribeToFrameworkEvents(
        eventType: String,
        handler: @escaping @Sendable (ForsettiEvent) -> Void
    ) -> SubscriptionToken {
        eventBus.subscribe(eventType: eventType, handler: handler)
    }

    public func moduleLogger(moduleID: String) -> ForsettiModuleLogger {
        ForsettiModuleLogger(moduleID: moduleID, logger: logger)
    }

    public func logModule(
        _ level: LogLevel,
        moduleID: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        logger.log(level, message: message, sourceModuleID: moduleID, metadata: metadata)
    }

    public func reportModuleError(
        moduleID: String,
        message: String,
        error: (any Error)? = nil,
        metadata: [String: String] = [:]
    ) {
        moduleLogger(moduleID: moduleID).error(message, error: error, metadata: metadata)
    }
}

@MainActor
public struct NoopOverlayRouter: OverlayRouting {
    public init() {}

    public func openPointer(_ pointerID: String) {}
    public func openRoute(_ routeID: String) {}
}
