import Foundation

public enum ManifestLoaderError: Error, LocalizedError {
    case manifestsDirectoryNotFound(String)
    case duplicateModuleID(String)
    case validationFailed(file: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .manifestsDirectoryNotFound(path):
            return "No manifests found in resource directory: \(path)."
        case let .duplicateModuleID(moduleID):
            return "Duplicate moduleID in manifest resources: \(moduleID)."
        case let .validationFailed(file, reason):
            return "Manifest \(file) failed validation: \(reason)."
        }
    }
}

public final class ManifestLoader {
    private let decoder: JSONDecoder
    private let manifestRootKeys: Set<String> = [
        "schemaVersion",
        "moduleID",
        "displayName",
        "moduleVersion",
        "moduleType",
        "supportedPlatforms",
        "minForsettiVersion",
        "capabilitiesRequested",
        "entryPoint"
    ]

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func loadManifests(
        bundle: Bundle,
        subdirectory: String = "ForsettiManifests"
    ) throws -> [String: ModuleManifest] {
        if let directURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory), !directURLs.isEmpty {
            return try loadManifests(
                resourceURLs: directURLs,
                strict: true,
                missingDirectoryHint: subdirectory
            )
        }

        // SwiftPM resource processing may flatten directories; fallback to recursive lookup.
        guard let resourceURL = bundle.resourceURL else {
            throw ManifestLoaderError.manifestsDirectoryNotFound(subdirectory)
        }

