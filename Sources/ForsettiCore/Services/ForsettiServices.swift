import Foundation

public protocol ForsettiServiceProviding: Sendable {
    func resolve<T>(_ type: T.Type) -> T?
}

public protocol NetworkingService: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public protocol StorageService: Sendable {
    func set(_ value: String, forKey key: String)
    func value(forKey key: String) -> String?
    func removeValue(forKey key: String)
}

public protocol SecureStorageService: Sendable {
    func set(_ value: Data, forKey key: String) throws
    func value(forKey key: String) throws -> Data?
    func removeValue(forKey key: String) throws
}

public protocol FileExportService: Sendable {
    func export(data: Data, suggestedFileName: String) throws -> URL
}

public protocol TelemetryService: Sendable {
    func track(event: String, properties: [String: String])
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
