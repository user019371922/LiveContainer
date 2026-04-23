//
//  LCAppBanner.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

protocol LCAppBannerDelegate {
    func removeApp(app: LCAppModel)
    func installMdm(data: Data)
    func openNavigationView(view: AnyView)
    func promptForGeneratedIconStyle() async -> GeneratedIconStyle?
}

private enum AppBinaryExportKind: String {
    case dylib = "Dylib"
    case framework = "Framework"
}

private struct AppBinaryExportItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let relativePath: String
    let kind: AppBinaryExportKind
}

struct LCAppBanner : View {
    @State var appInfo: LCAppInfo
    var delegate: LCAppBannerDelegate
    
    @ObservedObject var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    
    @StateObject private var appRemovalAlert = YesNoHelper()
    @StateObject private var appFolderRemovalAlert = YesNoHelper()
    
    @State private var saveIconExporterShow = false
    @State private var saveIconFile : ImageDocument?
    
    @State private var errorShow = false
    @State private var errorInfo = ""

    @State private var showBinaryExportSheet = false
    @State private var binaryExportItems: [AppBinaryExportItem] = []
    @State private var selectedBinaryExportItemIDs: Set<String> = []
    @State private var isExportingBinarySelection = false
    
    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false

    @State private var mainColor : Color
    @State private var icon: UIImage
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(appModel: LCAppModel, delegate: LCAppBannerDelegate, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        _appInfo = State(initialValue: appModel.appInfo)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
        self.delegate = delegate
        
        _model = ObservedObject(wrappedValue: appModel)
        _mainColor = State(initialValue: Color.clear)
        _icon = State(initialValue: appModel.appInfo.iconIsDarkIcon(LCUtils.appGroupUserDefault.bool(forKey: "darkModeIcon")))
        _mainColor = State(initialValue: extractMainHueColor())

    }
    @State private var mainHueColor: CGFloat? = nil
    
