//
//  LCAppBannerExportActions.swift
//  LiveContainerSwiftUI
//

import Foundation
import SwiftUI
import UIKit

extension LCAppBannerViewController {
    func cloneApp() async {
        do {
            let clonedAppModel = try await createClonedAppModel()
            await MainActor.run {
                DataManager.shared.model.apps.append(clonedAppModel)
                showExportSuccess("Cloned app created.")
            }
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        }
    }

    private func createClonedAppModel() async throws -> LCAppModel {
        let fm = FileManager.default
        let appInfo = configuration.model.appInfo
        guard let sourceBundlePath = appInfo.bundlePath() else {
            throw "Unable to read app bundle path."
        }

        let sourceBundleURL = URL(fileURLWithPath: sourceBundlePath, isDirectory: true)
        let targetRootURL = configuration.model.uiIsShared ? LCPath.lcGroupBundlePath : LCPath.bundlePath
        try fm.createDirectory(at: targetRootURL, withIntermediateDirectories: true)

        let cloneRelativeBundlePath = makeCloneRelativeBundlePath(targetRootURL: targetRootURL, fileManager: fm)
        let destinationBundleURL = targetRootURL.appendingPathComponent(cloneRelativeBundlePath, isDirectory: true)

        do {
            try fm.copyItem(at: sourceBundleURL, to: destinationBundleURL)
        } catch {
            throw "Failed to copy app bundle: \(error.localizedDescription)"
        }

        do {
            try resetClonedAppInfo(at: destinationBundleURL, fileManager: fm)
            guard let clonedAppInfo = LCAppInfo(bundlePath: destinationBundleURL.path) else {
                throw "Failed to initialize cloned app."
            }
            clonedAppInfo.relativeBundlePath = cloneRelativeBundlePath
            clonedAppInfo.isShared = configuration.model.uiIsShared
            clonedAppInfo.spoofSDKVersion = true
            clonedAppInfo.installationDate = Date.now
            try await signClonedAppIfNeeded(clonedAppInfo)
            return LCAppModel(appInfo: clonedAppInfo, delegate: configuration.model.delegate)
        } catch {
            try? fm.removeItem(at: destinationBundleURL)
            throw error
        }
    }

    private func makeCloneRelativeBundlePath(targetRootURL: URL, fileManager: FileManager) -> String {
        let appInfo = configuration.model.appInfo
        let bundleIdStem = (appInfo.bundleIdentifier() ?? appInfo.displayName() ?? "ClonedApp").sanitizeNonACSII()
        let stem = bundleIdStem.isEmpty ? "ClonedApp" : bundleIdStem
        let timestamp = Int(Date().timeIntervalSince1970)

        var candidate = "\(stem)_\(timestamp).app"
        var index = 2
        while fileManager.fileExists(atPath: targetRootURL.appendingPathComponent(candidate).path) {
            candidate = "\(stem)_\(timestamp)_\(index).app"
            index += 1
        }
        return candidate
    }