        let recursiveURLs = try FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).flatMap { url -> [URL] in
            if url.hasDirectoryPath {
                return recursiveJSONURLs(in: url)
            }
            return url.pathExtension.lowercased() == "json" ? [url] : []
        }

        let requestedFolderName = URL(fileURLWithPath: subdirectory).lastPathComponent.lowercased()
        let scopedURLs = recursiveURLs.filter { url in
            !requestedFolderName.isEmpty && url.path.lowercased().contains(requestedFolderName)
        }

        if !scopedURLs.isEmpty {
            return try loadManifests(
                resourceURLs: scopedURLs,
                strict: true,
                missingDirectoryHint: subdirectory
            )
        }

        guard !recursiveURLs.isEmpty else {
            throw ManifestLoaderError.manifestsDirectoryNotFound(subdirectory)
        }

        return try loadManifests(
            resourceURLs: recursiveURLs,
            strict: false,
            missingDirectoryHint: subdirectory
        )
    }

    public func loadManifests(resourceURLs: [URL]) throws -> [String: ModuleManifest] {
        try loadManifests(
            resourceURLs: resourceURLs,
            strict: true,
            missingDirectoryHint: "provided resource URLs"
        )
    }

    private func loadManifests(
        resourceURLs: [URL],
        strict: Bool,
        missingDirectoryHint: String
    ) throws -> [String: ModuleManifest] {
        var manifests: [String: ModuleManifest] = [:]

        for url in resourceURLs {
            let data = try Data(contentsOf: url)

            if !strict, !looksLikeManifestJSON(data) {
                continue
            }

            let manifest: ModuleManifest
            do {
                manifest = try decoder.decode(ModuleManifest.self, from: data)
            } catch {
                throw ManifestLoaderError.validationFailed(
                    file: url.lastPathComponent,
                    reason: "invalid manifest JSON (\(error.localizedDescription))"
                )
            }

            try validate(manifest: manifest, fileName: url.lastPathComponent)

            if manifests[manifest.moduleID] != nil {
                throw ManifestLoaderError.duplicateModuleID(manifest.moduleID)
            }

            manifests[manifest.moduleID] = manifest
        }

        if manifests.isEmpty {
            throw ManifestLoaderError.manifestsDirectoryNotFound(missingDirectoryHint)
        }

        return manifests
    }

    private func validate(manifest: ModuleManifest, fileName: String) throws {
        try validateIdentityFields(manifest, fileName: fileName)
        try validateSchemaVersions(manifest, fileName: fileName)
        try validateVersionRange(manifest, fileName: fileName)
        try validateDuplicateManifestArrays(manifest, fileName: fileName)
        try validateRoleAndUIBoundary(manifest, fileName: fileName)
        try validateIORequirements(manifest, fileName: fileName)
        try validateUIRequirements(manifest.runtimeRequirements.ui, fileName: fileName)
        try validateDataIsolation(manifest.runtimeRequirements.dataIsolation, fileName: fileName)
    }

    private func validateIdentityFields(_ manifest: ModuleManifest, fileName: String) throws {
        if isBlank(manifest.schemaVersion) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "schemaVersion is required")
        }

        if isBlank(manifest.moduleID) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "moduleID is required")
        }

        if isBlank(manifest.displayName) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "displayName is required")
        }

        if isBlank(manifest.entryPoint) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "entryPoint is required")
        }

        if !Self.moduleIDPattern.matches(manifest.moduleID) {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "moduleID '\(manifest.moduleID)' must use reverse-DNS segments."
            )
        }

        if manifest.moduleID.hasPrefix("forsetti.") {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "moduleID '\(manifest.moduleID)' uses the reserved forsetti namespace."
            )
        }

        if !Self.entryPointPattern.matches(manifest.entryPoint) {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "entryPoint '\(manifest.entryPoint)' must be a Swift type path."
            )
        }
    }

    private func validateSchemaVersions(_ manifest: ModuleManifest, fileName: String) throws {
        guard ModuleManifest.supportedSchemaVersions.contains(manifest.schemaVersion) else {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "Unsupported schemaVersion '\(manifest.schemaVersion)'."
            )
        }

        guard ModuleManifest.supportedManifestTemplateVersions.contains(manifest.manifestTemplateVersion) else {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "Unsupported manifestTemplateVersion '\(manifest.manifestTemplateVersion.rawValue)'."
            )
        }

        if manifest.schemaVersion == ModuleManifest.currentSchemaVersion,
           manifest.manifestTemplateVersion != .current {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "schemaVersion \(ModuleManifest.currentSchemaVersion) requires manifestTemplateVersion \(ManifestTemplateVersion.current.rawValue)."
            )
        }
    }

    private func validateVersionRange(_ manifest: ModuleManifest, fileName: String) throws {
        if manifest.supportedPlatforms.isEmpty {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "supportedPlatforms must include at least one platform")
        }

        try validateSemVer(manifest.moduleVersion, label: "moduleVersion", fileName: fileName)
        try validateSemVer(manifest.minForsettiVersion, label: "minForsettiVersion", fileName: fileName)
        if let maxForsettiVersion = manifest.maxForsettiVersion {
            try validateSemVer(maxForsettiVersion, label: "maxForsettiVersion", fileName: fileName)
            if maxForsettiVersion < manifest.minForsettiVersion {
                throw ManifestLoaderError.validationFailed(
                    file: fileName,
                    reason: "maxForsettiVersion cannot be below minForsettiVersion."
                )
            }
        }
    }

    private func validateDuplicateManifestArrays(_ manifest: ModuleManifest, fileName: String) throws {
        if hasDuplicates(manifest.supportedPlatforms) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "supportedPlatforms contains duplicates")
        }

        if hasDuplicates(manifest.capabilitiesRequested) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "capabilitiesRequested contains duplicates")
        }
    }

    private func validateRoleAndUIBoundary(_ manifest: ModuleManifest, fileName: String) throws {
        if let role = manifest.defaultModuleRole, !role.isValid(for: manifest.moduleType) {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "defaultModuleRole '\(role.rawValue)' is invalid for moduleType '\(manifest.moduleType.rawValue)'."
            )
        }

        if manifest.moduleType == .service, manifest.runtimeRequirements.ui != nil {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "service modules cannot declare UI requirements."
            )
        }
    }

    private func validateIORequirements(_ manifest: ModuleManifest, fileName: String) throws {
        let requestedCapabilities = Set(manifest.capabilitiesRequested)
        var ioRequirementIDs = Set<String>()
        for requirement in manifest.runtimeRequirements.io {
            let requirementID = requirement.requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
            if requirementID.isEmpty {
                throw ManifestLoaderError.validationFailed(file: fileName, reason: "I/O requirementID is required.")
            }
            if !ioRequirementIDs.insert(requirementID).inserted {
                throw ManifestLoaderError.validationFailed(
                    file: fileName,
                    reason: "Duplicate I/O requirementID '\(requirementID)'."
                )
            }
            let requiredCapability = requirement.kind.requiredCapability
            if !requestedCapabilities.contains(requiredCapability) {
                throw ManifestLoaderError.validationFailed(
                    file: fileName,
                    reason: "I/O requirement '\(requirementID)' requires capability '\(requiredCapability.rawValue)'."
                )
            }
        }
    }

    private func validateSemVer(_ value: SemVer, label: String, fileName: String) throws {
        guard value.hasNonNegativeComponents else {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "\(label) cannot contain negative components."
            )
        }
    }

    private func validateUIRequirements(_ requirements: ModuleUIRequirements?, fileName: String) throws {
        guard let requirements else {
            return
        }

        try validateIdentifierSet(requirements.themeIDs, label: "themeIDs", fileName: fileName)
        try validateIdentifierSet(requirements.viewIDs, label: "viewIDs", fileName: fileName)
        try validateIdentifierSet(requirements.slotIDs, label: "slotIDs", fileName: fileName)
        try validateIdentifierSet(requirements.toolbarItemIDs, label: "toolbarItemIDs", fileName: fileName)
        try validateIdentifierSet(requirements.routeIDs, label: "routeIDs", fileName: fileName)
        try validateIdentifierSet(requirements.pointerIDs, label: "pointerIDs", fileName: fileName)
    }

    private func validateDataIsolation(_ dataIsolation: ModuleDataIsolation, fileName: String) throws {
        try validateIdentifierSet(dataIsolation.ownedStoreIDs, label: "ownedStoreIDs", fileName: fileName)
        if hasDuplicates(dataIsolation.requiredDefaultRoles) {
            throw ManifestLoaderError.validationFailed(
                file: fileName,
                reason: "requiredDefaultRoles contains duplicates."
            )
        }
    }

    private func validateIdentifierSet(_ values: [String], label: String, fileName: String) throws {
        if values.contains(where: isBlank) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "\(label) cannot contain blank values.")
        }
        if hasDuplicates(values) {
            throw ManifestLoaderError.validationFailed(file: fileName, reason: "\(label) contains duplicates.")
        }
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasDuplicates<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count != values.count
    }

    private func recursiveJSONURLs(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "json" {
                urls.append(fileURL)
            }
        }
        return urls
    }

    private func looksLikeManifestJSON(_ data: Data) -> Bool {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any] else {
            return false
        }

        return manifestRootKeys.isSubset(of: Set(dictionary.keys))
    }

    private static let moduleIDPattern = RegexMatcher("^[A-Za-z][A-Za-z0-9]*(\\.[A-Za-z][A-Za-z0-9-]*)+$")
    private static let entryPointPattern = RegexMatcher("^[A-Za-z_][A-Za-z0-9_.]*$")
}

private struct RegexMatcher {
    private let regex: NSRegularExpression?

    init(_ pattern: String) {
        regex = try? NSRegularExpression(pattern: pattern)
    }

    func matches(_ value: String) -> Bool {
        guard let regex else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }
}
