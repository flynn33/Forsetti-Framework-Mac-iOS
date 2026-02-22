import Foundation
import ForsettiCore

public final class URLSessionNetworkingService: NetworkingService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public final class UserDefaultsStorageService: StorageService, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func value(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemorySecureStorageService: SecureStorageService, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func set(_ value: Data, forKey key: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    public func value(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func removeValue(forKey key: String) {
        lock.lock()
        storage[key] = nil
        lock.unlock()
    }
}

public final class LocalFileExportService: FileExportService {
    private let directoryURL: URL

    public init(directoryURL: URL = FileManager.default.temporaryDirectory) {
        self.directoryURL = directoryURL
    }

    public func export(data: Data, suggestedFileName: String) throws -> URL {
        let targetURL = directoryURL.appendingPathComponent(suggestedFileName)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }
}

public final class NoopTelemetryService: TelemetryService {
    public init() {}

    public func track(event _: String, properties _: [String: String]) {}
}

public final class DefaultForsettiPlatformServices {
    public let container: ForsettiServiceContainer

    public init(
        networking: NetworkingService = URLSessionNetworkingService(),
        storage: StorageService = UserDefaultsStorageService(),
        secureStorage: SecureStorageService = InMemorySecureStorageService(),
        fileExport: FileExportService = LocalFileExportService(),
        telemetry: TelemetryService = NoopTelemetryService()
    ) {
        container = ForsettiServiceContainer()
        container.register(NetworkingService.self, service: networking)
        container.register(StorageService.self, service: storage)
        container.register(SecureStorageService.self, service: secureStorage)
        container.register(FileExportService.self, service: fileExport)
        container.register(TelemetryService.self, service: telemetry)
    }
}
