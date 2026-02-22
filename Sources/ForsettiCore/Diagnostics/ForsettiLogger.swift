import Foundation

public enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

public protocol ForsettiLogger: Sendable {
    func log(_ level: LogLevel, message: String)
}

public struct ConsoleForsettiLogger: ForsettiLogger {
    public init() {}

    public func log(_ level: LogLevel, message: String) {
        #if DEBUG
        print("[Forsetti][\(level.rawValue.uppercased())] \(message)")
        #endif
    }
}
