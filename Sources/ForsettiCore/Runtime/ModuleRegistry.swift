import Foundation

public typealias ModuleFactory = @Sendable () -> ForsettiModule

public enum ModuleRegistryError: Error, LocalizedError {
    case entryPointNotRegistered(String)
    case duplicateEntryPoint(String)

    public var errorDescription: String? {
        switch self {
        case let .entryPointNotRegistered(entryPoint):
            return "No module factory registered for entryPoint '\(entryPoint)'."
        case let .duplicateEntryPoint(entryPoint):
            return "Module factory already registered for entryPoint '\(entryPoint)'."
        }
    }
}

public final class ModuleRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var factories: [String: ModuleFactory]

    public init(registrations: [String: ModuleFactory] = [:]) {
        self.factories = registrations
    }

    public var registeredEntryPoints: [String] {
        lock.lock()
        defer { lock.unlock() }
        return factories.keys.sorted()
    }

    public func register(
        entryPoint: String,
        replacingExisting: Bool = false,
        factory: @escaping ModuleFactory
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        if factories[entryPoint] != nil, !replacingExisting {
            throw ModuleRegistryError.duplicateEntryPoint(entryPoint)
        }
        factories[entryPoint] = factory
    }

    public func makeModule(entryPoint: String) throws -> ForsettiModule {
        lock.lock()
        let factory = factories[entryPoint]
        lock.unlock()

        guard let factory else {
            throw ModuleRegistryError.entryPointNotRegistered(entryPoint)
        }

        return factory()
    }
}