    var body: some View {

        HStack {
            HStack {
                IconImageView(icon: icon)
                    .frame(width: 60, height: 60)

                VStack (alignment: .leading, content: {
                    let color = (dynamicColors ? mainColor : Color("FontColor"))
                    // note: keep this so the color updates when toggling dark mode
                    let textColor = colorScheme == .dark ? color.readableTextColor() : color.readableTextColor()
                    HStack {
                        Text(model.displayName).font(.system(size: 16)).bold()
                        if model.uiIsShared {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                        if model.uiIsJITNeeded {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("JITBadgeColor"))
                                )
                        }
#if is32BitSupported
                        if model.uiIs32bit {
                            Text("32")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("32BitBadgeColor"))
                                )
                        }
#endif
                        if model.uiIsLocked && !model.uiIsHidden {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .frame(width: 16, height:16)
                                .background(
                                    Capsule().fill(Color("BadgeColor"))
                                )
                        }
                    }

                    Text("\(model.version) - \(model.bundleIdentifier)").font(.system(size: 12)).foregroundColor(textColor)
                    if !model.uiRemark.isEmpty {
                        Text(model.uiRemark)
                            .font(.system(size: 10))
                            .foregroundColor(textColor.opacity(0.8))
                            .lineLimit(1)
                    }
                    Text(model.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc).font(.system(size: 8)).foregroundColor(textColor)
                })
            }
            .allowsHitTesting(false)
            Spacer()
            Button {
                if #available(iOS 16.0, *) {
                     if let currentDataFolder = model.uiSelectedContainer?.folderName,
                        MultitaskManager.isUsing(container: currentDataFolder) {
                         var found = false
                         if #available(iOS 16.1, *) {
                             found = MultitaskWindowManager.openExistingAppWindow(dataUUID: currentDataFolder)
                         }
                         if !found {
                             found = MultitaskDockManager.shared.bringMultitaskViewToFront(uuid: currentDataFolder)
                         }
                         if found {
                             return
                         }
                     }
                     
                    Task{ await runApp() }
                } else {
                    Task{ await runApp() }
                }
            } label: {
                if !model.isSigningInProgress {
                    Text("lc.appBanner.run".loc).bold().foregroundColor(.white)
                        .lineLimit(1)
                        .frame(height:32)
                        .minimumScaleFactor(0.1)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }

            }
            .buttonStyle(BasicButtonStyle())
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(GeometryReader { g in
                if !model.isSigningInProgress {
                    Capsule().fill(dynamicColors ? mainColor : Color("FontColor"))
                } else {
                    let w = g.size.width
                    let h = g.size.height
                    Capsule()
                        .fill(dynamicColors ? mainColor : Color("FontColor")).opacity(0.2)
                    Circle()
                        .fill(dynamicColors ? mainColor : Color("FontColor"))
                        .frame(width: w * 2, height: w * 2)
                        .offset(x: (model.signProgress - 2) * w, y: h/2-w)
                }

            })
            .clipShape(Capsule())
            .contentShape(Capsule())
            .disabled(model.isAppRunning)
        }
        .padding()
        .frame(height: 88)
        .background {
            RoundedRectangle(cornerSize: CGSize(width:22, height: 22)).fill(dynamicColors ? mainColor.opacity(0.5) : Color("AppBannerBG"))
                .onTapGesture(count: 2) {
                    openSettings()
                }
        }
        .fileExporter(
            isPresented: $saveIconExporterShow,
            document: saveIconFile,
            contentType: .image,
            defaultFilename: "\(appInfo.displayName()!) Icon.png",
            onCompletion: { result in
            
        })
        .betterContextMenu(menuProvider: makeContextMenu)
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $appRemovalAlert.show) {
            Button(role: .destructive) {
                appRemovalAlert.close(result: true)
            } label: {
                Text("lc.appBanner.uninstall".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                appRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $appFolderRemovalAlert.show) {
            Button(role: .destructive) {
                appFolderRemovalAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.no".loc, role: .cancel) {
                appFolderRemovalAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg %@".localizeWithFormat(appInfo.displayName()!))
        }
        
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .sheet(isPresented: $showBinaryExportSheet) {
            NavigationView {
                List(binaryExportItems) { item in
                    Button {
                        toggleBinarySelection(for: item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedBinaryExportItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedBinaryExportItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.relativePath)
                                    .font(.system(.body, design: .monospaced))
                                Text(item.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Export Dylibs & Frameworks")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showBinaryExportSheet = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if !binaryExportItems.isEmpty {
                            Button(selectedBinaryExportItemIDs.count == binaryExportItems.count ? "Unselect All" : "Select All") {
                                if selectedBinaryExportItemIDs.count == binaryExportItems.count {
                                    selectedBinaryExportItemIDs.removeAll()
                                } else {
                                    selectedBinaryExportItemIDs = Set(binaryExportItems.map(\.id))
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isExportingBinarySelection {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Button("Export") {
                                Task { await exportSelectedDylibsAndFrameworks() }
                            }
                            .disabled(selectedBinaryExportItemIDs.isEmpty)
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .onChange(of: darkModeIcon) { newVal in
            icon = appInfo.iconIsDarkIcon(newVal)
            mainColor = extractMainHueColor()
        }
    }
    
    func makeContextMenu() -> UIMenu {
        var menuChildren: [UIMenuElement] = []

        // 1. Containers Picker (Equivalent to a Menu with single selection)
        if model.uiContainers.count > 1 {
            let containerActions = model.uiContainers.map { container in
                UIAction(title: container.name,
                         state: container == model.uiSelectedContainer ? .on : .off) { _ in
                    model.uiSelectedContainer = container
                }
            }
            let containerMenu = UIMenu(title: "Containers", options: .displayInline, children: containerActions)
            menuChildren.append(containerMenu)
        }

        // 2. Main Section
        var sectionChildren: [UIMenuElement] = []

        // Open Data Folder
        if !model.uiIsShared, model.uiSelectedContainer != nil {
            let openFolder = UIAction(title: "lc.appBanner.openDataFolder".loc,
                                      image: UIImage(systemName: "folder")) { _ in
                openDataFolder()
            }
            sectionChildren.append(openFolder)
        }

        // Multitask Toggle
        if #available(iOS 16.0, *) {
            let runTitle = model.shouldLaunchInMultitaskMode ? "lc.appBanner.run".loc : "lc.appBanner.multitask".loc
            let runImage = model.shouldLaunchInMultitaskMode ? "play.fill" : "macwindow.badge.plus"
            
            let multitaskAction = UIAction(title: runTitle, image: UIImage(systemName: runImage)) { _ in
                Task { await runApp(multitask: !model.shouldLaunchInMultitaskMode) }
            }
            sectionChildren.append(multitaskAction)
        }

        // Submenu: Add to Home Screen
        let subMenuActions = [
            UIAction(title: "lc.appBanner.copyLaunchUrl".loc, image: UIImage(systemName: "link")) { _ in
                copyLaunchUrl()
            },
            UIAction(title: "lc.appBanner.saveAppIcon".loc, image: UIImage(systemName: "square.and.arrow.down")) { _ in
                Task { await saveIcon() }
            },
            UIAction(title: "lc.appBanner.createAppClip".loc, image: UIImage(systemName: "appclip")) { _ in
                Task { await openSafariViewToCreateAppClip() }
            }
        ]
        let addToHomeMenu = UIMenu(title: "lc.appBanner.addToHomeScreen".loc,
                                   image: UIImage(systemName: "plus.app"),
                                   children: subMenuActions)
        sectionChildren.append(addToHomeMenu)

        let dataExportDisabled: UIMenuElement.Attributes = model.uiSelectedContainer == nil ? [.disabled] : []
        let exportMenu = UIMenu(
            title: "Export",
            image: UIImage(systemName: "square.and.arrow.up"),
            children: [
                UIAction(
                    title: "Export IPA",
                    image: UIImage(systemName: "shippingbox")
                ) { _ in
                    Task { await exportIPA(includeData: false) }
                },
                UIAction(
                    title: "Export Data",
                    image: UIImage(systemName: "folder.zip"),
                    attributes: dataExportDisabled
                ) { _ in
                    Task { await exportData() }
                },
                UIAction(
                    title: "Export IPA + Data",
                    image: UIImage(systemName: "square.and.arrow.up.on.square"),
                    attributes: dataExportDisabled
                ) { _ in
                    Task { await exportIPA(includeData: true) }
                },
                UIAction(
                    title: "Export Dylibs & Frameworks",
                    image: UIImage(systemName: "list.bullet.rectangle")
                ) { _ in
                    openDylibAndFrameworkExportSelection()
                }
            ]
        )
        sectionChildren.append(exportMenu)

        // Settings
        let settingsAction = UIAction(title: "lc.tabView.settings".loc, image: UIImage(systemName: "gear")) { _ in
            openSettings()
        }
        sectionChildren.append(settingsAction)

        // Destructive Uninstall
        if !model.uiIsShared {
            let uninstallAction = UIAction(title: "lc.appBanner.uninstall".loc,
                                           image: UIImage(systemName: "trash"),
                                           attributes: .destructive) { _ in
                Task { await uninstall() }
            }
            sectionChildren.append(uninstallAction)
        }

        // Wrap the section in an inline menu to mimic SwiftUI Section behavior
        let mainSection = UIMenu(title: appInfo.relativeBundlePath, options: .displayInline, children: sectionChildren)
        menuChildren.append(mainSection)

        return UIMenu(title: "", children: menuChildren)
    }
    
    func runApp(multitask: Bool? = nil) async {
        if appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                if !(try await LCUtils.authenticateUser()) {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }

        do {
            try await model.runApp(multitask: multitask)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func openSettings() {
        delegate.openNavigationView(view: AnyView(LCAppSettingsView(model: model, appDataFolders: $appDataFolders, tweakFolders: $tweakFolders)))
    }
    
    
    func openDataFolder() {
        let url = URL(string:"shareddocuments://\(LCPath.dataPath.path)/\(model.uiSelectedContainer!.folderName)")
        UIApplication.shared.open(url!)
    }
    

    
    func uninstall() async {
        do {
            if let result = await appRemovalAlert.open(), !result {
                return
            }
            
            var doRemoveAppFolder = false
            let containers = appInfo.containers
            if !containers.isEmpty {
                if let result = await appFolderRemovalAlert.open() {
                    doRemoveAppFolder = result
                }
                
            }
            
            let fm = FileManager()
            try fm.removeItem(atPath: self.appInfo.bundlePath()!)
            self.delegate.removeApp(app: self.model)
            if doRemoveAppFolder {
                for container in containers {
                    let dataUUID = container.folderName
                    let dataFolderPath = LCPath.dataPath.appendingPathComponent(dataUUID)
                    try fm.removeItem(at: dataFolderPath)
                    LCUtils.removeAppKeychain(dataUUID: dataUUID)
                    
                    DispatchQueue.main.async {
                        self.appDataFolders.removeAll(where: { f in
                            return f == dataUUID
                        })
                    }
                }
            }
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    
    func copyLaunchUrl() {
        if let fn = model.uiSelectedContainer?.folderName {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)&container-folder-name=\(fn)"
        } else {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(appInfo.relativeBundlePath!)"
        }
        
    }
    
    func openSafariViewToCreateAppClip() async {
        guard let style = await delegate.promptForGeneratedIconStyle() else {
            return
        }
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: appInfo.generateWebClipConfig(withContainerId: model.uiSelectedContainer?.folderName, iconStyle: style)!, format: .xml, options: 0)
            delegate.installMdm(data: data)
        } catch  {
            errorShow = true
            errorInfo = error.localizedDescription
        }

    }
    
    func saveIcon() async {
        guard let style = await delegate.promptForGeneratedIconStyle() else {
            return
        }
        
        let img = appInfo.generateLiveContainerWrappedIcon(with: style)!
        self.saveIconFile = ImageDocument(uiImage: img)
        self.saveIconExporterShow = true
    }

    func exportIPA(includeData: Bool) async {
        do {
            let exportURL = try await createExportIPA(includeData: includeData)
            presentShareSheet(for: exportURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func exportData() async {
        do {
            let exportURL = try await createDataArchive()
            presentShareSheet(for: exportURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func openDylibAndFrameworkExportSelection() {
        do {
            let items = try listExportableBinaries()
            if items.isEmpty {
                throw "No .dylib or .framework items were found in this app bundle."
            }
            binaryExportItems = items
            selectedBinaryExportItemIDs = Set(items.map(\.id))
            showBinaryExportSheet = true
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    private func toggleBinarySelection(for item: AppBinaryExportItem) {
        if selectedBinaryExportItemIDs.contains(item.id) {
            selectedBinaryExportItemIDs.remove(item.id)
        } else {
            selectedBinaryExportItemIDs.insert(item.id)
        }
    }

    func exportSelectedDylibsAndFrameworks() async {
        if isExportingBinarySelection {
            return
        }

        isExportingBinarySelection = true
        defer { isExportingBinarySelection = false }

        do {
            let selectedItems = binaryExportItems.filter { selectedBinaryExportItemIDs.contains($0.id) }
            if selectedItems.isEmpty {
                throw "Select at least one item to export."
            }
            let archiveURL = try await createSelectedBinaryArchive(selectedItems: selectedItems)
            showBinaryExportSheet = false
            try await Task.sleep(nanoseconds: 200_000_000)
            presentShareSheet(for: archiveURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func createExportIPA(includeData: Bool) async throws -> URL {
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
            guard let container = model.uiSelectedContainer else {
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
            let destinationDataURL = destinationAppURL.appendingPathComponent("LCUserData", isDirectory: true)
            try fm.copyItem(at: dataURL, to: destinationDataURL)
        }

        let appName = sanitizedFileStem(appInfo.displayName() ?? "App")
        let fileName = includeData ? "\(appName)-with-data.ipa" : "\(appName).ipa"
        let exportURL = fm.temporaryDirectory.appendingPathComponent(fileName)
        try? fm.removeItem(at: exportURL)

        try await zipDirectory(sourceURL: stagingRoot, destinationURL: exportURL)
        return exportURL
    }

    func createDataArchive() async throws -> URL {
        guard let container = model.uiSelectedContainer else {
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
        guard fm.fileExists(atPath: containerURL.path) else {
            throw "Selected container data does not exist."
        }

        let appName = sanitizedFileStem(appInfo.displayName() ?? "App")
        let containerName = sanitizedFileStem(container.name)
        let exportURL = fm.temporaryDirectory.appendingPathComponent("\(appName)-\(containerName)-data.zip")
        try? fm.removeItem(at: exportURL)

        try await zipDirectory(sourceURL: containerURL, destinationURL: exportURL)
        return exportURL
    }

    private func listExportableBinaries() throws -> [AppBinaryExportItem] {
        guard let bundlePath = appInfo.bundlePath() else {
            throw "Unable to read app bundle path."
        }
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

    private func createSelectedBinaryArchive(selectedItems: [AppBinaryExportItem]) async throws -> URL {
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

        let archiveURL = fm.temporaryDirectory.appendingPathComponent("\(appName)-dylibs-frameworks.zip")
        try? fm.removeItem(at: archiveURL)
        try await zipDirectory(sourceURL: contentRoot, destinationURL: archiveURL)
        return archiveURL
    }

    func zipDirectory(sourceURL: URL, destinationURL: URL) async throws {
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
    func presentShareSheet(for fileURL: URL) {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let keyWindow = scene.windows.first(where: { $0.isKeyWindow }),
              var presenter = keyWindow.rootViewController else {
            return
        }

        while let presentedViewController = presenter.presentedViewController {
            presenter = presentedViewController
        }
        controller.popoverPresentationController?.sourceView = presenter.view
        presenter.present(controller, animated: true)
    }

    func sanitizedFileStem(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Export" : cleaned
    }
    
    func extractMainHueColor() -> Color {
        if !darkModeIcon, let cachedColor = appInfo.cachedColor {
            return Color(uiColor: cachedColor)
        } else if darkModeIcon, let cachedColor = appInfo.cachedColorDark {
            return Color(uiColor: cachedColor)
        }
        
        guard let cgImage = appInfo.iconIsDarkIcon(darkModeIcon).cgImage else { return Color.clear }

        let width = 1
        let height = 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)
        
        guard let context = CGContext(data: &pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return Color.clear
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let red = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let blue = CGFloat(pixelData[2]) / 255.0
        
        let averageColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        if brightness < 0.1 && saturation < 0.1 {
            return Color.red
        }
        
        if brightness < 0.3 {
            brightness = 0.3
        }
        
        let ans = Color(hue: hue, saturation: saturation, brightness: brightness)
        if darkModeIcon {
            appInfo.cachedColorDark = UIColor(ans)
        } else {
            appInfo.cachedColor = UIColor(ans)
        }
        
        
        return ans
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }

}


struct LCAppSkeletonBanner: View {
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 8)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 70, height: 32)
        }
        .padding()
        .frame(height: 88)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.gray.opacity(0.1)))
    }
    
}
