import Foundation
import XCTest

final class ArchitectureEnforcementTests: XCTestCase {
    private static let guardedTargets: Set<String> = [
        "ForsettiCore",
        "ForsettiPlatform",
        "ForsettiModulesExample",
        "ForsettiHostTemplate"
    ]

    private static let expectedTargetDependencies: [String: Set<String>] = [
        "ForsettiCore": [],
        "ForsettiPlatform": ["ForsettiCore"],
        "ForsettiModulesExample": ["ForsettiCore"],
        "ForsettiHostTemplate": ["ForsettiCore", "ForsettiPlatform"]
    ]

    private static let expectedInternalImports: [String: Set<String>] = [
        "ForsettiCore": [],
        "ForsettiPlatform": ["ForsettiCore"],
        "ForsettiModulesExample": ["ForsettiCore"],
        "ForsettiHostTemplate": ["ForsettiCore", "ForsettiPlatform"]
    ]

    private static let disallowedFrameworkImports: [String: Set<String>] = [
        "ForsettiCore": ["SwiftUI", "UIKit", "AppKit", "StoreKit", "Combine"],
        "ForsettiPlatform": ["SwiftUI", "UIKit", "AppKit"],
        "ForsettiModulesExample": ["SwiftUI", "UIKit", "AppKit", "StoreKit"]
    ]

