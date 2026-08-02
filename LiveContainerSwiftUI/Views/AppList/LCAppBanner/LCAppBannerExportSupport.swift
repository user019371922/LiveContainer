//
//  LCAppBannerExportSupport.swift
//  LiveContainerSwiftUI
//

import Foundation

enum AppBinaryExportKind: String, Sendable {
    case dylib = "Dylib"
    case framework = "Framework"
}

struct AppBinaryExportItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let relativePath: String
    let kind: AppBinaryExportKind
}

private let lcExportArtifactDirectoryName = "LCExports"

func lcExportArtifactDirectoryURL(fileManager: FileManager = .default) -> URL {
    fileManager.temporaryDirectory.appendingPathComponent(lcExportArtifactDirectoryName, isDirectory: true)
}

func lcEnsureExportArtifactDirectory(fileManager: FileManager = .default) throws -> URL {
    let directoryURL = lcExportArtifactDirectoryURL(fileManager: fileManager)
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        try fileManager.removeItem(at: directoryURL)
    }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

func lcExportArtifactFileURL(fileName: String, fileManager: FileManager = .default) throws -> URL {
    let directoryURL = try lcEnsureExportArtifactDirectory(fileManager: fileManager)
    return directoryURL.appendingPathComponent(fileName)
}

func lcListExportableBinaries(bundlePath: String) throws -> [AppBinaryExportItem] {
    let rootURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
    let fm = FileManager.default

    guard let enumerator = fm.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var items: [AppBinaryExportItem] = []
    var seenPaths = Set<String>()
    let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

    for case let itemURL as URL in enumerator {
        let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values.isDirectory ?? false

        if isDirectory && itemURL.pathExtension.lowercased() == "framework" {
            let relativePath = itemURL.path.hasPrefix(rootPrefix) ? String(itemURL.path.dropFirst(rootPrefix.count)) : itemURL.lastPathComponent
            if seenPaths.insert(relativePath).inserted {
                items.append(AppBinaryExportItem(id: "framework:\(relativePath)", url: itemURL, relativePath: relativePath, kind: .framework))
            }
            enumerator.skipDescendants()
            continue
        }

        if !isDirectory && itemURL.pathExtension.lowercased() == "dylib" {
            let relativePath = itemURL.path.hasPrefix(rootPrefix) ? String(itemURL.path.dropFirst(rootPrefix.count)) : itemURL.lastPathComponent
            if seenPaths.insert(relativePath).inserted {
                items.append(AppBinaryExportItem(id: "dylib:\(relativePath)", url: itemURL, relativePath: relativePath, kind: .dylib))
            }
        }
    }

    return items.sorted { lhs, rhs in
        if lhs.kind == rhs.kind {
            return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
