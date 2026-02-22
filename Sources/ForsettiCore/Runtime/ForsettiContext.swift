import Foundation

@MainActor
public protocol OverlayRouting: Sendable {
    func openPointer(_ pointerID: String)
    func openRoute(_ routeID: String)
}

public final class ForsettiContext: @unchecked Sendable {
    public let eventBus: ForsettiEventBus
    public let services: any ForsettiServiceProviding
    public let logger: any ForsettiLogger
    public let router: any OverlayRouting

    public init(
        eventBus: ForsettiEventBus,
        services: any ForsettiServiceProviding,
        logger: any ForsettiLogger,
        router: any OverlayRouting
    ) {
        self.eventBus = eventBus
        self.services = services
        self.logger = logger
        self.router = router
    }
}

@MainActor
public struct NoopOverlayRouter: OverlayRouting {
    public init() {}

    public func openPointer(_ pointerID: String) {}
    public func openRoute(_ routeID: String) {}
}