    private var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPackageDependencyGraphMatchesExpectedLayering() throws {
        let actualDependencies = try loadRegularTargetDependenciesFromManifest()

        XCTAssertEqual(Set(actualDependencies.keys), Self.guardedTargets)

        for (target, expectedDependencies) in Self.expectedTargetDependencies.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(
                actualDependencies[target, default: []],
                expectedDependencies,
                "Unexpected module dependencies for \(target)."
            )
        }
    }

    func testInternalImportsRespectLayerBoundaries() throws {
        let internalModules = Self.guardedTargets

        for (target, allowedImports) in Self.expectedInternalImports.sorted(by: { $0.key < $1.key }) {
            for fileURL in try swiftSourceFiles(inTarget: target) {
                for importedModule in try parseImports(in: fileURL) where internalModules.contains(importedModule) {
                    XCTAssertTrue(
                        allowedImports.contains(importedModule),
                        "\(target) cannot import \(importedModule) in \(relativePath(for: fileURL))."
                    )
                }
            }
        }
    }

    func testFrameworkImportsRespectTargetRole() throws {
        for (target, disallowedImports) in Self.disallowedFrameworkImports.sorted(by: { $0.key < $1.key }) {
            for fileURL in try swiftSourceFiles(inTarget: target) {
                for importedModule in try parseImports(in: fileURL) where disallowedImports.contains(importedModule) {
                    XCTFail(
                        "\(target) cannot import \(importedModule) in \(relativePath(for: fileURL))."
                    )
                }
            }
        }
    }

    func testAllProductionClassesAreFinal() throws {
        let classDeclarationRegex = try NSRegularExpression(
            pattern: #"(?m)^\s*(?:@\w+(?:\([^)\n]*\))?\s*)*(?:public|internal|private|fileprivate|open)?\s*(?:final\s+)?class\s+[A-Za-z_][A-Za-z0-9_]*\b"#
        )
        var nonFinalClasses: [String] = []

        for fileURL in try swiftSourceFiles(in: packageRootURL.appendingPathComponent("Sources")) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let nsSource = source as NSString

            for match in classDeclarationRegex.matches(
                in: source,
                range: NSRange(location: 0, length: nsSource.length)
            ) {
                let declaration = nsSource.substring(with: match.range)
                if !declaration.contains("final class") {
                    nonFinalClasses.append("\(relativePath(for: fileURL)): \(declaration)")
                }
            }
        }

        XCTAssertTrue(
            nonFinalClasses.isEmpty,
            """
            All source classes must be `final` to preserve Forsetti OOP boundaries.
            Violations:
            \(nonFinalClasses.joined(separator: "\n"))
            """
        )
    }

    func testPublicRepositorySurfacesDoNotContainAttributionTerms() throws {
        let prohibitedContentTerms = [
            joined("Co-authored", "-by"),
            joined("Generated", " by"),
            joined("generated", " by"),
            joined("authored", " by"),
            joined("Authored", " by"),
            joined("Chat", "GPT"),
            joined("Open", "AI"),
            joined("Cod", "ex"),
            joined("AI", "-assisted"),
            joined("AI", " generated"),
            joined("AI", "-generated"),
            joined("ag", "entic"),
            joined("AI", " coding"),
            joined("AI", joined(" ag", "ents"))
        ]
        let prohibitedPathTerms = [
            joined("Cod", "ex").lowercased(),
            joined("ag", "entic"),
            joined("ag", "ent"),
            joined("Chat", "GPT").lowercased(),
            joined("Open", "AI").lowercased(),
            joined("l", "lm")
        ]

        var violations: [String] = []
        for path in try trackedRepositoryFiles() where !path.hasPrefix(".forsetti/") {
            let lowercasePath = path.lowercased()
            for term in prohibitedPathTerms where lowercasePath.contains(term) {
                violations.append("Prohibited filename term in \(path).")
            }

            let fileURL = packageRootURL.appendingPathComponent(path)
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for term in prohibitedContentTerms where source.contains(term) {
                violations.append("Prohibited content term in \(path).")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Public repository surfaces must not contain prohibited attribution terms.
            Violations:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testExampleAndTemplateManifestsDeclareRuntimeRequirements() throws {
        let manifestPaths = [
            "Sources/ForsettiModulesExample/Resources/ForsettiManifests/ExampleServiceModule.json",
            "Sources/ForsettiModulesExample/Resources/ForsettiManifests/ExampleUIModule.json",
            "XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate/AppModuleManifest.json",
            "XcodeTemplates/Project Templates/Forsetti/Forsetti Service Module.xctemplate/ServiceModuleManifest.json",
            "XcodeTemplates/Project Templates/Forsetti/Forsetti UI Module.xctemplate/UIModuleManifest.json",
            "XcodeTemplates/Project Templates/Forsetti/Forsetti Manifest.xctemplate/ModuleManifest.json"
        ]

        for path in manifestPaths {
            let data = try Data(contentsOf: packageRootURL.appendingPathComponent(path))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let manifest = object as? [String: Any] else {
                XCTFail("\(path) is not a JSON object.")
                continue
            }

            XCTAssertEqual(manifest["schemaVersion"] as? String, "1.1", "\(path) must use schema 1.1.")
            XCTAssertEqual(
                manifest["manifestTemplateVersion"] as? String,
                "1.1",
                "\(path) must declare manifestTemplateVersion."
            )
            XCTAssertNotNil(manifest["runtimeRequirements"], "\(path) must declare runtimeRequirements.")
        }
    }

    private func parseImports(in fileURL: URL) throws -> [String] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let nsSource = source as NSString
        let importRegex = try NSRegularExpression(pattern: #"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)\b"#)

        return importRegex.matches(in: source, range: NSRange(location: 0, length: nsSource.length)).compactMap {
            guard $0.numberOfRanges > 1 else {
                return nil
            }
            return nsSource.substring(with: $0.range(at: 1))
        }
    }

    private func swiftSourceFiles(inTarget targetName: String) throws -> [URL] {
        let targetURL = packageRootURL
            .appendingPathComponent("Sources")
            .appendingPathComponent(targetName)
        return try swiftSourceFiles(in: targetURL)
    }

    private func swiftSourceFiles(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw architectureError("Missing source directory at \(directoryURL.path).")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw architectureError("Could not enumerate \(directoryURL.path).")
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            files.append(fileURL)
        }

        return files.sorted(by: { $0.path < $1.path })
    }

    private func loadRegularTargetDependenciesFromManifest() throws -> [String: Set<String>] {
        let manifestURL = packageRootURL.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let nsManifest = manifest as NSString
        let targetRegex = try NSRegularExpression(
            pattern: #"(?s)\.target\(\s*name:\s*"([^"]+)"\s*,\s*dependencies:\s*\[([^\]]*)\]"#
        )
        let dependencyRegex = try NSRegularExpression(pattern: #""([^"]+)""#)

        var dependenciesByTarget: [String: Set<String>] = [:]
        for match in targetRegex.matches(
            in: manifest,
            range: NSRange(location: 0, length: nsManifest.length)
        ) {
            guard match.numberOfRanges > 2 else {
                continue
            }

            let targetName = nsManifest.substring(with: match.range(at: 1))
            guard Self.guardedTargets.contains(targetName) else {
                continue
            }

            let dependencySlice = nsManifest.substring(with: match.range(at: 2))
            let nsDependencySlice = dependencySlice as NSString
            let dependencies = dependencyRegex.matches(
                in: dependencySlice,
                range: NSRange(location: 0, length: nsDependencySlice.length)
            ).map {
                nsDependencySlice.substring(with: $0.range(at: 1))
            }

            dependenciesByTarget[targetName] = Set(dependencies)
        }

        return dependenciesByTarget
    }

    private func trackedRepositoryFiles() throws -> [String] {
        let process = Process()
        process.currentDirectoryURL = packageRootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw architectureError("Could not enumerate tracked repository files.")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw architectureError("Could not decode tracked repository file list.")
        }
        return output.split(separator: "\n").map(String.init)
    }

    private func joined(_ first: String, _ second: String) -> String {
        first + second
    }

    private func relativePath(for url: URL) -> String {
        let rootPathWithSlash = packageRootURL.path + "/"
        return url.path.replacingOccurrences(of: rootPathWithSlash, with: "")
    }

    private func architectureError(_ message: String) -> NSError {
        NSError(
            domain: "ForsettiArchitectureTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
