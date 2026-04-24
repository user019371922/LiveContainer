//
//  LCContainerView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/6.
//

import SwiftUI

protocol LCContainerViewDelegate {
    func unbindContainer(container: LCContainer)
    func setDefaultContainer(container: LCContainer)
    func saveContainer(container: LCContainer)
    
    func getSettingsBundle() -> Bundle?
    func getContainerURL(container: LCContainer) -> URL
    func getBundleId() -> String
    func isTweakLoaderInjectionDisabled() -> Bool
}

struct LCContainerView : View {
    @ObservedObject var container : LCContainer
    let delegate : LCContainerViewDelegate
    @Binding var uiDefaultDataFolder : String?
    @State var settingsBundle : Bundle? = nil
    
    @StateObject private var removeContainerAlert = YesNoHelper()
    @StateObject private var deleteDataAlert = YesNoHelper()
    @StateObject private var removeKeychainAlert = YesNoHelper()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharedModel : SharedModel
    @State private var typingContainerName : String = ""
    @State private var typingIDFV: String = ""
    @State private var typingSpoofDeviceName: String = ""
    @State private var typingSpoofDeviceModel: String = ""
    @State private var typingSpoofSystemName: String = ""
    @State private var typingSpoofSystemVersion: String = ""
    @State private var typingSpoofLocaleIdentifier: String = ""
    @State private var typingSpoofTimeZoneIdentifier: String = ""
    @State private var typingSpoofBatteryLevel: String = ""
    @State private var spoofBatteryStateSelection: Int = 2
    @State private var spoofLowPowerModeEnabled: Bool = false
    @State private var typingSpoofSubscriberIdentifier: String = ""
    @State private var typingSpoofSubscriberCarrierTokenBase64: String = ""
    @State private var spoofSubscriberSIMInsertedEnabled: Bool = false
    @State private var spoofSubscriberSIMInserted: Bool = false
    @State private var typingSpoofRadioAccessTechnology: String = "CTRadioAccessTechnologyLTE"
    @State private var inUse = false
    @State private var runningLC : String? = nil
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var successShow = false
    @State private var successInfo = ""

    private var tweakLoaderDependentControlsEnabled: Bool {
        !delegate.isTweakLoaderInjectionDisabled()
    }
    
    init(container: LCContainer, uiDefaultDataFolder : Binding<String?>, delegate: LCContainerViewDelegate) {
        self._container = ObservedObject(initialValue: container)
        self.delegate = delegate
        self._typingContainerName = State(initialValue: container.name)
        self._typingSpoofDeviceName = State(initialValue: container.spoofDeviceName)
        self._typingSpoofDeviceModel = State(initialValue: container.spoofDeviceModel)
        self._typingSpoofSystemName = State(initialValue: container.spoofSystemName)
        self._typingSpoofSystemVersion = State(initialValue: container.spoofSystemVersion)
        self._typingSpoofLocaleIdentifier = State(initialValue: container.spoofLocaleIdentifier)
        self._typingSpoofTimeZoneIdentifier = State(initialValue: container.spoofTimeZoneIdentifier)
        self._typingSpoofBatteryLevel = State(initialValue: String(format: "%.2f", container.spoofBatteryLevel))
        self._spoofBatteryStateSelection = State(initialValue: container.spoofBatteryState)
        self._spoofLowPowerModeEnabled = State(initialValue: container.spoofLowPowerModeEnabled)
        self._typingSpoofSubscriberIdentifier = State(initialValue: container.spoofSubscriberIdentifier)
        self._typingSpoofSubscriberCarrierTokenBase64 = State(initialValue: container.spoofSubscriberCarrierTokenBase64)
        self._spoofSubscriberSIMInsertedEnabled = State(initialValue: container.spoofSubscriberSIMInsertedEnabled)
        self._spoofSubscriberSIMInserted = State(initialValue: container.spoofSubscriberSIMInserted)
        self._typingSpoofRadioAccessTechnology = State(initialValue: container.spoofRadioAccessTechnology.isEmpty ? "CTRadioAccessTechnologyLTE" : container.spoofRadioAccessTechnology)
        self._uiDefaultDataFolder = Binding(projectedValue: uiDefaultDataFolder)
    }
    
