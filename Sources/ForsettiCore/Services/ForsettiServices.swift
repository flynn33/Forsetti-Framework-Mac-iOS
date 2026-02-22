import Foundation

public protocol ForsettiServiceProviding: Sendable {
    func resolve<T>(_ type: T.Type) -> T?
}

public final class ForsettiServiceContainer: ForsettiServiceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var services: [ObjectIdentifier: Any] = [:]

    public init() {}

    public func register<T>(_ type: T.Type, service: T) {
        lock.lock()
        services[ObjectIdentifier(type)] = service
        lock.unlock()
    }

    public func resolve<T>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return services[ObjectIdentifier(type)] as? T
    }
}
