import Combine
import Foundation

@MainActor
public final class UISurfaceManager: ObservableObject {
    @Published public private(set) var themeMask: ThemeMask?
    @Published public private(set) var toolbarItems: [ToolbarItemDescriptor] = []
    @Published public private(set) var viewInjectionsBySlot: [String: [ViewInjectionDescriptor]] = [:]
    @Published public private(set) var overlaySchema: OverlaySchema?

    private var contributionsByModule: [String: UIContributions] = [:]

    public init() {}

    public func apply(moduleID: String, contributions: UIContributions) {
        contributionsByModule[moduleID] = contributions
        rebuildSurfaceState()
    }

    public func remove(moduleID: String) {
        contributionsByModule[moduleID] = nil
        rebuildSurfaceState()
    }

    public func clear() {
        contributionsByModule.removeAll()
        rebuildSurfaceState()
    }

    private func rebuildSurfaceState() {
        let orderedContributions = contributionsByModule
            .sorted(by: { $0.key < $1.key })
            .map(\.value)

        themeMask = orderedContributions.compactMap(\.themeMask).last
        overlaySchema = orderedContributions.compactMap(\.overlaySchema).last
        toolbarItems = orderedContributions.flatMap(\.toolbarItems)

        let injections = orderedContributions
            .flatMap(\.viewInjections)
            .sorted { lhs, rhs in
                if lhs.slot == rhs.slot {
                    return lhs.priority > rhs.priority
                }
                return lhs.slot < rhs.slot
            }

        viewInjectionsBySlot = Dictionary(grouping: injections, by: \.slot)
    }
}