    var body: some View {
        Form {
            if !(container.storageBookMark != nil && container.resolvedContainerURL == nil) {
                
                Section {
                    HStack {
                        Text("lc.container.containerName".loc)
                        Spacer()
                        TextField("lc.container.containerName".loc, text: $typingContainerName)
                            .multilineTextAlignment(.trailing)
                            .onSubmit {
                                container.name = typingContainerName
                                saveContainer()
                            }
                    }
                    HStack {
                        Text("lc.container.containerFolderName".loc)
                        Spacer()
                        Text(container.folderName)
                            .foregroundStyle(.gray)
                    }
                    Toggle(isOn: $container.isolateAppGroup) {
                        Text("lc.container.isolateAppGroup".loc)
                    }
                    .disabled(container.strictTestMode)
                    .onChange(of: container.isolateAppGroup) { newValue in
                        saveContainer()
                    }
                    
                    if let settingsBundle {
                        NavigationLink {
                            AppPreferenceView(bundleId: delegate.getBundleId(), settingsBundle: settingsBundle, containerURL: delegate.getContainerURL(container: container))
                        } label: {
                            Text("lc.container.preferences".loc)
                        }
                    }
                    if container.folderName == uiDefaultDataFolder {
                        Text("lc.container.alreadyDefaultContainer".loc)
                            .foregroundStyle(.gray)
                    } else {
                        Button {
                            setAsDefault()
                        } label: {
                            Text("lc.container.setDefaultContainer".loc)
                        }
                    }
                } footer: {
                    Text("lc.container.defaultContainerDesc".loc)
                }
                
                Section {
                    Toggle(isOn: $container.spoofIdentifierForVendor) {
                        Text("lc.container.spoofIdentifierForVendor".loc)
                    }
                    .disabled(!tweakLoaderDependentControlsEnabled)
                    .onChange(of: container.spoofIdentifierForVendor) { newValue in
                        saveContainer()
                    }
                    
                    if container.spoofIdentifierForVendor {
                        HStack {
                            Text("UUID")
                            TextField("lc.common.auto".loc, text: $typingIDFV)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveIDFV()
                                }
                        }
                    }
                    if !tweakLoaderDependentControlsEnabled {
                        Text("Disabled because Don't Inject TweakLoader is enabled for this app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Strict Test Mode", isOn: $container.strictTestMode)
                        .disabled(!tweakLoaderDependentControlsEnabled)
                        .onChange(of: container.strictTestMode) { _ in
                            saveStrictModeSettings()
                        }

                    if container.strictTestMode {
                        Toggle("Auto-Wipe Container on App Exit", isOn: $container.strictAutoWipeOnExit)
                            .disabled(!tweakLoaderDependentControlsEnabled)
                            .onChange(of: container.strictAutoWipeOnExit) { _ in
                                saveContainer()
                            }
                    }
                } header: {
                    Text("Strict Test Mode")
                } footer: {
                    if tweakLoaderDependentControlsEnabled {
                        Text("Aggressive isolation for app testing: forces app-group isolation, blocks device identity/profile reads, blocks common external URL/network paths, and can auto-wipe this container on exit.")
                    } else {
                        Text("Strict Test Mode requires TweakLoader injection. Disable Don't Inject TweakLoader in App Settings to use this.")
                    }
                }

                Section {
                    Toggle("Block Device Info Reads", isOn: $container.blockDeviceInfoReads)
                        .disabled(container.strictTestMode || !tweakLoaderDependentControlsEnabled)
                        .onChange(of: container.blockDeviceInfoReads) { _ in
                            saveContainer()
                        }

                    Toggle("Advanced Spoof Profile", isOn: $container.spoofProfileEnabled)
                        .disabled(!tweakLoaderDependentControlsEnabled)
                        .onChange(of: container.spoofProfileEnabled) { _ in
                            if container.spoofProfileEnabled {
                                applyRandomDeviceProfileValues()
                            }
                            saveSpoofProfile()
                        }

                    if container.spoofProfileEnabled {
                        Group {
                        HStack {
                            Text("Device Name")
                            TextField("iPhone", text: $typingSpoofDeviceName)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("Device Model")
                            TextField("iPhone", text: $typingSpoofDeviceModel)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("System Name")
                            TextField("iOS", text: $typingSpoofSystemName)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("System Version")
                            TextField("26.0", text: $typingSpoofSystemVersion)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("Locale ID")
                            TextField("en_US", text: $typingSpoofLocaleIdentifier)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("Time Zone")
                            TextField("Asia/Riyadh", text: $typingSpoofTimeZoneIdentifier)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        Button("Use Current Device Values") {
                            applyCurrentDeviceProfileValues()
                            saveSpoofProfile()
                        }
                        Button("Generate Random Profile") {
                            applyRandomDeviceProfileValues()
                            saveSpoofProfile()
                        }

                        HStack {
                            Text("Battery Level")
                            TextField("0.83", text: $typingSpoofBatteryLevel)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        Picker("Battery State", selection: $spoofBatteryStateSelection) {
                            Text("Unknown").tag(UIDevice.BatteryState.unknown.rawValue)
                            Text("Unplugged").tag(UIDevice.BatteryState.unplugged.rawValue)
                            Text("Charging").tag(UIDevice.BatteryState.charging.rawValue)
                            Text("Full").tag(UIDevice.BatteryState.full.rawValue)
                        }
                        .onChange(of: spoofBatteryStateSelection) { _ in
                            saveSpoofProfile()
                        }
                        Toggle("Low Power Mode", isOn: $spoofLowPowerModeEnabled)
                            .onChange(of: spoofLowPowerModeEnabled) { _ in
                                saveSpoofProfile()
                            }

                        HStack {
                            Text("Subscriber ID")
                            TextField("A1B2C3D4-E5F6-47A8-9C2D-1234567890AB", text: $typingSpoofSubscriberIdentifier)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        HStack {
                            Text("Carrier Token (Base64)")
                            TextField("Optional", text: $typingSpoofSubscriberCarrierTokenBase64)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        Toggle("Spoof SIM Inserted", isOn: $spoofSubscriberSIMInsertedEnabled)
                            .onChange(of: spoofSubscriberSIMInsertedEnabled) { _ in
                                saveSpoofProfile()
                            }
                        if spoofSubscriberSIMInsertedEnabled {
                            Toggle("SIM Inserted", isOn: $spoofSubscriberSIMInserted)
                                .onChange(of: spoofSubscriberSIMInserted) { _ in
                                    saveSpoofProfile()
                                }
                        }
                        Picker("Radio Tech", selection: $typingSpoofRadioAccessTechnology) {
                            ForEach(availableRadioAccessTechnologies(), id: \.self) { tech in
                                Text(tech).tag(tech)
                            }
                        }
                        .onChange(of: typingSpoofRadioAccessTechnology) { _ in
                            saveSpoofProfile()
                        }
                        }
                        .disabled(container.blockDeviceInfoReads)
                    }
                } header: {
                    Text("Spoof Profile")
                } footer: {
                    if tweakLoaderDependentControlsEnabled {
                        Text("Overrides UIDevice, NSProcessInfo, Locale/TimeZone, and modern CoreTelephony subscriber surfaces (CTSubscriber/CTSubscriberInfo + serviceCurrentRadioAccessTechnology). If Block Device Info Reads is enabled, unknown/empty values are returned instead.")
                    } else {
                        Text("Spoof controls require TweakLoader injection. Disable Don't Inject TweakLoader in App Settings to use this.")
                    }
                }

                Section {
                    if inUse {
                        Text("lc.container.inUse".loc)
                            .foregroundStyle(.gray)
                        
                    } else {
                        if !container.isShared || container.storageBookMark != nil {
                            Button {
                                openDataFolder()
                            } label: {
                                Text("lc.appBanner.openDataFolder".loc)
                            }
                            Button {
                                unbindContainer()
                            } label: {
                                Text("lc.container.unbind".loc)
                            }
                        }
                        Button(role:.destructive) {
                            Task { await deleteData() }
                        } label: {
                            Text("lc.container.deleteData".loc)
                        }
                        
                        Button(role:.destructive) {
                            Task { await cleanUpKeychain() }
                        } label: {
                            Text("lc.settings.cleanKeychain".loc)
                        }
                        
                        if(container.storageBookMark == nil) {
                            Button(role:.destructive) {
                                Task { await removeContainer() }
                            } label: {
                                Text("lc.container.removeContainer".loc)
                            }
                        }
                        
                    }
                }
            } else {
                Section {
                    if container.bookmarkResolved {
                        Text("lc.container.externalStorageUnavailable".loc)
                    } else {
                        Text("lc.container.bookmarkResolveInProgress".loc)
                    }

                }
                
                Section {
                    Button(role:.destructive) {
                        Task { await removeContainer() }
                    } label: {
                        Text("lc.container.removeContainer".loc)
                    }
                }
            }
        }
        .navigationTitle(container.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow){
        } message: {
            Text(errorInfo)
        }
        .alert("lc.common.success".loc, isPresented: $successShow){
        } message: {
            Text(successInfo)
        }
        
        .alert("lc.container.removeContainer".loc, isPresented: $removeContainerAlert.show) {
            Button(role: .destructive) {
                removeContainerAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                removeContainerAlert.close(result: false)
            }
        } message: {
            Text("lc.container.removeContainerDesc".loc)
        }
        
        .alert("lc.container.deleteData".loc, isPresented: $deleteDataAlert.show) {
            Button(role: .destructive) {
                deleteDataAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                deleteDataAlert.close(result: false)
            }
        } message: {
            Text("lc.container.deleteDataDesc".loc)
        }
        
        .alert("lc.settings.cleanKeychain".loc, isPresented: $removeKeychainAlert.show) {
            Button(role: .destructive) {
                removeKeychainAlert.close(result: true)
            } label: {
                Text("lc.common.delete".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                removeKeychainAlert.close(result: false)
            }
        } message: {
            Text("lc.container.removeKeychainDesc".loc)
        }
        .onAppear() {
            container.reloadInfoPlist()
            if container.strictTestMode {
                container.isolateAppGroup = true
                container.blockDeviceInfoReads = true
            }
            if let spoofedIDFV = container.spoofedIdentifier {
                typingIDFV = spoofedIDFV
            }
            typingSpoofDeviceName = container.spoofDeviceName
            typingSpoofDeviceModel = container.spoofDeviceModel
            typingSpoofSystemName = container.spoofSystemName
            typingSpoofSystemVersion = container.spoofSystemVersion
            typingSpoofLocaleIdentifier = container.spoofLocaleIdentifier
            typingSpoofTimeZoneIdentifier = container.spoofTimeZoneIdentifier
            typingSpoofBatteryLevel = String(format: "%.2f", container.spoofBatteryLevel)
            spoofBatteryStateSelection = container.spoofBatteryState
            spoofLowPowerModeEnabled = container.spoofLowPowerModeEnabled
            typingSpoofSubscriberIdentifier = container.spoofSubscriberIdentifier
            typingSpoofSubscriberCarrierTokenBase64 = container.spoofSubscriberCarrierTokenBase64
            spoofSubscriberSIMInsertedEnabled = container.spoofSubscriberSIMInsertedEnabled
            spoofSubscriberSIMInserted = container.spoofSubscriberSIMInserted
            typingSpoofRadioAccessTechnology = container.spoofRadioAccessTechnology.isEmpty ? "CTRadioAccessTechnologyLTE" : container.spoofRadioAccessTechnology
            settingsBundle = delegate.getSettingsBundle()
            runningLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName)
            inUse = runningLC != nil
        }
        
    }
    
    func saveIDFV() {
        guard let newIDFV = UUID(uuidString: typingIDFV) else {
            errorInfo = "lc.container.invalidIDFV".loc
            errorShow = true
            return
        }
        container.spoofedIdentifier = newIDFV.uuidString
        delegate.saveContainer(container: container)
    }

    func saveSpoofProfile() {
        let normalizedSystemVersion = typingSpoofSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSystemVersion.isEmpty && !isValidSystemVersion(normalizedSystemVersion) {
            errorInfo = "System Version must use numbers like 26 or 26.1 or 26.1.2."
            errorShow = true
            return
        }

        let rawLocale = typingSpoofLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale: String
        if rawLocale.isEmpty {
            normalizedLocale = ""
        } else if let localeIdentifier = normalizedLocaleIdentifier(rawLocale) {
            normalizedLocale = localeIdentifier
        } else {
            errorInfo = "Locale ID is invalid. Example: en_US or en-US."
            errorShow = true
            return
        }

        let rawTimeZone = typingSpoofTimeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTimeZone: String
        if rawTimeZone.isEmpty {
            normalizedTimeZone = ""
        } else if let zoneIdentifier = normalizedTimeZoneIdentifier(rawTimeZone) {
            normalizedTimeZone = zoneIdentifier
        } else {
            errorInfo = "Time Zone is invalid. Example: Asia/Riyadh."
            errorShow = true
            return
        }

        let normalizedBattery = typingSpoofBatteryLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let batteryLevel = Double(normalizedBattery), batteryLevel >= 0.0, batteryLevel <= 1.0 else {
            errorInfo = "Battery Level must be between 0.0 and 1.0."
            errorShow = true
            return
        }

        let subscriberID = typingSpoofSubscriberIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let subscriberTokenBase64 = typingSpoofSubscriberCarrierTokenBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subscriberTokenBase64.isEmpty && Data(base64Encoded: subscriberTokenBase64) == nil {
            errorInfo = "Carrier Token must be valid Base64."
            errorShow = true
            return
        }

        let radioTech = typingSpoofRadioAccessTechnology.trimmingCharacters(in: .whitespacesAndNewlines)
        if !availableRadioAccessTechnologies().contains(radioTech) {
            errorInfo = "Radio Tech value is invalid."
            errorShow = true
            return
        }

        container.spoofDeviceName = typingSpoofDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofDeviceModel = typingSpoofDeviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofSystemName = typingSpoofSystemName.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofSystemVersion = normalizedSystemVersion
        container.spoofLocaleIdentifier = normalizedLocale
        container.spoofTimeZoneIdentifier = normalizedTimeZone
        container.spoofBatteryLevel = batteryLevel
        container.spoofBatteryState = spoofBatteryStateSelection
        container.spoofLowPowerModeEnabled = spoofLowPowerModeEnabled
        container.spoofSubscriberIdentifier = subscriberID
        container.spoofSubscriberCarrierTokenBase64 = subscriberTokenBase64
        container.spoofSubscriberSIMInsertedEnabled = spoofSubscriberSIMInsertedEnabled
        container.spoofSubscriberSIMInserted = spoofSubscriberSIMInserted
        container.spoofRadioAccessTechnology = radioTech
        saveContainer()
    }

    func applyCurrentDeviceProfileValues() {
        typingSpoofDeviceName = UIDevice.current.name
        typingSpoofDeviceModel = UIDevice.current.model
        typingSpoofSystemName = UIDevice.current.systemName
        typingSpoofSystemVersion = UIDevice.current.systemVersion
        typingSpoofLocaleIdentifier = Locale.current.identifier
        typingSpoofTimeZoneIdentifier = TimeZone.current.identifier
        typingSpoofBatteryLevel = "0.85"
        spoofBatteryStateSelection = UIDevice.BatteryState.charging.rawValue
        spoofLowPowerModeEnabled = false
        typingSpoofSubscriberIdentifier = ""
        typingSpoofSubscriberCarrierTokenBase64 = ""
        spoofSubscriberSIMInsertedEnabled = false
        spoofSubscriberSIMInserted = false
        typingSpoofRadioAccessTechnology = "CTRadioAccessTechnologyLTE"
    }

    func applyRandomDeviceProfileValues() {
        let localeTimeZonePairs: [(String, String)] = [
            ("en_US", "America/New_York"),
            ("en_GB", "Europe/London"),
            ("ar_SA", "Asia/Riyadh"),
            ("fr_FR", "Europe/Paris"),
            ("de_DE", "Europe/Berlin"),
            ("ja_JP", "Asia/Tokyo"),
            ("es_ES", "Europe/Madrid"),
            ("tr_TR", "Europe/Istanbul"),
            ("ko_KR", "Asia/Seoul"),
            ("hi_IN", "Asia/Kolkata")
        ]
        let selectedLocaleZone = localeTimeZonePairs.randomElement() ?? ("en_US", "America/New_York")

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let possibleNames = isPad
            ? ["iPad", "My iPad", "iPad Pro", "iPad Air"]
            : ["iPhone", "My iPhone", "iPhone Pro", "iPhone Plus"]
        let selectedName = possibleNames.randomElement() ?? (isPad ? "iPad" : "iPhone")

        let currentSystemName = UIDevice.current.systemName
        let majorVersion = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "26") ?? 26
        let minorVersion = Int.random(in: 0...3)
        let patchVersion = Int.random(in: 0...2)
        let batteryLevel = Double.random(in: 0.18...1.0)
        let batteryStateOptions = [
            UIDevice.BatteryState.unplugged.rawValue,
            UIDevice.BatteryState.charging.rawValue,
            UIDevice.BatteryState.full.rawValue
        ]
        let radioTechnology = availableRadioAccessTechnologies().randomElement() ?? "CTRadioAccessTechnologyLTE"
        let tokenBytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        let randomToken = Data(tokenBytes).base64EncodedString()

        typingSpoofDeviceName = selectedName
        typingSpoofDeviceModel = isPad ? "iPad" : "iPhone"
        typingSpoofSystemName = currentSystemName
        if patchVersion == 0 {
            typingSpoofSystemVersion = "\(majorVersion).\(minorVersion)"
        } else {
            typingSpoofSystemVersion = "\(majorVersion).\(minorVersion).\(patchVersion)"
        }
        typingSpoofLocaleIdentifier = selectedLocaleZone.0
        typingSpoofTimeZoneIdentifier = selectedLocaleZone.1
        typingSpoofBatteryLevel = String(format: "%.2f", batteryLevel)
        spoofBatteryStateSelection = batteryStateOptions.randomElement() ?? UIDevice.BatteryState.unplugged.rawValue
        spoofLowPowerModeEnabled = batteryLevel < 0.25
        typingSpoofSubscriberIdentifier = UUID().uuidString.uppercased()
        typingSpoofSubscriberCarrierTokenBase64 = randomToken
        spoofSubscriberSIMInsertedEnabled = true
        spoofSubscriberSIMInserted = Bool.random()
        typingSpoofRadioAccessTechnology = radioTechnology
    }

    func normalizedLocaleIdentifier(_ raw: String) -> String? {
        let bcp47Normalized = raw.replacingOccurrences(of: "-", with: "_")
        let canonical = Locale.canonicalIdentifier(from: bcp47Normalized)
        let components = NSLocale.components(fromLocaleIdentifier: canonical)
        let languageCode = components[NSLocale.Key.languageCode.rawValue]
        if let languageCode, !languageCode.isEmpty {
            return canonical
        }
        return nil
    }

    func normalizedTimeZoneIdentifier(_ raw: String) -> String? {
        if let zone = TimeZone(identifier: raw) {
            return zone.identifier
        }
        if let zone = TimeZone(abbreviation: raw.uppercased()) {
            return zone.identifier
        }
        return nil
    }

    func availableRadioAccessTechnologies() -> [String] {
        [
            "CTRadioAccessTechnologyNR",
            "CTRadioAccessTechnologyNRNSA",
            "CTRadioAccessTechnologyLTE",
            "CTRadioAccessTechnologyWCDMA",
            "CTRadioAccessTechnologyHSDPA",
            "CTRadioAccessTechnologyHSUPA",
            "CTRadioAccessTechnologyCDMAEVDORevA"
        ]
    }

    func isValidSystemVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty && parts.count <= 3 else {
            return false
        }
        for part in parts {
            if part.isEmpty || part.contains(where: { !$0.isNumber }) {
                return false
            }
        }
        return true
    }

    func saveContainer() {
        if let usingLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
            errorInfo = "lc.container.inUseBy %@".localizeWithFormat(usingLC)
            errorShow = true
            return
        }
        
        delegate.saveContainer(container: container)
    }

    func saveStrictModeSettings() {
        if container.strictTestMode {
            container.isolateAppGroup = true
            container.blockDeviceInfoReads = true
        }
        saveContainer()
    }
    
    func openDataFolder() {
        let url = URL(string:"shareddocuments://\(LCPath.dataPath.path)/\(container.folderName)")
        UIApplication.shared.open(url!)
    }
    
    func setAsDefault() {
        delegate.setDefaultContainer(container: container)
    }
    
    func removeContainer() async {
        if let usingLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
            errorInfo = "lc.container.inUseBy %@".localizeWithFormat(usingLC)
            errorShow = true
            return
        }
        guard let ans = await removeContainerAlert.open(), ans else {
            return
        }
        do {
            let fm = FileManager.default
            try fm.removeItem(at: container.containerURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
        
        dismiss()
        delegate.unbindContainer(container: container)
    }
    
    func unbindContainer() {
        if let usingLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
            errorInfo = "lc.container.inUseBy %@".localizeWithFormat(usingLC)
            errorShow = true
            return
        }
        
        dismiss()
        delegate.unbindContainer(container: container)
    }
    
    func cleanUpKeychain() async {
        if let usingLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
            errorInfo = "lc.container.inUseBy %@".localizeWithFormat(usingLC)
            errorShow = true
            return
        }
        guard let ans = await removeKeychainAlert.open(), ans else {
            return
        }
        
        LCUtils.removeAppKeychain(dataUUID: container.folderName)
    }
    
    func deleteData() async {
        if let usingLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {
            errorInfo = "lc.container.inUseBy %@".localizeWithFormat(usingLC)
            errorShow = true
            return
        }
        guard let ans = await deleteDataAlert.open(), ans else {
            return
        }
        do {
            let fm = FileManager.default
            for file in try fm.contentsOfDirectory(at: container.containerURL, includingPropertiesForKeys: nil) {
                if file.lastPathComponent == "LCContainerInfo.plist" {
                    continue
                }
                try fm.removeItem(at: file)
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
}
