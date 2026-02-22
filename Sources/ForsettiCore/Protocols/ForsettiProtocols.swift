import Foundation

public protocol ForsettiModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    var manifest: ModuleManifest { get }

    func start(context: ForsettiContext) throws
    func stop(context: ForsettiContext)
}

public protocol ForsettiUIModule: ForsettiModule {
    var uiContributions: UIContributions { get }
}

public protocol ForsettiEntitlementProvider: Sendable {
    func isUnlocked(moduleID: String, productID: String?) async -> Bool
    func refreshEntitlements() async
    func entitlementsDidChangeStream() -> AsyncStream<Void>
    func restorePurchases() async throws
}

public extension ForsettiEntitlementProvider {
    func restorePurchases() async throws {}
}
