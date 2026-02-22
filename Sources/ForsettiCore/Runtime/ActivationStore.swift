import Foundation

public struct ActivationState: Codable, Sendable, Hashable {
    public var enabledServiceModuleIDs: Set<String>
    public var activeUIModuleID: String?

    public init(enabledServiceModuleIDs: Set<String> = [], activeUIModuleID: String? = nil) {
        self.enabledServiceModuleIDs = enabledServiceModuleIDs
        self.activeUIModuleID = activeUIModuleID
    }
}

public protocol ActivationStore: Sendable {
    func loadState() -> ActivationState
    func saveState(_ state: ActivationState) throws
}

public final class UserDefaultsActivationStore: ActivationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "forsetti.activation.state") {
        self.defaults = defaults
        self.key = key
    }

    public func loadState() -> ActivationState {
        guard let data = defaults.data(forKey: key),
              let state = try? decoder.decode(ActivationState.self, from: data) else {
            return ActivationState()
        }
        return state
    }

    public func saveState(_ state: ActivationState) throws {
        let data = try encoder.encode(state)
        defaults.set(data, forKey: key)
    }
}
