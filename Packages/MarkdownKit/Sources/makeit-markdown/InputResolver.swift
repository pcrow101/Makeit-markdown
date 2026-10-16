import Foundation
import MarkdownKit

/// Expands command line inputs into a list of convertible documents.
struct InputResolver {

    /// A problem encountered while expanding the supplied paths.
    struct Failure: Error, Equatable {
        var path: String
        var message: String
    }

    private let registry: ConverterRegistry
    private let fileManager: FileManager

    init(registry: ConverterRegistry, fileManager: FileManager = .default) {
        self.registry = registry
        self.fileManager = fileManager
    }

    /// Resolves `paths` into document URLs.
    ///
    /// Files named explicitly are always included, even when the registry does
    /// not recognise them, so that the user receives a specific error. Files
    /// discovered by walking a directory are filtered to recognised types,
    /// because sweeping a folder should not fail on unrelated content.
    ///
    /// - Parameters:
    ///   - paths: The file and directory paths supplied on the command line.
    ///   - recursive: Whether directories should be searched recursively.
    func resolve(paths: [String], recursive: Bool) throws -> [URL] {
        var resolved: [URL] = []
        var seen: Set<String> = []

        for path in paths {
            let url = URL(filePath: path).standardizedFileURL

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: url.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            guard exists else {
                throw Failure(path: path, message: "no such file or directory")
            }

            if isDirectory.boolValue {
                let contents = try directoryContents(of: url, recursive: recursive)
                for item in contents where seen.insert(item.path(percentEncoded: false)).inserted {
                    resolved.append(item)
                }
            } else if seen.insert(url.path(percentEncoded: false)).inserted {
                resolved.append(url)
            }
        }

        return resolved
    }

    private func directoryContents(of directory: URL, recursive: Bool) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            throw Failure(
                path: directory.path(percentEncoded: false),
                message: "the directory could not be read"
            )
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                let isRegularFile = values?.isRegularFile ?? false
                return isRegularFile && registry.converter(for: url) != nil
            }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }
}