    private func resetClonedAppInfo(at clonedBundleURL: URL, fileManager: FileManager) throws {
        let lcAppInfoPath = clonedBundleURL.appendingPathComponent("LCAppInfo.plist")
        if fileManager.fileExists(atPath: lcAppInfoPath.path) {
            try fileManager.removeItem(at: lcAppInfoPath)
        }

        for fileName in ["LCAppIconLight.png", "LCAppIconDark.png", "zsign_cache.json", "LiveContainer.tmp"] {
            let fileURL = clonedBundleURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func signClonedAppIfNeeded(_ clonedAppInfo: LCAppInfo) async throws {
        var signError: String?
        var signSuccess = false
        await withCheckedContinuation { continuation in
            clonedAppInfo.patchExecAndSignIfNeed(completionHandler: { success, error in
                signSuccess = success
                signError = error
                continuation.resume()
            }, progressHandler: { _ in
            }, forceSign: false)
        }
        if let signError, !signSuccess {
            throw signError.loc
        }
    }

    func exportIPA(includeData: Bool) async {
        do {
            let exportURL = try await createExportIPA(includeData: includeData)
            await MainActor.run {
                presentExportShareSheet(for: exportURL)
            }
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        }
    }

    func exportData() async {
        do {
            let exportURL = try await createDataArchive()
            await MainActor.run {
                presentExportShareSheet(for: exportURL)
            }
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        }
    }

    func openDylibAndFrameworkExportSelection() {
        guard let bundlePath = configuration.model.appInfo.bundlePath() else {
            showError("Unable to read app bundle path.")
            return
        }

        Task { [weak self] in
            do {
                let items = try await Task.detached(priority: .userInitiated) {
                    try lcListExportableBinaries(bundlePath: bundlePath)
                }.value
                await MainActor.run {
                    self?.presentBinaryExportSelection(items: items)
                }
            } catch {
                await MainActor.run {
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func presentBinaryExportSelection(items: [AppBinaryExportItem]) {
        guard presentedViewController == nil else {
            return
        }

        let controller = UIHostingController(
            rootView: LCAppBinaryExportView(
                items: items,
                onCancel: { [weak self] in
                    self?.dismiss(animated: true)
                },
                onExport: { [weak self] selectedItems in
                    self?.dismiss(animated: true) {
                        Task { [weak self] in
                            await self?.exportSelectedDylibsAndFrameworks(selectedItems: selectedItems)
                        }
                    }
                },
                onCopyToTweaks: { [weak self] selectedItems in
                    self?.dismiss(animated: true) {
                        self?.presentCopyToTweaksDestination(selectedItems: selectedItems)
                    }
                }
            )
        )
        controller.modalPresentationStyle = .formSheet
        present(controller, animated: true)
    }

    private func exportSelectedDylibsAndFrameworks(selectedItems: [AppBinaryExportItem]) async {
        do {
            guard !selectedItems.isEmpty else {
                throw "Select at least one item to export."
            }
            let archiveURL = try await createSelectedBinaryArchive(selectedItems: selectedItems)
            await MainActor.run {
                presentExportShareSheet(for: archiveURL)
            }
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func presentCopyToTweaksDestination(selectedItems: [AppBinaryExportItem]) {
        guard !selectedItems.isEmpty else {
            showError("Select at least one item first.")
            return
        }

        let controller = UIHostingController(
            rootView: LCTweaksCopyDestinationView(
                onClose: { [weak self] in
                    self?.dismiss(animated: true)
                },
                onCopyHere: { [weak self] destinationURL in
                    Task { [weak self] in
                        await self?.copySelectedToTweaks(selectedItems: selectedItems, destinationFolderURL: destinationURL)
                    }
                }
            )
            .environmentObject(DataManager.shared.model)
        )
        controller.modalPresentationStyle = .formSheet
        present(controller, animated: true)
    }

    private func copySelectedToTweaks(selectedItems: [AppBinaryExportItem], destinationFolderURL: URL) async {
        do {
            let copiedCount = try copySelectedBinaryItems(selectedItems: selectedItems, to: destinationFolderURL)
            await MainActor.run {
                dismiss(animated: true) {
                    self.showExportSuccess("Copied \(copiedCount) item(s) to \(destinationFolderURL.lastPathComponent).")
                }
            }
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
        }
    }

    private func copySelectedBinaryItems(selectedItems: [AppBinaryExportItem], to destinationFolderURL: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)

        var copiedCount = 0
        for item in selectedItems {
            let proposedURL = destinationFolderURL.appendingPathComponent(item.url.lastPathComponent, isDirectory: item.kind == .framework)
            let destinationURL = nextAvailableCopyURL(for: proposedURL)
            try fm.copyItem(at: item.url, to: destinationURL)
            copiedCount += 1
        }
        return copiedCount
    }

    private func nextAvailableCopyURL(for proposedURL: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: proposedURL.path) {
            return proposedURL
        }

        let pathExtension = proposedURL.pathExtension
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let parentURL = proposedURL.deletingLastPathComponent()

        var index = 2
        while true {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(pathExtension)"
            let candidateURL = parentURL.appendingPathComponent(candidateName, isDirectory: pathExtension == "framework")
            if !fm.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func createExportIPA(includeData: Bool) async throws -> URL {
        let appInfo = configuration.model.appInfo
        guard let bundlePath = appInfo.bundlePath() else {
            throw "Unable to read app bundle path."
        }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("LCAppExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }

        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let payloadDir = stagingRoot.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        let sourceAppURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
        let destinationAppURL = payloadDir.appendingPathComponent(sourceAppURL.lastPathComponent, isDirectory: true)
        try fm.copyItem(at: sourceAppURL, to: destinationAppURL)

        if includeData {
            guard let container = configuration.model.uiSelectedContainer else {
                throw "Select a container before exporting app data."
            }
            let dataURL = container.containerURL
            let needsSecurityAccess = container.storageBookMark != nil
            if needsSecurityAccess && !dataURL.startAccessingSecurityScopedResource() {
                throw "Unable to access selected external container."
            }
            defer {
                if needsSecurityAccess {
                    dataURL.stopAccessingSecurityScopedResource()
                }
            }
            guard fm.fileExists(atPath: dataURL.path) else {
                throw "Selected container data does not exist."
            }
            try copyContainerDataForExport(
                from: dataURL,
                to: destinationAppURL.appendingPathComponent("LCUserData", isDirectory: true)
            )
        }

        let appName = sanitizedFileStem(appInfo.displayName() ?? "App")
        let fileName = includeData ? "\(appName)-with-data.ipa" : "\(appName).ipa"
        let exportURL = try lcExportArtifactFileURL(fileName: fileName, fileManager: fm)
        try? fm.removeItem(at: exportURL)
        try await zipDirectory(sourceURL: stagingRoot, destinationURL: exportURL)
        return exportURL
    }

    private func createDataArchive() async throws -> URL {
        guard let container = configuration.model.uiSelectedContainer else {
            throw "Select a container before exporting data."
        }

        let containerURL = container.containerURL
        let needsSecurityAccess = container.storageBookMark != nil
        if needsSecurityAccess && !containerURL.startAccessingSecurityScopedResource() {
            throw "Unable to access selected external container."
        }
        defer {
            if needsSecurityAccess {
                containerURL.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: containerURL.path, isDirectory: &sourceIsDirectory), sourceIsDirectory.boolValue else {
            throw "Selected container path is not a directory."
        }

        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("LCDataExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let appName = sanitizedFileStem(configuration.model.appInfo.displayName() ?? "App")
        let containerName = sanitizedFileStem(container.name)
        let stagedContainerURL = stagingRoot.appendingPathComponent("\(appName)-\(containerName)-data", isDirectory: true)
        try copyContainerDataForExport(from: containerURL, to: stagedContainerURL)

        let exportURL = try lcExportArtifactFileURL(fileName: "\(appName)-\(containerName)-data.zip", fileManager: fm)
        try? fm.removeItem(at: exportURL)
        try await zipDirectory(sourceURL: stagedContainerURL, destinationURL: exportURL)
        return exportURL
    }

    private func createSelectedBinaryArchive(selectedItems: [AppBinaryExportItem]) async throws -> URL {
        let appInfo = configuration.model.appInfo
        guard appInfo.bundlePath() != nil else {
            throw "Unable to read app bundle path."
        }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("LCBinaryExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }

        let appName = sanitizedFileStem(appInfo.displayName() ?? "App")
        let contentRoot = stagingRoot.appendingPathComponent("\(appName)-dylibs-frameworks", isDirectory: true)
        try fm.createDirectory(at: contentRoot, withIntermediateDirectories: true)

        for item in selectedItems {
            let destinationURL = contentRoot.appendingPathComponent(item.relativePath, isDirectory: item.kind == .framework)
            try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destinationURL)
            try fm.copyItem(at: item.url, to: destinationURL)
        }

        let archiveURL = try lcExportArtifactFileURL(fileName: "\(appName)-dylibs-frameworks.zip", fileManager: fm)
        try? fm.removeItem(at: archiveURL)
        try await zipDirectory(sourceURL: contentRoot, destinationURL: archiveURL)
        return archiveURL
    }

    private func zipDirectory(sourceURL: URL, destinationURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?

            coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinationError) { zippedURL in
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: zippedURL, to: destinationURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let coordinationError {
                continuation.resume(throwing: coordinationError)
            }
        }
    }

    @MainActor
    private func presentExportShareSheet(for fileURL: URL) {
        let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activityController.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.cleanupExportArtifacts()
        }
        present(activityController, animated: true)
    }

    private func cleanupExportArtifacts() {
        try? FileManager.default.removeItem(at: lcExportArtifactDirectoryURL())
    }

    @MainActor
    private func showExportSuccess(_ message: String) {
        guard viewIfLoaded?.window != nil else {
            return
        }
        let alert = UIAlertController(title: "lc.common.success".loc, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "lc.common.ok".loc, style: .default))
        present(alert, animated: true)
    }

    private func sanitizedFileStem(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Export" : cleaned
    }

    private func copyContainerDataForExport(from sourceContainerURL: URL, to destinationContainerURL: URL) throws {
        let fm = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceContainerURL.path, isDirectory: &sourceIsDirectory), sourceIsDirectory.boolValue else {
            throw "Selected container path is not a directory."
        }
        try copyDirectoryForExport(from: sourceContainerURL, to: destinationContainerURL)
    }

    private func copyDirectoryForExport(from sourceDirectoryURL: URL, to destinationDirectoryURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let items = try fm.contentsOfDirectory(
            at: sourceDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileResourceTypeKey],
            options: []
        )

        for itemURL in items {
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileResourceTypeKey])
            if shouldSkipDataExportItem(values: values) {
                continue
            }

            let destinationItemURL = destinationDirectoryURL.appendingPathComponent(itemURL.lastPathComponent, isDirectory: values.isDirectory ?? false)
            if values.isDirectory == true {
                try copyDirectoryForExport(from: itemURL, to: destinationItemURL)
                continue
            }

            do {
                try fm.copyItem(at: itemURL, to: destinationItemURL)
            } catch {
                if shouldIgnoreDataExportCopyError(error, resourceValues: values) {
                    continue
                }
                throw error
            }
        }
    }

    private func shouldSkipDataExportItem(values: URLResourceValues) -> Bool {
        if values.isSymbolicLink == true {
            return true
        }
        if let resourceType = values.fileResourceType {
            switch resourceType {
            case .socket, .characterSpecial, .blockSpecial, .namedPipe, .unknown:
                return true
            default:
                break
            }
        }
        return false
    }

    private func shouldIgnoreDataExportCopyError(_ error: Error, resourceValues: URLResourceValues) -> Bool {
        if shouldSkipDataExportItem(values: resourceValues) {
            return true
        }
        let nsError = error as NSError
        if !isNoSuchFileError(nsError) {
            if nsError.domain == NSPOSIXErrorDomain {
                switch nsError.code {
                case Int(POSIXErrorCode.EINVAL.rawValue),
                     Int(POSIXErrorCode.EPERM.rawValue),
                     Int(POSIXErrorCode.ENOTSUP.rawValue),
                     Int(POSIXErrorCode.EOPNOTSUPP.rawValue):
                    return true
                default:
                    break
                }
            }
            return false
        }
        if resourceValues.isSymbolicLink == true {
            return true
        }
        if let resourceType = resourceValues.fileResourceType {
            return resourceType == .socket || resourceType == .namedPipe
        }
        return false
    }

    private func isNoSuchFileError(_ nsError: NSError) -> Bool {
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == ENOENT
        }
        return false
    }
}
