//
//  LCAppSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/9/16.
//

import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LCAppSettingsView: View {
    @State private var documentPickerCoordinator = DocumentPickerCoordinator()

    private class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentPicked: ((URL) -> Void)?

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked?(url)
        }
    }
    
    private var appInfo : LCAppInfo
    
    @ObservedObject private var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    

    @StateObject private var renameFolderInput = InputHelper()
    @StateObject private var moveToAppGroupAlert = YesNoHelper()
    @StateObject private var moveToPrivateDocAlert = YesNoHelper()
    @StateObject private var signUnsignedAlert = YesNoHelper()
    @StateObject private var addExternalNonLocalContainerWarningAlert = YesNoHelper()
    @State var choosingStorage = false
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var successShow = false
    @State private var successInfo = ""
    @State private var selectUnusedContainerSheetShow = false
    
    @State private var appOriginalSizeBytes: Int64?
    @State private var appDataSizeBytes: Int64?
    @State private var appTotalSizeBytes: Int64?
    @State private var isStorageLoading = false
    @State private var isClearingCacheAndTemp = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(model: LCAppModel, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        self.appInfo = model.appInfo
        self._model = ObservedObject(wrappedValue: model)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("lc.appSettings.bundleId".loc)
                    Spacer()
                    Text(appInfo.relativeBundlePath)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("lc.appSettings.remark".loc)
                    Spacer()
                    TextField("lc.appSettings.remarkPlaceholder".loc, text: $model.uiRemark)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                }
                if !model.uiIsShared {
                    Menu {
                        Picker(selection: $model.uiTweakFolder , label: Text("")) {
                            Label("lc.common.none".loc, systemImage: "nosign").tag(Optional<String>(nil))
                            ForEach(tweakFolders, id:\.self) { folderName in
                                Text(folderName).tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("lc.appSettings.tweakFolder".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiTweakFolder == nil ? "None" : model.uiTweakFolder!)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    
                } else {
                    HStack {
                        Text("lc.appSettings.tweakFolder".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiTweakFolder == nil ? "lc.common.none".loc : model.uiTweakFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !model.uiIsShared {
                    if LCUtils.isAppGroupAltStoreLike() || LCUtils.store() == .ADP {
                        Button("lc.appSettings.toSharedApp".loc) {
                            Task { await moveToAppGroup()}
                        }
                    }
                } else if sharedModel.multiLCStatus != 2 {
                    Button("lc.appSettings.toPrivateApp".loc) {
                        Task { await movePrivateDoc() }
                    }
                }
            } header: {
                Text("lc.common.data".loc)
            }
            
            Section {
                List{
                    ForEach(model.uiContainers.indices, id:\.self) { i in
                        NavigationLink {
                            LCContainerView(container: model.uiContainers[i], uiDefaultDataFolder: $model.uiDefaultDataFolder, delegate: self)
                        } label: {
                            Text(model.uiContainers[i].name)
                        }
                    }
                }
                if(model.uiContainers.count < SharedModel.keychainAccessGroupCount) {
                    Button {
                        Task{ await createFolder() }
                    } label: {
                        Text("lc.appSettings.newDataFolder".loc)
                    }
                    Button {
                        choosingStorage = true
                    } label: {
                        Text("lc.appSettings.selectExternalStorage".loc)
                    }
                    if(!model.uiIsShared) {
                        Button {
                            selectUnusedContainerSheetShow = true
                        } label: {
                            Text("lc.container.selectUnused".loc)
                        }
                    }
                }
                
            } header: {
                Text("lc.common.container".loc)
            }
            
            
            Section {
                Toggle(isOn: $model.uiIsJITNeeded) {
                    Text("lc.appSettings.launchWithJit".loc)
                }
                if #available(iOS 26.0, *), model.uiIsJITNeeded {
                    HStack {
                        Text("lc.appSettings.jit26.script".loc)
                        Spacer()
                        if let base64String = model.jitLaunchScriptJs, !base64String.isEmpty {
                            // Show a generic name since we're not storing the filename
                            Text("lc.appSettings.jit26.scriptLoaded".loc)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.primary)

                            Button(action: {
                                model.jitLaunchScriptJs = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Text("No file selected")
                                .foregroundColor(.gray)
                        }
                        Button(action: {
                            // This will trigger the file picker
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.javaScript], asCopy: true)
                            picker.allowsMultipleSelection = false
                            documentPickerCoordinator.onDocumentPicked = { url in
                                do {
                                    let data = try Data(contentsOf: url)
                                    // Store the Base64-encoded string of the file content
                                    model.jitLaunchScriptJs = data.base64EncodedString()
                                } catch {
                                    errorInfo = "Failed to read file: \(error.localizedDescription)"
                                    errorShow = true
                                }
                            }
                            picker.delegate = documentPickerCoordinator

                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootViewController = windowScene.windows.first?.rootViewController {
                                rootViewController.present(picker, animated: true)
                            }
                        }) {
                            Text("lc.common.select".loc)
                        }
                    }
                }
            } footer: {

                    if #available(iOS 26.0, *), model.uiIsJITNeeded {
                        Text("lc.appSettings.launchWithJitDesc".loc + "\n" + "lc.appSettings.jit26.scriptDesc".loc)

                    } else {
                        Text("lc.appSettings.launchWithJitDesc".loc)
                    }
                
            }

            Section {
                Toggle(isOn: $model.uiIsLocked) {
                    Text("lc.appSettings.lockApp".loc)
                }
                .onChange(of: model.uiIsLocked, perform: { newValue in
                    Task { await model.setLocked(newLockState: newValue) }
                })

                if model.uiIsLocked {
                    Toggle(isOn: $model.uiIsHidden) {
                        Text("lc.appSettings.hideApp".loc)
                    }
                    .onChange(of: model.uiIsHidden, perform: { _ in
                        Task { await toggleHidden() }
                    })
                    .transition(.opacity.combined(with: .slide)) 
                }
            } footer: {
                if model.uiIsLocked {
                    Text("lc.appSettings.hideAppDesc".loc)
                        .transition(.opacity.combined(with: .slide))
                }
            }
            
            if #available(iOS 16.0, *) {
                Section {
                    Picker(selection: $model.uiIsMultitaskModeSpecificed) {
                        Text("lc.common.default".loc).tag(MultitaskSpecified.default)
                        Text("lc.common.no".loc).tag(MultitaskSpecified.no)
                        Text("lc.common.yes".loc).tag(MultitaskSpecified.yes)
                    } label: {
                        Text("lc.appBanner.multitask".loc)
                    }
                }
            }
            
            Section {
                NavigationLink {
                    if let supportedLanguage = model.supportedLanguages {
                        Form {
                            Picker(selection: $model.uiSelectedLanguage) {
                                Text("lc.common.auto".loc).tag("")
                                
                                ForEach(supportedLanguage, id:\.self) { language in
                                    if language != "Base" {
                                        VStack(alignment: .leading) {
                                            Text(Locale(identifier: language).localizedString(forIdentifier: language) ?? language)
                                            Text("\(Locale.current.localizedString(forIdentifier: language) ?? "") - \(language)")
                                                .font(.footnote)
                                                .foregroundStyle(.gray)
                                        }
                                        .tag(language)
                                    }

                                }
                            } label: {
                                Text("lc.common.language".loc)
                            }
                            .pickerStyle(.inline)
                        }

                    } else {
                        Text("lc.common.loading".loc)
                            .onAppear() {
                                Task{ loadSupportedLanguages() }
                            }
                    }
                } label: {
                    HStack {
                        Text("lc.common.language".loc)
                        Spacer()
                        if model.uiSelectedLanguage == "" {
                            Text("lc.common.auto".loc)
                                .foregroundStyle(.gray)
                        } else {
                            Text(Locale.current.localizedString(forIdentifier: model.uiSelectedLanguage) ?? model.uiSelectedLanguage)
                                .foregroundStyle(.gray)
                        }
                    }
                    
                }
            }
            
            Section {
                Toggle(isOn: $model.uiFixFilePickerNew) {
                    Text("lc.appSettings.fixFilePickerNew".loc)
                }
                Toggle(isOn: $model.uiFixLocalNotification) {
                    Text("lc.appSettings.fixLocalNotification".loc)
                }
                Toggle(isOn: $model.uiUseLCBundleId) {
                    Text("lc.appSettings.useLCBundleId".loc)
                }
            } header: {
                Text("lc.appSettings.fixes".loc)
            } footer: {
                Text("lc.appSettings.useLCBundleIdDesc".loc)
            }
            
            if SharedModel.isPhone {
                Section {
                    Picker(selection: $model.uiOrientationLock) {
                        Text("lc.common.disabled".loc).tag(LCOrientationLock.Disabled)
                        Text("lc.apppSettings.orientationLock.landscape".loc).tag(LCOrientationLock.Landscape)
                        Text("lc.apppSettings.orientationLock.portrait".loc).tag(LCOrientationLock.Portrait)
                    } label: {
                        Text("lc.apppSettings.orientationLock".loc)
                    }
                }
            }
            
            Section {
                Toggle(isOn: $model.uiHideLiveContainer) {
                    Text("lc.appSettings.hideLiveContainer".loc)
                }

                Toggle(isOn: $model.uiDontInjectTweakLoader) {
                    Text("lc.appSettings.dontInjectTweakLoader".loc)
                }.disabled(model.uiTweakLoaderInjectFailed)
                
                if model.uiDontInjectTweakLoader {
                    Toggle(isOn: $model.uiDontLoadTweakLoader) {
                        Text("lc.appSettings.dontLoadTweakLoader".loc)
                    }
                }
                
            } footer: {
                Text("lc.appSettings.hideLiveContainerDesc".loc)
            }
            
            Section {
                Toggle(isOn: $model.uiSpoofSDKVersion) {
                    Text("lc.appSettings.spoofSDKVersion".loc)
                }
            } footer: {
                Text("lc.appSettings.fspoofSDKVersionDesc".loc)
            }

            
            Section {
                Toggle(isOn: $model.uiDoSymlinkInbox) {
                    Text("lc.appSettings.fixFilePicker".loc)
                }
            } footer: {
                Text("lc.appSettings.fixFilePickerDesc".loc)
            }
            
            Section {
                Button("lc.appSettings.forceSign".loc) {
                    Task { await forceResign() }
                }
                .disabled(model.isAppRunning)
            } footer: {
                Text("lc.appSettings.forceSignDesc".loc)
            }

            Section {
                if isStorageLoading {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("lc.storage.calculating".loc)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    storageRow(title: "App Original Size", bytes: appOriginalSizeBytes)
                    storageRow(title: "App Data", bytes: appDataSizeBytes)
                    storageRow(title: "Total", bytes: appTotalSizeBytes, emphasize: true)
                }

                Button {
                    Task { await clearAppCacheAndTemp() }
                } label: {
                    if isClearingCacheAndTemp {
                        HStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Clearing...")
                        }
                    } else {
                        Text("Clear Cache & Temp")
                    }
                }
                .disabled(isClearingCacheAndTemp || isStorageLoading)
                
                Toggle("Auto Clean Cache & Temp on Launch", isOn: $model.uiAutoCleanCacheOnLaunch)
                
                if model.uiAutoCleanCacheOnLaunch {
                    storageRow(title: "Saved This Week", bytes: appInfo.autoCleanBytesSaved(inLastDays: 7))
                    storageRow(title: "Saved This Month", bytes: appInfo.autoCleanBytesSaved(inLastDays: 30))
                    storageRow(title: "Saved Total", bytes: appInfo.autoCleanTotalBytesSaved)
                    storageRow(title: "Last Clean Saved", bytes: appInfo.lastAutoCleanBytesSaved())
                    HStack {
                        Text("Last Cleaned")
                        Spacer()
                        Text(formatDate(date: appInfo.lastAutoCleanDate))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        resetAutoCleanStats()
                    } label: {
                        Text("Reset Auto-Clean Stats")
                    }
                }
            } header: {
                Text("App Storage")
            } footer: {
                Text("Clears app cache files and temporary folders. Auto-clean runs at launch for apps that enable it.")
            }
            
            Section {
                HStack {
                    Text("lc.appList.sort.lastLaunched".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.lastLaunched))
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("lc.appList.sort.installationDate".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.installationDate))
                        .foregroundStyle(.gray)
                }
            } header: {
                Text("lc.common.statistics")
            }

        }
        .navigationTitle(appInfo.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        .alert("lc.common.success".loc, isPresented: $successShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(successInfo)
        }
        
        .textFieldAlert(
            isPresented: $renameFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $renameFolderInput.initVal,
            placeholder: "",
            action: { newText in
                renameFolderInput.close(result: newText!)
            },
            actionCancel: {_ in
                renameFolderInput.close(result: "")
            }
        )
        .alert("lc.appSettings.toSharedApp".loc, isPresented: $moveToAppGroupAlert.show) {
            Button {
                self.moveToAppGroupAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToAppGroupAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toSharedAppDesc".loc)
        }
        .alert("lc.appSettings.toPrivateApp".loc, isPresented: $moveToPrivateDocAlert.show) {
            Button {
                self.moveToPrivateDocAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToPrivateDocAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toPrivateAppDesc".loc)
        }
        .alert("lc.appSettings.forceSign".loc, isPresented: $signUnsignedAlert.show) {
            Button {
                self.signUnsignedAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.signUnsignedAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.signUnsignedDesc".loc)
        }
        .alert("lc.appSettings.addExternalNonLocalContainer".loc, isPresented: $addExternalNonLocalContainerWarningAlert.show) {
            Button {
                self.addExternalNonLocalContainerWarningAlert.close(result: true)
            } label: {
                Text("lc.common.continue".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.addExternalNonLocalContainerWarningAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.addExternalNonLocalContainerWarningAlert".loc)
        }
        .sheet(isPresented: $selectUnusedContainerSheetShow) {
            LCSelectContainerView(isPresent: $selectUnusedContainerSheetShow, delegate: self)
        }
        .fileImporter(isPresented: $choosingStorage, allowedContentTypes: [.folder]) { result in
            Task { await importDataStorage(result: result) }
        }
        .task(id: model.uiContainers.count) {
            await refreshAppStorageMetrics()
        }
    }

    @ViewBuilder
    func storageRow(title: String, bytes: Int64?, emphasize: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatStorageSize(bytes))
                .font(emphasize ? .body.weight(.semibold) : .body)
                .foregroundStyle(.secondary)
        }
    }

    func formatStorageSize(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "lc.common.unknown".loc
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func refreshAppStorageMetrics() async {
        guard !isStorageLoading else {
            return
        }
        guard let bundlePath = appInfo.bundlePath() else {
            appOriginalSizeBytes = nil
            appDataSizeBytes = nil
            appTotalSizeBytes = nil
            return
        }

        isStorageLoading = true
        defer { isStorageLoading = false }

        let containerTargets = model.uiContainers.map { container in
            LCAppContainerTarget(url: container.containerURL, needsSecurityScope: container.storageBookMark != nil)
        }

        do {
            let metrics = try await Task.detached(priority: .utility) {
                try lcCalculateAppStorageMetrics(bundlePath: bundlePath, containerTargets: containerTargets)
            }.value
            appOriginalSizeBytes = metrics.appOriginalSize
            appDataSizeBytes = metrics.appDataSize
            appTotalSizeBytes = metrics.totalSize
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func clearAppCacheAndTemp() async {
        guard !isClearingCacheAndTemp else {
            return
        }
        guard let bundlePath = appInfo.bundlePath() else {
            errorInfo = "Cannot locate app bundle path."
            errorShow = true
            return
        }

        isClearingCacheAndTemp = true
        defer { isClearingCacheAndTemp = false }

        let containerTargets = model.uiContainers.map { container in
            LCAppContainerTarget(url: container.containerURL, needsSecurityScope: container.storageBookMark != nil)
        }

        do {
            let cleanupResult = try await Task.detached(priority: .utility) {
                try lcClearAppCacheAndTemp(bundlePath: bundlePath, containerTargets: containerTargets)
            }.value
            appInfo.clearIconCache()
            if cleanupResult.removedItemCount > 0 {
                successInfo = "Cleared \(cleanupResult.removedItemCount) cache/temp item(s), freed \(formatStorageSize(cleanupResult.removedBytes))."
            } else {
                successInfo = "No cache/temp files were found."
            }
            successShow = true
            await refreshAppStorageMetrics()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func resetAutoCleanStats() {
        appInfo.resetAutoCleanStats()
        model.objectWillChange.send()
        successInfo = "Auto-clean stats reset."
        successShow = true
    }

    func createFolder() async {
        let newName = NSUUID().uuidString
        guard let displayName = await renameFolderInput.open(initVal: newName), displayName != "" else {
            return
        }
        let fm = FileManager()
        let dest : URL
        if model.uiIsShared {
            dest = LCPath.lcGroupDataPath.appendingPathComponent(newName)
        } else {
            dest = LCPath.dataPath.appendingPathComponent(newName)
        }
        
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        self.appDataFolders.append(newName)
        let newContainer = LCContainer(folderName: newName, name: displayName, isShared: model.uiIsShared)
        // assign keychain group
        var keychainGroupSet : Set<Int> = Set(minimumCapacity: 3)
        for i in 0..<SharedModel.keychainAccessGroupCount {
            keychainGroupSet.insert(i)
        }
        for container in model.uiContainers {
            keychainGroupSet.remove(container.keychainGroupId)
        }
        guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
            errorInfo = "lc.container.notEnoughKeychainGroup".loc
            errorShow = true
            return
        }
        
        model.uiContainers.append(newContainer)
        if model.uiSelectedContainer == nil {
            model.uiSelectedContainer = newContainer;
        }
        if model.uiDefaultDataFolder == nil {
            model.uiDefaultDataFolder = newName
            appInfo.dataUUID = newName
        }
        appInfo.containers = model.uiContainers;
        newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
    }
    
    func importDataStorage(result: Result<URL, any Error>) async {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                errorInfo = "unable to access directory, startAccessingSecurityScopedResource returns false"
                errorShow = true
                return
            }
            let path = url.path
            let fm = FileManager.default
            let _ = try fm.contentsOfDirectory(atPath: path)

            let v = try url.resourceValues(forKeys: [
                .volumeIsLocalKey,
                .volumeIsInternalKey,
            ])
            if !(v.volumeIsLocal == true && v.volumeIsInternal == true) {
                guard let doAdd = await addExternalNonLocalContainerWarningAlert.open(), doAdd else {
                    return
                }
            }
            
            guard let bookmark = LCUtils.bookmark(for: url) else {
                errorInfo = "Unable to generate a bookmark for the selected URL!"
                errorShow = true
                return
            }
            
            var container: LCContainer? = nil
            if fm.fileExists(atPath: url.appendingPathComponent("LCContainerInfo.plist").path) {
                let plistInfo = try PropertyListSerialization.propertyList(from: Data(contentsOf: url.appendingPathComponent("LCContainerInfo.plist")), format: nil)
                if let plistInfo = plistInfo as? [String : Any] {
                    let name = plistInfo["folderName"] as? String ?? url.lastPathComponent
                    container = LCContainer(infoDict: ["folderName": url.lastPathComponent, "name": name, "bookmarkData":bookmark], isShared: false)
                }
            }
            if container == nil {
                // it's an empty folder, we assign a new keychain group to it.
                container = LCContainer(infoDict: ["folderName": url.lastPathComponent, "name": url.lastPathComponent, "bookmarkData": bookmark], isShared: false)
                // assign keychain group
                var keychainGroupSet : Set<Int> = Set(minimumCapacity: 3)
                for i in 0..<SharedModel.keychainAccessGroupCount {
                    keychainGroupSet.insert(i)
                }
                for container in model.uiContainers {
                    keychainGroupSet.remove(container.keychainGroupId)
                }
                guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
                    errorInfo = "lc.container.notEnoughKeychainGroup".loc
                    errorShow = true
                    return
                }
                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if container!.bookmarkResolved {
                        container!.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
                    }
//                }
            }
            model.uiContainers.append(container!)
            appInfo.containers = model.uiContainers;
            if model.uiSelectedContainer == nil {
                model.uiSelectedContainer = container;
            }
            if model.uiDefaultDataFolder == nil {
                model.uiDefaultDataFolder = url.lastPathComponent
                appInfo.dataUUID = url.lastPathComponent
            }

        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func moveToAppGroup() async {
        guard let result = await moveToAppGroupAlert.open(), result else {
            return
        }
        
        do {
            try LCPath.ensureAppGroupPaths()
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                if container.storageBookMark != nil {
                    continue
                }
                
                try fm.moveItem(at: LCPath.dataPath.appendingPathComponent(container.folderName),
                                to: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName))
                appDataFolders.removeAll(where: { s in
                    return s == container.folderName
                })
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.tweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.removeAll(where: { s in
                    return s == tweakFolder
                })
            }
            appInfo.setBundlePath(LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = true
            model.uiIsShared = true
            for container in model.uiContainers {
                container.isShared = true
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func movePrivateDoc() async {
        for container in appInfo.containers {
            if let runningLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {                
                errorInfo = "lc.appSettings.appOpenInOtherLc %@ %@".localizeWithFormat(runningLC, runningLC)
                errorShow = true
                return
            }
        }

        guard let result = await moveToPrivateDocAlert.open(), result else {
            return
        }
        
        do {
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                if container.storageBookMark != nil {
                    continue
                }
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName),
                                to: LCPath.dataPath.appendingPathComponent(container.folderName))
                appDataFolders.append(container.folderName)
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.tweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.append(tweakFolder)
                model.uiTweakFolder = tweakFolder
            }
            appInfo.setBundlePath(LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = false
            model.uiIsShared = false
            for container in model.uiContainers {
                container.isShared = false
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
        
    }
    
    func loadSupportedLanguages() {
        do {
            try model.loadSupportedLanguages()
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
    }
    
    func toggleHidden() async {
        await model.toggleHidden()
    }
    
    func forceResign() async {
        if model.uiDontSign {
            guard let result = await signUnsignedAlert.open(), result else {
                return
            }
            model.uiDontSign = false
        }
        
        do {
            try await model.forceResign()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func formatDate(date: Date?) -> String {
        guard let date else {
            return "lc.common.unknown".loc
        }
        
        let formatter1 = DateFormatter()
        formatter1.dateStyle = .short
        formatter1.timeStyle = .medium
        return formatter1.string(from: date)
    
    }
}

struct LCAppContainerTarget: Sendable {
    let url: URL
    let needsSecurityScope: Bool
}

struct LCAppStorageMetrics: Sendable {
    let appOriginalSize: Int64
    let appDataSize: Int64
    let totalSize: Int64
}

struct LCCacheCleanupResult: Sendable {
    let removedItemCount: Int
    let removedBytes: Int64
    
    static let empty = LCCacheCleanupResult(removedItemCount: 0, removedBytes: 0)
    
    static func +(lhs: LCCacheCleanupResult, rhs: LCCacheCleanupResult) -> LCCacheCleanupResult {
        LCCacheCleanupResult(
            removedItemCount: lhs.removedItemCount + rhs.removedItemCount,
            removedBytes: lhs.removedBytes + rhs.removedBytes
        )
    }
}

func lcCalculateAppStorageMetrics(bundlePath: String, containerTargets: [LCAppContainerTarget]) throws -> LCAppStorageMetrics {
    let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
    let appBundleSize = (try? lcCalculateItemSize(at: bundleURL)) ?? 0
    let generatedCacheSize = lcCalculateGeneratedBundleCacheSize(bundleURL: bundleURL)
    let appOriginalSize = max(0, appBundleSize - generatedCacheSize)

    var appDataSize: Int64 = 0
    for target in containerTargets {
        let didAccess: Bool
        if target.needsSecurityScope {
            didAccess = target.url.startAccessingSecurityScopedResource()
            if !didAccess {
                continue
            }
        } else {
            didAccess = false
        }

        appDataSize += (try? lcCalculateItemSize(at: target.url)) ?? 0

        if didAccess {
            target.url.stopAccessingSecurityScopedResource()
        }
    }

    return LCAppStorageMetrics(
        appOriginalSize: appOriginalSize,
        appDataSize: appDataSize,
        totalSize: appOriginalSize + appDataSize
    )
}

func lcCalculateGeneratedBundleCacheSize(bundleURL: URL) -> Int64 {
    let generatedCacheFileNames = [
        "LCAppIconLight.png",
        "LCAppIconDark.png",
        "zsign_cache.json",
        "LiveContainer.tmp"
    ]
    return generatedCacheFileNames.reduce(into: Int64(0)) { partialResult, fileName in
        let fileURL = bundleURL.appendingPathComponent(fileName)
        partialResult += (try? lcCalculateItemSize(at: fileURL)) ?? 0
    }
}

func lcCalculateItemSize(at url: URL) throws -> Int64 {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return 0
    }

    let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    if !isDirectory.boolValue {
        do {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                return 0
            }
            let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            return Int64(fileSize)
        } catch {
            if lcIsNoSuchFileError(error) {
                return 0
            }
            throw error
        }
    }

    guard let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [],
        errorHandler: nil
    ) else {
        return 0
    }

    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
        do {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }
            let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            totalSize += Int64(fileSize)
        } catch {
            if lcIsNoSuchFileError(error) {
                continue
            }
            throw error
        }
    }
    return totalSize
}

func lcClearAppCacheAndTemp(bundlePath: String, containerTargets: [LCAppContainerTarget]) throws -> LCCacheCleanupResult {
    let bundleURL = URL(fileURLWithPath: bundlePath, isDirectory: true)
    var cleanupResult = LCCacheCleanupResult.empty
    
    cleanupResult = cleanupResult + (try lcRemoveItemIfExists(at: bundleURL.appendingPathComponent("LCAppIconLight.png")))
    cleanupResult = cleanupResult + (try lcRemoveItemIfExists(at: bundleURL.appendingPathComponent("LCAppIconDark.png")))
    cleanupResult = cleanupResult + (try lcRemoveItemIfExists(at: bundleURL.appendingPathComponent("zsign_cache.json")))
    cleanupResult = cleanupResult + (try lcRemoveItemIfExists(at: bundleURL.appendingPathComponent("LiveContainer.tmp")))

    for target in containerTargets {
        let didAccess: Bool
        if target.needsSecurityScope {
            didAccess = target.url.startAccessingSecurityScopedResource()
            if !didAccess {
                continue
            }
        } else {
            didAccess = false
        }

        cleanupResult = cleanupResult + (try lcClearDirectoryContentsIfExists(at: target.url.appendingPathComponent("Library/Caches", isDirectory: true)))
        cleanupResult = cleanupResult + (try lcClearDirectoryContentsIfExists(at: target.url.appendingPathComponent("tmp", isDirectory: true)))

        if didAccess {
            target.url.stopAccessingSecurityScopedResource()
        }
    }

    return cleanupResult
}

func lcClearDirectoryContentsIfExists(at directoryURL: URL) throws -> LCCacheCleanupResult {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
        return .empty
    }
    guard isDirectory.boolValue else {
        let removedSize = (try? lcCalculateItemSize(at: directoryURL)) ?? 0
        do {
            try fm.removeItem(at: directoryURL)
        } catch {
            if lcIsNoSuchFileError(error) {
                return .empty
            }
            throw error
        }
        return LCCacheCleanupResult(removedItemCount: 1, removedBytes: removedSize)
    }

    let items: [URL]
    do {
        items = try fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
    } catch {
        if lcIsNoSuchFileError(error) {
            return .empty
        }
        throw error
    }
    var removedBytes: Int64 = 0
    for item in items {
        removedBytes += (try? lcCalculateItemSize(at: item)) ?? 0
        do {
            try fm.removeItem(at: item)
        } catch {
            if lcIsNoSuchFileError(error) {
                continue
            }
            throw error
        }
    }
    return LCCacheCleanupResult(removedItemCount: items.count, removedBytes: removedBytes)
}

func lcRemoveItemIfExists(at url: URL) throws -> LCCacheCleanupResult {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
        return .empty
    }
    let removedSize = (try? lcCalculateItemSize(at: url)) ?? 0
    do {
        try fm.removeItem(at: url)
    } catch {
        if lcIsNoSuchFileError(error) {
            return .empty
        }
        throw error
    }
    return LCCacheCleanupResult(removedItemCount: 1, removedBytes: removedSize)
}

private func lcIsNoSuchFileError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
        return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
    }
    if nsError.domain == NSPOSIXErrorDomain {
        return nsError.code == Int(POSIXErrorCode.ENOENT.rawValue)
    }
    return false
}



extension LCAppSettingsView : LCContainerViewDelegate {
    func isTweakLoaderInjectionDisabled() -> Bool {
        model.uiDontInjectTweakLoader
    }

    func getBundleId() -> String {
        return model.appInfo.bundleIdentifier()!
    }
    
    func unbindContainer(container: LCContainer) {
        model.uiContainers.removeAll { c in
            c === container
        }
        
        // if the deleted container is the default one, we change to another one
        if container.folderName == model.uiDefaultDataFolder && !model.uiContainers.isEmpty{
            setDefaultContainer(container: model.uiContainers[0])
        }
        // if the deleted container is the selected one, we change to the default one
        if model.uiSelectedContainer === container && !model.uiContainers.isEmpty {
            for container in model.uiContainers {
                if container.folderName == model.uiDefaultDataFolder {
                    model.uiSelectedContainer = container
                    break
                }
            }
        }
        
        if model.uiContainers.isEmpty {
            model.uiSelectedContainer = nil
            model.uiDefaultDataFolder = nil
            appInfo.dataUUID = nil
        }
        appInfo.containers = model.uiContainers
    }
    
    func setDefaultContainer(container newDefaultContainer: LCContainer ) {
        if model.uiSelectedContainer?.folderName == model.uiDefaultDataFolder {
            model.uiSelectedContainer = newDefaultContainer
        }
        
        appInfo.dataUUID = newDefaultContainer.folderName
        model.uiDefaultDataFolder = newDefaultContainer.folderName
    }
    
    func saveContainer(container: LCContainer) {
        container.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: container.keychainGroupId)
        appInfo.containers = model.uiContainers
        model.objectWillChange.send()
    }
    
    func getSettingsBundle() -> Bundle? {
        return Bundle(url: URL(fileURLWithPath: appInfo.bundlePath()).appendingPathComponent("Settings.bundle"))
    }
    
    func getContainerURL(container: LCContainer) -> URL {
        let preferencesFolderUrl = container.containerURL.appendingPathComponent("Library/Preferences")
        let fm = FileManager.default
        do {
            let doExist = fm.fileExists(atPath: preferencesFolderUrl.path)
            if !doExist {
                try fm.createDirectory(at: preferencesFolderUrl, withIntermediateDirectories: true)
            }

        } catch {
            errorInfo = "Cannot create Library/Preferences folder!".loc
            errorShow = true
        }
        return container.containerURL
    }
    
}

