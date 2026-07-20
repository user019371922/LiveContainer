//
//  LCContainerView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/6.
//

import SwiftUI
import Metal
import AVFoundation

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
    private static let allLocaleIdentifiers = Array(Set(Locale.availableIdentifiers.map {
        Locale.canonicalIdentifier(from: $0)
    })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    private static let allTimeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

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
    @State private var typingSpoofHardwareModel: String = ""
    @State private var inUse = false
    @State private var runningLC : String? = nil
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var successShow = false
    @State private var successInfo = ""

    private var tweakLoaderDependentControlsEnabled: Bool {
        !delegate.isTweakLoaderInjectionDisabled()
    }

    private func categoryToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _ in saveSpoofProfile() }
    }

    private func featureBinding(_ key: String, default defaultValue: Bool = true) -> Binding<Bool> {
        Binding(
            get: { container.spoofFeatureOverrides[key] ?? defaultValue },
            set: { value in
                var overrides = container.spoofFeatureOverrides
                overrides[key] = value
                container.spoofFeatureOverrides = overrides
                saveSpoofProfile()
            }
        )
    }

    private func featureToggle(_ title: String, _ key: String, default defaultValue: Bool = true) -> some View {
        Toggle(title, isOn: featureBinding(key, default: defaultValue))
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
        self._typingSpoofHardwareModel = State(initialValue: container.spoofHardwareModel)
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
                            if container.spoofProfileEnabled && !hasConfiguredSpoofTemplate() {
                                applyRandomDeviceProfileValues()
                            }
                            saveSpoofProfile()
                        }

                    if container.spoofProfileEnabled {
                        Group {
                        Toggle("Rotate Profile Every Launch", isOn: $container.rotateSpoofProfileOnLaunch)
                            .onChange(of: container.rotateSpoofProfileOnLaunch) { _ in saveSpoofProfile() }
                        if container.rotateSpoofProfileOnLaunch {
                            HStack {
                                Text("OS Major Versions")
                                TextField("18,26,27", text: $container.rotateOSMajorVersions)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numbersAndPunctuation)
                                    .onSubmit { saveSpoofProfile() }
                            }
                            Toggle("Use Real Device Templates", isOn: $container.rotateUsesRealDeviceTemplates)
                                .onChange(of: container.rotateUsesRealDeviceTemplates) { _ in saveSpoofProfile() }
                            Text("Enter exact major versions separated by commas. Real Device Templates rotate among known iPhone/iPad hardware identifiers; turn this off to preserve custom, Android-style, or empty device values.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Category Kill Switches") {
                            categoryToggle("Identity", isOn: $container.spoofIdentityCategoryEnabled)
                            categoryToggle("System", isOn: $container.spoofSystemCategoryEnabled)
                            categoryToggle("Display", isOn: $container.spoofDisplayCategoryEnabled)
                            categoryToggle("Locale & Time Zone", isOn: $container.spoofLocaleCategoryEnabled)
                            categoryToggle("Battery & Power", isOn: $container.spoofBatteryCategoryEnabled)
                            categoryToggle("Telephony", isOn: $container.spoofTelephonyCategoryEnabled)
                            categoryToggle("Network Headers", isOn: $container.spoofNetworkHeadersCategoryEnabled)
                            categoryToggle("Accessibility", isOn: $container.spoofAccessibilityCategoryEnabled)
                            categoryToggle("Storage", isOn: $container.spoofStorageCategoryEnabled)
                            categoryToggle("Network Environment", isOn: $container.spoofNetworkEnvironmentCategoryEnabled)
                            categoryToggle("Audio Routes", isOn: $container.spoofAudioCategoryEnabled)
                            categoryToggle("Graphics & Metal", isOn: $container.spoofGraphicsCategoryEnabled)
                            categoryToggle("WebView Fingerprint", isOn: $container.spoofWebViewCategoryEnabled)
                            categoryToggle("App, Account & Pasteboard", isOn: $container.spoofAppPrivacyCategoryEnabled)
                            categoryToggle("Sensors & Personal Data", isOn: $container.spoofSensorsAndUserDataCategoryEnabled)
                        }
                        Text("Disable an individual category if an app depends on the real API. Sensors & Personal Data intentionally reports permissions or hardware as unavailable instead of fabricating contacts, photos, locations, or sensor samples.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DisclosureGroup("Identity") {
                        Toggle(isOn: $container.spoofIdentifierForVendor) {
                            Text("lc.container.spoofIdentifierForVendor".loc)
                        }
                        .onChange(of: container.spoofIdentifierForVendor) { _ in
                            saveSpoofProfile()
                        }

                        if container.spoofIdentifierForVendor {
                            HStack {
                                Text("Vendor ID (UUID)")
                                TextField("lc.common.auto".loc, text: $typingIDFV)
                                    .multilineTextAlignment(.trailing)
                                    .onSubmit {
                                        saveSpoofProfile()
                                    }
                            }
                        }

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
                            Text("Hardware Model")
                            Spacer()
                            Picker("", selection: $typingSpoofHardwareModel) {
                                Text("None").tag("")
                                Section("iPhone 17") {
                                    Text("iPhone 17 Pro").tag("iPhone18,1")
                                    Text("iPhone 17 Pro Max").tag("iPhone18,2")
                                    Text("iPhone 17").tag("iPhone18,3")
                                    Text("iPhone 17 Air").tag("iPhone18,4")
                                }
                                Section("iPhone 16") {
                                    Text("iPhone 16 Pro").tag("iPhone17,1")
                                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                                    Text("iPhone 16").tag("iPhone17,3")
                                    Text("iPhone 16 Plus").tag("iPhone17,4")
                                    Text("iPhone 16e").tag("iPhone17,5")
                                }
                                Section("iPhone 15") {
                                    Text("iPhone 15 Pro").tag("iPhone16,1")
                                    Text("iPhone 15 Pro Max").tag("iPhone16,2")
                                    Text("iPhone 15").tag("iPhone15,4")
                                    Text("iPhone 15 Plus").tag("iPhone15,5")
                                }
                                Section("iPhone 14") {
                                    Text("iPhone 14 Pro").tag("iPhone15,2")
                                    Text("iPhone 14 Pro Max").tag("iPhone15,3")
                                    Text("iPhone 14").tag("iPhone14,7")
                                    Text("iPhone 14 Plus").tag("iPhone14,8")
                                }
                                Section("iPad Pro") {
                                    Text("iPad Pro M4 11\"").tag("iPad16,3")
                                    Text("iPad Pro M4 13\"").tag("iPad16,5")
                                }
                                Section("iPad Air") {
                                    Text("iPad Air M2 11\"").tag("iPad14,8")
                                    Text("iPad Air M2 13\"").tag("iPad14,10")
                                }
                            }
                            .labelsHidden()
                            .onChange(of: typingSpoofHardwareModel) { _ in
                                saveSpoofProfile()
                            }
                        }
                        .disabled(!container.spoofIdentityCategoryEnabled)
                        HStack {
                            Text("Custom Hardware Model")
                            TextField("Empty, iPhone17,1, Android…", text: $typingSpoofHardwareModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .onSubmit { saveSpoofProfile() }
                        }
                        }
                        .disabled(!container.spoofIdentityCategoryEnabled)

                        DisclosureGroup("System & Display") {
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
                        featureToggle("Report Low Data Mode Disabled", "system.lowDataMode")
                        DisclosureGroup("Advanced Hardware & Display") {
                            TextField("Host Name", text: $container.spoofHostName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { saveSpoofProfile() }
                            TextField("Board Model", text: $container.spoofBoardModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { saveSpoofProfile() }
                            TextField("Kernel Version", text: $container.spoofKernelVersion)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { saveSpoofProfile() }
                            TextField("Boot Time (Unix)", value: $container.spoofBootTime, format: .number)
                                .keyboardType(.numberPad)
                            TextField("CPU Type", value: $container.spoofCPUType, format: .number)
                                .keyboardType(.numberPad)
                            TextField("CPU Subtype", value: $container.spoofCPUSubtype, format: .number)
                                .keyboardType(.numberPad)
                            Stepper("Processor Cores: \(container.spoofProcessorCount)", value: $container.spoofProcessorCount, in: 1...16)
                                .onChange(of: container.spoofProcessorCount) { _ in saveSpoofProfile() }
                            Picker("Physical Memory", selection: $container.spoofPhysicalMemory) {
                                Text("2 GB").tag(Int64(2 * 1_073_741_824))
                                Text("3 GB").tag(Int64(3 * 1_073_741_824))
                                Text("4 GB").tag(Int64(4 * 1_073_741_824))
                                Text("6 GB").tag(Int64(6 * 1_073_741_824))
                                Text("8 GB").tag(Int64(8 * 1_073_741_824))
                                Text("12 GB").tag(Int64(12 * 1_073_741_824))
                                Text("16 GB").tag(Int64(16 * 1_073_741_824))
                            }
                            .onChange(of: container.spoofPhysicalMemory) { _ in saveSpoofProfile() }
                            Picker("Thermal State", selection: $container.spoofThermalState) {
                                Text("Nominal").tag(0)
                                Text("Fair").tag(1)
                                Text("Serious").tag(2)
                                Text("Critical").tag(3)
                            }
                            .onChange(of: container.spoofThermalState) { _ in saveSpoofProfile() }
                            HStack {
                                Text("Native Resolution")
                                TextField("Width", value: $container.spoofScreenWidth, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                Text("×")
                                TextField("Height", value: $container.spoofScreenHeight, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text("Screen Scale")
                                TextField("3", value: $container.spoofScreenScale, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text("Native Scale")
                                TextField("3", value: $container.spoofScreenNativeScale, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            Picker("Maximum FPS", selection: $container.spoofMaximumFramesPerSecond) {
                                Text("60 Hz").tag(60)
                                Text("120 Hz").tag(120)
                            }
                            .onChange(of: container.spoofMaximumFramesPerSecond) { _ in saveSpoofProfile() }
                            HStack {
                                Text("Brightness")
                                TextField("0.50", value: $container.spoofScreenBrightness, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            Picker("Appearance", selection: $container.spoofUserInterfaceStyle) {
                                Text("Use System").tag(0)
                                Text("Light Mode").tag(1)
                                Text("Dark Mode").tag(2)
                            }
                            .onChange(of: container.spoofUserInterfaceStyle) { _ in saveSpoofProfile() }
                            Picker("Display Gamut", selection: $container.spoofDisplayGamut) {
                                Text("Unspecified").tag(0)
                                Text("sRGB").tag(1)
                                Text("Display P3").tag(2)
                            }
                            .onChange(of: container.spoofDisplayGamut) { _ in saveSpoofProfile() }
                            Picker("Horizontal Size Class", selection: $container.spoofHorizontalSizeClass) {
                                Text("Unspecified").tag(0)
                                Text("Compact").tag(1)
                                Text("Regular").tag(2)
                            }
                            .onChange(of: container.spoofHorizontalSizeClass) { _ in saveSpoofProfile() }
                            Picker("Vertical Size Class", selection: $container.spoofVerticalSizeClass) {
                                Text("Unspecified").tag(0)
                                Text("Compact").tag(1)
                                Text("Regular").tag(2)
                            }
                            .onChange(of: container.spoofVerticalSizeClass) { _ in saveSpoofProfile() }
                            Picker("Text Size", selection: $container.spoofPreferredContentSizeCategory) {
                                Text("Extra Small").tag("UICTContentSizeCategoryXS")
                                Text("Small").tag("UICTContentSizeCategoryS")
                                Text("Medium").tag("UICTContentSizeCategoryM")
                                Text("Large").tag("UICTContentSizeCategoryL")
                                Text("Extra Large").tag("UICTContentSizeCategoryXL")
                                Text("XX Large").tag("UICTContentSizeCategoryXXL")
                                Text("XXX Large").tag("UICTContentSizeCategoryXXXL")
                                Text("Accessibility Medium").tag("UICTContentSizeCategoryAccessibilityM")
                                Text("Accessibility Large").tag("UICTContentSizeCategoryAccessibilityL")
                                Text("Accessibility XL").tag("UICTContentSizeCategoryAccessibilityXL")
                                Text("Accessibility XXL").tag("UICTContentSizeCategoryAccessibilityXXL")
                                Text("Accessibility XXXL").tag("UICTContentSizeCategoryAccessibilityXXXL")
                            }
                            .onChange(of: container.spoofPreferredContentSizeCategory) { _ in saveSpoofProfile() }
                            HStack {
                                Text("Safe Area T/B")
                                TextField("Top", value: $container.spoofSafeAreaTop, format: .number)
                                    .keyboardType(.decimalPad)
                                TextField("Bottom", value: $container.spoofSafeAreaBottom, format: .number)
                                    .keyboardType(.decimalPad)
                            }
                            HStack {
                                Text("Safe Area L/R")
                                TextField("Left", value: $container.spoofSafeAreaLeft, format: .number)
                                    .keyboardType(.decimalPad)
                                TextField("Right", value: $container.spoofSafeAreaRight, format: .number)
                                    .keyboardType(.decimalPad)
                            }
                            Button("Save System & Display") { saveSpoofProfile() }
                        }
                        }
                        .disabled(!container.spoofSystemCategoryEnabled && !container.spoofDisplayCategoryEnabled)

                        DisclosureGroup("Locale & Time Zone") {
                        HStack {
                            Text("Locale ID")
                            TextField("en_US", text: $typingSpoofLocaleIdentifier)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    saveSpoofProfile()
                                }
                        }
                        Picker("All Locales", selection: $typingSpoofLocaleIdentifier) {
                            Text("None").tag("")
                            ForEach(Self.allLocaleIdentifiers, id: \.self) { identifier in
                                Text(localeDisplayName(identifier)).tag(identifier)
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
                        Picker("All Time Zones", selection: $typingSpoofTimeZoneIdentifier) {
                            Text("None").tag("")
                            ForEach(Self.allTimeZoneIdentifiers, id: \.self) { identifier in
                                Text(identifier).tag(identifier)
                            }
                        }
                        featureToggle("Hide Active Keyboard/Input Modes", "locale.inputModes")
                        Button("Use Current Device Values") {
                            applyCurrentDeviceProfileValues()
                            saveSpoofProfile()
                        }
                        Button("Generate Random Profile") {
                            applyRandomDeviceProfileValues()
                            saveSpoofProfile()
                        }
                        }
                        .disabled(!container.spoofLocaleCategoryEnabled)

                        DisclosureGroup("Battery & Power") {
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
                        }
                        .disabled(!container.spoofBatteryCategoryEnabled)

                        DisclosureGroup("Telephony") {
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
                        .disabled(!container.spoofTelephonyCategoryEnabled)

                        DisclosureGroup("Network Headers") {
                            featureToggle("Rewrite User-Agent Headers", "networkHeaders.userAgent")
                            TextField("Custom User-Agent (empty = generated)", text: $container.spoofCustomUserAgent)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Save Network Headers") { saveSpoofProfile() }
                        }
                        .disabled(!container.spoofNetworkHeadersCategoryEnabled)

                        DisclosureGroup("Accessibility & Appearance") {
                            Picker("Appearance", selection: $container.spoofUserInterfaceStyle) {
                                Text("Use System").tag(0)
                                Text("Light Mode").tag(1)
                                Text("Dark Mode").tag(2)
                            }
                            .onChange(of: container.spoofUserInterfaceStyle) { _ in saveSpoofProfile() }
                            Picker("Contrast", selection: $container.spoofAccessibilityContrast) {
                                Text("Normal").tag(0)
                                Text("High").tag(1)
                            }
                            .onChange(of: container.spoofAccessibilityContrast) { _ in saveSpoofProfile() }
                            DisclosureGroup("Accessibility Features Reported Off") {
                                featureToggle("VoiceOver", "accessibility.voiceOver")
                                featureToggle("Switch Control", "accessibility.switchControl")
                                featureToggle("Guided Access", "accessibility.guidedAccess")
                                featureToggle("Grayscale", "accessibility.grayscale")
                                featureToggle("Invert Colors", "accessibility.invertColors")
                                featureToggle("Reduce Motion", "accessibility.reduceMotion")
                                featureToggle("Reduce Transparency", "accessibility.reduceTransparency")
                                featureToggle("AssistiveTouch", "accessibility.assistiveTouch")
                                featureToggle("Shake to Undo", "accessibility.shakeToUndo")
                                featureToggle("Bold Text", "accessibility.boldText")
                                featureToggle("Darker System Colors", "accessibility.darkerColors")
                                featureToggle("Mono Audio", "accessibility.monoAudio")
                                featureToggle("Speak Screen", "accessibility.speakScreen")
                                featureToggle("Speak Selection", "accessibility.speakSelection")
                                featureToggle("Closed Captions", "accessibility.closedCaptions")
                                featureToggle("Video Autoplay", "accessibility.videoAutoplay")
                                featureToggle("Differentiate Without Color", "accessibility.differentiateWithoutColor")
                                featureToggle("On/Off Switch Labels", "accessibility.onOffLabels")
                            }
                        }
                        .disabled(!container.spoofAccessibilityCategoryEnabled)

                        DisclosureGroup("Storage") {
                            featureToggle("Override Capacity", "storage.capacity")
                            TextField("Total Capacity (Bytes)", value: $container.spoofStorageTotalCapacity, format: .number)
                                .keyboardType(.numberPad)
                            TextField("Available Capacity (Bytes)", value: $container.spoofStorageAvailableCapacity, format: .number)
                                .keyboardType(.numberPad)
                            featureToggle("Override Volume Identity", "storage.identity")
                            TextField("Volume Name", text: $container.spoofStorageVolumeName)
                            TextField("Volume UUID", text: $container.spoofStorageVolumeUUID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            featureToggle("Override Creation Dates", "storage.creationDates")
                            TextField("File Creation (Unix)", value: $container.spoofStorageFileCreationTime, format: .number)
                                .keyboardType(.numberPad)
                            TextField("Volume Creation (Unix)", value: $container.spoofStorageVolumeCreationTime, format: .number)
                                .keyboardType(.numberPad)
                            Button("Save Storage") { saveSpoofProfile() }
                        }
                        .disabled(!container.spoofStorageCategoryEnabled)

                        DisclosureGroup("Network Environment") {
                            featureToggle("Override Host Name", "network.hostName")
                            featureToggle("Hide Network Interfaces", "network.interfaces")
                            featureToggle("Stop Path Monitoring", "network.pathMonitor")
                            featureToggle("Block Bonjour / Service Discovery", "network.serviceDiscovery")
                            featureToggle("Hide Proxy and VPN Settings", "network.proxy")
                        }
                        .disabled(!container.spoofNetworkEnvironmentCategoryEnabled)

                        DisclosureGroup("Audio Routes") {
                            featureToggle("Hide Available Inputs", "audio.availableInputs")
                            featureToggle("Hide Current Route Inputs/Outputs", "audio.routes")
                            featureToggle("Override Output Volume", "audio.outputVolume")
                            HStack {
                                Text("Output Volume")
                                TextField("0.50", value: $container.spoofAudioOutputVolume, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            featureToggle("Override Sample Rate", "audio.sampleRate")
                            TextField("Sample Rate", value: $container.spoofAudioSampleRate, format: .number)
                                .keyboardType(.decimalPad)
                            featureToggle("Override Output Latency", "audio.outputLatency")
                            TextField("Output Latency", value: $container.spoofAudioOutputLatency, format: .number)
                                .keyboardType(.decimalPad)
                            featureToggle("Override Input Latency", "audio.inputLatency")
                            TextField("Input Latency", value: $container.spoofAudioInputLatency, format: .number)
                                .keyboardType(.decimalPad)
                            featureToggle("Override Other Audio Playing", "audio.otherPlaying")
                            Toggle("Other Audio Playing", isOn: $container.spoofAudioOtherPlaying)
                                .onChange(of: container.spoofAudioOtherPlaying) { _ in saveSpoofProfile() }
                            featureToggle("Override Channel Counts", "audio.channels")
                            Stepper("Output Channels: \(container.spoofAudioOutputChannels)", value: $container.spoofAudioOutputChannels, in: 0...32)
                            Stepper("Input Channels: \(container.spoofAudioInputChannels)", value: $container.spoofAudioInputChannels, in: 0...32)
                            Button("Save Audio") { saveSpoofProfile() }
                        }
                        .disabled(!container.spoofAudioCategoryEnabled)

                        DisclosureGroup("Graphics & Metal") {
                            featureToggle("Override GPU Name", "graphics.name")
                            TextField("GPU Name", text: $container.spoofGPUName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            featureToggle("Override Recommended Working Set", "graphics.workingSet")
                            TextField("Working Set (Bytes)", value: $container.spoofGPUWorkingSetSize, format: .number)
                                .keyboardType(.numberPad)
                            featureToggle("Report Ray Tracing Support", "graphics.rayTracing")
                            Toggle("Ray Tracing Result", isOn: $container.spoofGraphicsSupportsRayTracing)
                                .onChange(of: container.spoofGraphicsSupportsRayTracing) { _ in saveSpoofProfile() }
                            featureToggle("Report All Metal Families", "graphics.allFamilies")
                            Toggle("Metal Families Result", isOn: $container.spoofGraphicsSupportsAllFamilies)
                                .onChange(of: container.spoofGraphicsSupportsAllFamilies) { _ in saveSpoofProfile() }
                            Button("Save Graphics") { saveSpoofProfile() }
                        }
                        .disabled(!container.spoofGraphicsCategoryEnabled)

                        DisclosureGroup("WebView Fingerprint") {
                            featureToggle("Override Navigator and User-Agent", "web.navigator")
                            featureToggle("Override Screen and Device Pixel Ratio", "web.screen")
                            featureToggle("Override Time Zone", "web.timeZone")
                            featureToggle("Override WebGL", "web.webGL")
                            TextField("WebGL Vendor", text: $container.spoofWebGLVendor)
                            TextField("WebGL Renderer", text: $container.spoofWebGLRenderer)
                            featureToggle("Override Canvas Output", "web.canvas")
                            TextField("Canvas Data URL", text: $container.spoofWebCanvasDataURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Stepper("Color Depth: \(container.spoofWebColorDepth)", value: $container.spoofWebColorDepth, in: 1...64)
                            Button("Save WebView") { saveSpoofProfile() }
                        }
                        .disabled(!container.spoofWebViewCategoryEnabled)

                        DisclosureGroup("App, Account & Pasteboard") {
                            featureToggle("Hide URL-Scheme App Detection", "app.canOpenURL")
                            featureToggle("Hide Installed Font Families", "app.fonts")
                            featureToggle("Hide Installed Speech Voices", "app.voices")
                            featureToggle("Hide iCloud Account Identity", "app.iCloud")
                            featureToggle("Use Isolated General Pasteboard", "app.pasteboard")
                        }
                        .disabled(!container.spoofAppPrivacyCategoryEnabled)

                        DisclosureGroup("Sensors & Personal Data") {
                            DisclosureGroup("Sensors Reported Unavailable") {
                                featureToggle("Accelerometer", "sensors.accelerometer")
                                featureToggle("Gyroscope", "sensors.gyroscope")
                                featureToggle("Magnetometer", "sensors.magnetometer")
                                featureToggle("Device Motion", "sensors.deviceMotion")
                                featureToggle("Pedometer Capabilities", "sensors.pedometer")
                                featureToggle("Altimeter Capabilities", "sensors.altimeter")
                            }
                            DisclosureGroup("Permissions Reported Denied") {
                                featureToggle("Location", "permissions.location")
                                featureToggle("Camera and Microphone", "permissions.capture")
                                featureToggle("Photos", "permissions.photos")
                                featureToggle("Contacts", "permissions.contacts")
                                featureToggle("Calendars and Reminders", "permissions.events")
                                featureToggle("Media Library", "permissions.media")
                                featureToggle("Bluetooth", "permissions.bluetooth")
                            }
                        }
                        .disabled(!container.spoofSensorsAndUserDataCategoryEnabled)
                        }
                        .disabled(container.blockDeviceInfoReads)
                    }
                } header: {
                    Text("Spoof Profile")
                } footer: {
                    if tweakLoaderDependentControlsEnabled {
                        Text("Each category has an independent kill switch. Rotate Profile Every Launch generates an in-memory profile for that guest process without overwriting the saved template. Locale and time-zone pickers include every identifier provided by the installed OS.")
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
            typingSpoofHardwareModel = container.spoofHardwareModel
            settingsBundle = delegate.getSettingsBundle()
            runningLC = LCSharedUtils.getContainerUsingLCScheme(withFolderName: container.folderName)
            inUse = runningLC != nil
        }
        
    }
    
    func saveSpoofProfile() {
        if container.rotateSpoofProfileOnLaunch && parsedRotationOSMajors() == nil {
            errorInfo = "OS Major Versions must be a comma-separated list of numbers, for example 18,26,27."
            errorShow = true
            return
        }
        let rawIDFV = typingIDFV.trimmingCharacters(in: .whitespacesAndNewlines)
        if container.spoofIdentityCategoryEnabled && container.spoofIdentifierForVendor {
            if rawIDFV.isEmpty {
                let generatedIDFV = UUID().uuidString
                typingIDFV = generatedIDFV
                container.spoofedIdentifier = generatedIDFV
            } else if let normalizedIDFV = UUID(uuidString: rawIDFV) {
                let normalizedValue = normalizedIDFV.uuidString
                typingIDFV = normalizedValue
                container.spoofedIdentifier = normalizedValue
            } else {
                errorInfo = "lc.container.invalidIDFV".loc
                errorShow = true
                return
            }
        } else if container.spoofIdentityCategoryEnabled {
            container.spoofedIdentifier = nil
        }

        let normalizedSystemVersion = typingSpoofSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if container.spoofSystemCategoryEnabled && !normalizedSystemVersion.isEmpty && !isValidSystemVersion(normalizedSystemVersion) {
            errorInfo = "System Version must use numbers like 26 or 26.1 or 26.1.2."
            errorShow = true
            return
        }

        let rawLocale = typingSpoofLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale: String
        if rawLocale.isEmpty {
            normalizedLocale = ""
        } else if !container.spoofLocaleCategoryEnabled {
            normalizedLocale = rawLocale
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
        } else if !container.spoofLocaleCategoryEnabled {
            normalizedTimeZone = rawTimeZone
        } else if let zoneIdentifier = normalizedTimeZoneIdentifier(rawTimeZone) {
            normalizedTimeZone = zoneIdentifier
        } else {
            errorInfo = "Time Zone is invalid. Example: Asia/Riyadh."
            errorShow = true
            return
        }

        let normalizedBattery = typingSpoofBatteryLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        if container.spoofBatteryCategoryEnabled && Double(normalizedBattery) == nil {
            errorInfo = "Battery Level must be a number."
            errorShow = true
            return
        }
        let batteryLevel = Double(normalizedBattery) ?? container.spoofBatteryLevel
        if container.spoofBatteryCategoryEnabled && !(batteryLevel >= 0.0 && batteryLevel <= 1.0) {
            errorInfo = "Battery Level must be between 0.0 and 1.0."
            errorShow = true
            return
        }

        let subscriberID = typingSpoofSubscriberIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let subscriberTokenBase64 = typingSpoofSubscriberCarrierTokenBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        if container.spoofTelephonyCategoryEnabled && !subscriberTokenBase64.isEmpty && Data(base64Encoded: subscriberTokenBase64) == nil {
            errorInfo = "Carrier Token must be valid Base64."
            errorShow = true
            return
        }

        let radioTech = typingSpoofRadioAccessTechnology.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemValuesValid = !container.spoofSystemCategoryEnabled || (
              container.spoofProcessorCount > 0 &&
              container.spoofPhysicalMemory > 0 &&
              !container.spoofKernelVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
              container.spoofBootTime > 0 && container.spoofCPUType > 0 && container.spoofCPUSubtype >= 0)
        let thermalValueValid = !container.spoofBatteryCategoryEnabled || (0...3).contains(container.spoofThermalState)
        let displayValuesValid = !container.spoofDisplayCategoryEnabled || (
              container.spoofScreenWidth > 0 && container.spoofScreenHeight > 0 &&
              container.spoofScreenScale > 0 && container.spoofScreenNativeScale > 0 &&
              container.spoofMaximumFramesPerSecond > 0 &&
              container.spoofScreenBrightness >= 0 && container.spoofScreenBrightness <= 1 &&
              (0...2).contains(container.spoofUserInterfaceStyle) &&
              (0...2).contains(container.spoofDisplayGamut) &&
              (0...2).contains(container.spoofHorizontalSizeClass) &&
              (0...2).contains(container.spoofVerticalSizeClass) &&
              container.spoofSafeAreaTop >= 0 && container.spoofSafeAreaLeft >= 0 &&
              container.spoofSafeAreaBottom >= 0 && container.spoofSafeAreaRight >= 0)
        let extendedValuesValid = (!container.spoofStorageCategoryEnabled || (
              container.spoofStorageTotalCapacity > 0 && container.spoofStorageAvailableCapacity >= 0 &&
              container.spoofStorageAvailableCapacity <= container.spoofStorageTotalCapacity)) &&
            (!container.spoofAudioCategoryEnabled || (
              (0...1).contains(container.spoofAudioOutputVolume) && container.spoofAudioSampleRate > 0 &&
              container.spoofAudioOutputLatency >= 0 && container.spoofAudioInputLatency >= 0 &&
              container.spoofAudioOutputChannels >= 0 && container.spoofAudioInputChannels >= 0)) &&
            (!container.spoofGraphicsCategoryEnabled || container.spoofGPUWorkingSetSize > 0) &&
            (!container.spoofWebViewCategoryEnabled || (1...64).contains(container.spoofWebColorDepth))
        guard systemValuesValid && thermalValueValid && displayValuesValid && extendedValuesValid else {
            errorInfo = "Profile values are invalid. Capacities must be consistent, volume/brightness must be between 0 and 1, and enabled names cannot be empty."
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
        container.spoofHardwareModel = typingSpoofHardwareModel
        container.spoofHostName = container.spoofHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofBoardModel = container.spoofBoardModel.trimmingCharacters(in: .whitespacesAndNewlines)
        container.spoofKernelVersion = container.spoofKernelVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        saveContainer()
    }

    func hasConfiguredSpoofTemplate() -> Bool {
        [typingSpoofDeviceName, typingSpoofDeviceModel, typingSpoofSystemName,
         typingSpoofSystemVersion, typingSpoofLocaleIdentifier,
         typingSpoofTimeZoneIdentifier, typingSpoofHardwareModel]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func applyCurrentDeviceProfileValues() {
        container.spoofIdentifierForVendor = true
        typingIDFV = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
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
        typingSpoofHardwareModel = currentHardwareModel()
        container.spoofHostName = currentSysctlString("kern.hostname")
        container.spoofBoardModel = currentSysctlString("hw.model")
        container.spoofKernelVersion = currentSysctlString("kern.version")
        container.spoofBootTime = Int64(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
        container.spoofCPUType = Int(currentSysctlInt64("hw.cputype"))
        container.spoofCPUSubtype = Int(currentSysctlInt64("hw.cpusubtype"))
        container.spoofProcessorCount = ProcessInfo.processInfo.processorCount
        container.spoofPhysicalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
        container.spoofThermalState = ProcessInfo.processInfo.thermalState.rawValue
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let screen = scene.screen
            container.spoofScreenWidth = screen.nativeBounds.width
            container.spoofScreenHeight = screen.nativeBounds.height
            container.spoofScreenScale = screen.scale
            container.spoofScreenNativeScale = screen.nativeScale
            container.spoofMaximumFramesPerSecond = screen.maximumFramesPerSecond
            container.spoofScreenBrightness = screen.brightness
            let traits = scene.traitCollection
            container.spoofUserInterfaceStyle = traits.userInterfaceStyle.rawValue
            container.spoofAccessibilityContrast = traits.accessibilityContrast.rawValue
            container.spoofDisplayGamut = traits.displayGamut.rawValue
            container.spoofHorizontalSizeClass = traits.horizontalSizeClass.rawValue
            container.spoofVerticalSizeClass = traits.verticalSizeClass.rawValue
            container.spoofPreferredContentSizeCategory = traits.preferredContentSizeCategory.rawValue
            if let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
                container.spoofSafeAreaTop = window.safeAreaInsets.top
                container.spoofSafeAreaLeft = window.safeAreaInsets.left
                container.spoofSafeAreaBottom = window.safeAreaInsets.bottom
                container.spoofSafeAreaRight = window.safeAreaInsets.right
            }
        }
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            container.spoofStorageTotalCapacity = Int64(values.volumeTotalCapacity ?? Int(container.spoofStorageTotalCapacity))
            container.spoofStorageAvailableCapacity = Int64(values.volumeAvailableCapacity ?? Int(container.spoofStorageAvailableCapacity))
        }
        if let gpu = MTLCreateSystemDefaultDevice() {
            container.spoofGPUName = gpu.name
            if #available(iOS 16.0, *) {
                container.spoofGPUWorkingSetSize = Int64(clamping: gpu.recommendedMaxWorkingSetSize)
            } else {
                container.spoofGPUWorkingSetSize = Int64(clamping: ProcessInfo.processInfo.physicalMemory / 2)
            }
        }
        let audio = AVAudioSession.sharedInstance()
        container.spoofAudioOutputVolume = Double(audio.outputVolume)
        container.spoofAudioSampleRate = audio.sampleRate
        container.spoofAudioOutputLatency = audio.outputLatency
        container.spoofAudioInputLatency = audio.inputLatency
        container.spoofAudioOtherPlaying = audio.isOtherAudioPlaying
        container.spoofAudioOutputChannels = audio.outputNumberOfChannels
        container.spoofAudioInputChannels = audio.inputNumberOfChannels
    }

    func applyRandomDeviceProfileValues() {
        let regionalLocales = Self.allLocaleIdentifiers.filter {
            NSLocale.components(fromLocaleIdentifier: $0)[NSLocale.Key.countryCode.rawValue] != nil
        }
        let selectedLocale = regionalLocales.randomElement() ?? "en_US"
        let selectedTimeZone = Self.allTimeZoneIdentifiers.randomElement() ?? "Etc/UTC"

        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let possibleNames = isPad
            ? ["iPad", "My iPad", "iPad Pro", "iPad Air"]
            : ["iPhone", "My iPhone", "iPhone Pro", "iPhone Plus"]
        let selectedName = possibleNames.randomElement() ?? (isPad ? "iPad" : "iPhone")

        let currentSystemName = typingSpoofSystemName.isEmpty ? UIDevice.current.systemName : typingSpoofSystemName
        let majorVersion = parsedRotationOSMajors()?.randomElement() ?? 26
        let minorVersion = Int.random(in: 0...7)
        let patchVersion = Int.random(in: 0...3)
        let batteryLevel = Double.random(in: 0.18...1.0)
        let batteryStateOptions = [
            UIDevice.BatteryState.unplugged.rawValue,
            UIDevice.BatteryState.charging.rawValue,
            UIDevice.BatteryState.full.rawValue
        ]
        let radioTechnology = availableRadioAccessTechnologies().randomElement() ?? "CTRadioAccessTechnologyLTE"
        let tokenBytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        let randomToken = Data(tokenBytes).base64EncodedString()

        container.spoofIdentifierForVendor = true
        typingIDFV = UUID().uuidString
        typingSpoofDeviceName = selectedName
        typingSpoofDeviceModel = isPad ? "iPad" : "iPhone"
        typingSpoofSystemName = currentSystemName
        if patchVersion == 0 {
            typingSpoofSystemVersion = "\(majorVersion).\(minorVersion)"
        } else {
            typingSpoofSystemVersion = "\(majorVersion).\(minorVersion).\(patchVersion)"
        }
        typingSpoofLocaleIdentifier = selectedLocale
        typingSpoofTimeZoneIdentifier = selectedTimeZone
        typingSpoofBatteryLevel = String(format: "%.2f", batteryLevel)
        spoofBatteryStateSelection = batteryStateOptions.randomElement() ?? UIDevice.BatteryState.unplugged.rawValue
        spoofLowPowerModeEnabled = batteryLevel < 0.25
        typingSpoofSubscriberIdentifier = UUID().uuidString.uppercased()
        typingSpoofSubscriberCarrierTokenBase64 = randomToken
        spoofSubscriberSIMInsertedEnabled = true
        spoofSubscriberSIMInserted = Bool.random()
        typingSpoofRadioAccessTechnology = radioTechnology

        // Pick a random hardware model consistent with the device type
        let hardwareModels: [String]
        if isPad {
            hardwareModels = ["iPad16,3", "iPad16,5", "iPad14,8", "iPad14,10"]
        } else {
            hardwareModels = [
                "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4",
                "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4",
                "iPhone16,1", "iPhone16,2", "iPhone15,4", "iPhone15,5"
            ]
        }
        typingSpoofHardwareModel = hardwareModels.randomElement() ?? "iPhone17,3"
        container.spoofHostName = "\(selectedName.replacingOccurrences(of: " ", with: "-"))"
        container.spoofBoardModel = isPad ? "J720AP" : "D93AP"
        let darwinMajor = majorVersion >= 26 ? majorVersion - 1 : majorVersion + 6
        container.spoofKernelVersion = "Darwin Kernel Version \(darwinMajor).0.0"
        container.spoofBootTime = Int64(Date().timeIntervalSince1970) - Int64.random(in: 86_400...1_209_600)
        container.spoofCPUType = 16_777_228
        container.spoofCPUSubtype = 2
        container.spoofProcessorCount = [6, 8, 10].randomElement() ?? 6
        container.spoofPhysicalMemory = Int64(([4, 6, 8, 12].randomElement() ?? 8) * 1_073_741_824)
        container.spoofThermalState = [0, 0, 0, 1].randomElement() ?? 0
        let displayProfiles: [(Double, Double, Double, Double, Int)] = isPad
            ? [(1668, 2420, 2, 2, 120), (2064, 2752, 2, 2, 120)]
            : [(1179, 2556, 3, 3, 60), (1206, 2622, 3, 3, 120), (1290, 2796, 3, 3, 120)]
        let display = displayProfiles.randomElement() ?? (1179, 2556, 3, 3, 60)
        container.spoofScreenWidth = display.0
        container.spoofScreenHeight = display.1
        container.spoofScreenScale = display.2
        container.spoofScreenNativeScale = display.3
        container.spoofMaximumFramesPerSecond = display.4
        container.spoofScreenBrightness = Double.random(in: 0.25...0.85)
        container.spoofUserInterfaceStyle = Bool.random() ? 1 : 2
        container.spoofAccessibilityContrast = Int.random(in: 0...5) == 0 ? 1 : 0
        container.spoofDisplayGamut = 2
        container.spoofHorizontalSizeClass = isPad ? 2 : 1
        container.spoofVerticalSizeClass = 2
        container.spoofPreferredContentSizeCategory = [
            "UICTContentSizeCategoryM", "UICTContentSizeCategoryL", "UICTContentSizeCategoryXL"
        ].randomElement() ?? "UICTContentSizeCategoryL"
        container.spoofSafeAreaTop = isPad ? 24 : 59
        container.spoofSafeAreaLeft = 0
        container.spoofSafeAreaBottom = isPad ? 20 : 34
        container.spoofSafeAreaRight = 0
        let storageGB = [64, 128, 256, 512, 1024].randomElement() ?? 128
        container.spoofStorageTotalCapacity = Int64(storageGB) * 1_073_741_824
        let maximumFreeGB = Int64(max(8, storageGB - 8))
        container.spoofStorageAvailableCapacity = Int64.random(in: 8...maximumFreeGB) * 1_073_741_824
        container.spoofGPUName = "Apple GPU"
        container.spoofGPUWorkingSetSize = Int64(([2, 3, 4, 6].randomElement() ?? 4) * 1_073_741_824)
        container.spoofAudioOutputVolume = Double.random(in: 0.1...0.9)
        container.spoofAudioSampleRate = [44_100.0, 48_000.0, 96_000.0].randomElement() ?? 48_000
        container.spoofAudioOutputLatency = Double.random(in: 0.005...0.03)
        container.spoofAudioInputLatency = Double.random(in: 0.005...0.03)
        container.spoofAudioOtherPlaying = Bool.random()
        container.spoofAudioOutputChannels = [1, 2].randomElement() ?? 2
        container.spoofAudioInputChannels = [0, 1, 2].randomElement() ?? 1
    }

    private func parsedRotationOSMajors() -> [Int]? {
        let values = container.rotateOSMajorVersions
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !values.isEmpty,
              values.allSatisfy({ value in
                  guard !value.isEmpty, let major = Int(value) else { return false }
                  return (1...99).contains(major)
              }) else {
            return nil
        }
        return Array(Set(values.compactMap(Int.init))).sorted()
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

    func localeDisplayName(_ identifier: String) -> String {
        let localized = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        return "\(localized) — \(identifier)"
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

    func currentHardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    func currentSysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "" }
        return String(cString: value)
    }

    func currentSysctlInt64(_ name: String) -> Int64 {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return value }
        var value32: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname(name, &value32, &size, nil, 0) == 0 { return Int64(value32) }
        return 0
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