extension LCAppSettingsView : LCSelectContainerViewDelegate {
    func addContainers(containers: Set<String>) {
        if containers.count + model.uiContainers.count > SharedModel.keychainAccessGroupCount {
            errorInfo = "lc.container.tooMuchContainers".loc
            errorShow = true
            return
        }
        
        for folderName in containers {
            let newContainer = LCContainer(folderName: folderName, name: folderName, isShared: false)
            newContainer.loadName()
            if newContainer.keychainGroupId == -1 {
                // assign keychain group for old containers
                var keychainGroupSet : Set<Int> = Set(minimumCapacity: SharedModel.keychainAccessGroupCount)
                for i in 0..<SharedModel.keychainAccessGroupCount {
                    keychainGroupSet.insert(i)
                }
                for container in model.uiContainers {
                    keychainGroupSet.remove(container.keychainGroupId)
                }
                guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
                    errorInfo = "lc.container.notEnoughKeychainGroup".loc
                    errorShow = true
                    return
                }
                newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
            }

            
            model.uiContainers.append(newContainer)
            if model.uiSelectedContainer == nil {
                model.uiSelectedContainer = newContainer;
            }
            if model.uiDefaultDataFolder == nil {
                model.uiDefaultDataFolder = folderName
                appInfo.dataUUID = folderName
            }


        }
        appInfo.containers = model.uiContainers;

    }
}
