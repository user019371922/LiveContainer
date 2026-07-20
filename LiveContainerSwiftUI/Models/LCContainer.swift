//
//  LCAppInfo.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/12/5.
//

import Foundation

class LCContainer : ObservableObject, Hashable {
    @Published var folderName : String
    @Published var name : String
    @Published var isShared : Bool
    
    @Published var storageBookMark: Data?
    @Published var resolvedContainerURL: URL?
    @Published var bookmarkResolved = false
    var bookmarkResolveContinuation: UnsafeContinuation<(), Never>? = nil
    
    @Published var isolateAppGroup : Bool

    @Published var spoofIdentifierForVendor : Bool {
        didSet {
            if spoofIdentifierForVendor && spoofedIdentifier == nil {
                spoofedIdentifier = UUID().uuidString
            }
        }
    }
    public var spoofedIdentifier: String?
    @Published var strictTestMode: Bool
    @Published var strictAutoWipeOnExit: Bool
    @Published var blockDeviceInfoReads: Bool
    @Published var spoofProfileEnabled: Bool
    @Published var rotateSpoofProfileOnLaunch: Bool
    @Published var rotateOSMajorVersions: String
    @Published var rotateUsesRealDeviceTemplates: Bool
    @Published var spoofIdentityCategoryEnabled: Bool
    @Published var spoofSystemCategoryEnabled: Bool
    @Published var spoofDisplayCategoryEnabled: Bool
    @Published var spoofLocaleCategoryEnabled: Bool
    @Published var spoofBatteryCategoryEnabled: Bool
    @Published var spoofTelephonyCategoryEnabled: Bool
    @Published var spoofNetworkHeadersCategoryEnabled: Bool
    @Published var spoofAccessibilityCategoryEnabled: Bool
    @Published var spoofStorageCategoryEnabled: Bool
    @Published var spoofNetworkEnvironmentCategoryEnabled: Bool
    @Published var spoofAudioCategoryEnabled: Bool
    @Published var spoofGraphicsCategoryEnabled: Bool
    @Published var spoofWebViewCategoryEnabled: Bool
    @Published var spoofAppPrivacyCategoryEnabled: Bool
    @Published var spoofSensorsAndUserDataCategoryEnabled: Bool
    @Published var spoofDeviceName: String
    @Published var spoofDeviceModel: String
    @Published var spoofSystemName: String
    @Published var spoofSystemVersion: String
    @Published var spoofLocaleIdentifier: String
    @Published var spoofTimeZoneIdentifier: String
    @Published var spoofBatteryLevel: Double
    @Published var spoofBatteryState: Int
    @Published var spoofLowPowerModeEnabled: Bool
    @Published var spoofSubscriberIdentifier: String
    @Published var spoofSubscriberCarrierTokenBase64: String
    @Published var spoofSubscriberSIMInsertedEnabled: Bool
    @Published var spoofSubscriberSIMInserted: Bool
    @Published var spoofRadioAccessTechnology: String
    @Published var spoofHardwareModel: String
    @Published var spoofHostName: String
    @Published var spoofBoardModel: String
    @Published var spoofKernelVersion: String
    @Published var spoofBootTime: Int64
    @Published var spoofCPUType: Int
    @Published var spoofCPUSubtype: Int
    @Published var spoofProcessorCount: Int
    @Published var spoofPhysicalMemory: Int64
    @Published var spoofThermalState: Int
    @Published var spoofScreenWidth: Double
    @Published var spoofScreenHeight: Double
    @Published var spoofScreenScale: Double
    @Published var spoofScreenNativeScale: Double
    @Published var spoofMaximumFramesPerSecond: Int
    @Published var spoofScreenBrightness: Double
    @Published var spoofUserInterfaceStyle: Int
    @Published var spoofAccessibilityContrast: Int
    @Published var spoofDisplayGamut: Int
    @Published var spoofHorizontalSizeClass: Int
    @Published var spoofVerticalSizeClass: Int
    @Published var spoofPreferredContentSizeCategory: String
    @Published var spoofSafeAreaTop: Double
    @Published var spoofSafeAreaLeft: Double
    @Published var spoofSafeAreaBottom: Double
    @Published var spoofSafeAreaRight: Double
    @Published var spoofStorageTotalCapacity: Int64
    @Published var spoofStorageAvailableCapacity: Int64
    @Published var spoofGPUName: String
    @Published var spoofAudioOutputVolume: Double
    private var infoDict : [String:Any]?
    public var containerURL : URL {
        if let resolvedContainerURL {
            return resolvedContainerURL
        }
        
        if isShared {
            return LCPath.lcGroupDataPath.appendingPathComponent("\(folderName)")
        } else {
            return LCPath.dataPath.appendingPathComponent("\(folderName)")
        }
    }
    private var infoDictUrl : URL {
        return containerURL.appendingPathComponent("LCContainerInfo.plist")
    }
    public var keychainGroupId : Int {
        get {
            if infoDict == nil {
                infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
            }
            guard let infoDict else {
                return -1
            }
            return infoDict["keychainGroupId"] as? Int ?? -1
        }
    }
    
    public var appIdentifier : String? {
        get {
            if infoDict == nil {
                infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
            }
            guard let infoDict else {
                return nil
            }
            return infoDict["appIdentifier"] as? String ?? nil
        }
    }
    
    init(
        folderName: String,
        name: String,
        isShared : Bool,
        isolateAppGroup: Bool = false,
        spoofIdentifierForVendor: Bool = false,
        strictTestMode: Bool = false,
        strictAutoWipeOnExit: Bool = false,
        blockDeviceInfoReads: Bool = false,
        spoofProfileEnabled: Bool = false,
        rotateSpoofProfileOnLaunch: Bool = false,
        rotateOSMajorVersions: String = "18,26,27",
        rotateUsesRealDeviceTemplates: Bool = true,
        spoofIdentityCategoryEnabled: Bool = true,
        spoofSystemCategoryEnabled: Bool = true,
        spoofDisplayCategoryEnabled: Bool = true,
        spoofLocaleCategoryEnabled: Bool = true,
        spoofBatteryCategoryEnabled: Bool = true,
        spoofTelephonyCategoryEnabled: Bool = true,
        spoofNetworkHeadersCategoryEnabled: Bool = true,
        spoofAccessibilityCategoryEnabled: Bool = true,
        spoofStorageCategoryEnabled: Bool = true,
        spoofNetworkEnvironmentCategoryEnabled: Bool = true,
        spoofAudioCategoryEnabled: Bool = true,
        spoofGraphicsCategoryEnabled: Bool = true,
        spoofWebViewCategoryEnabled: Bool = true,
        spoofAppPrivacyCategoryEnabled: Bool = true,
        spoofSensorsAndUserDataCategoryEnabled: Bool = true,
        spoofDeviceName: String = "",
        spoofDeviceModel: String = "",
        spoofSystemName: String = "",
        spoofSystemVersion: String = "",
        spoofLocaleIdentifier: String = "",
        spoofTimeZoneIdentifier: String = "",
        spoofBatteryLevel: Double = 0.8,
        spoofBatteryState: Int = 2,
        spoofLowPowerModeEnabled: Bool = false,
        spoofSubscriberIdentifier: String = "",
        spoofSubscriberCarrierTokenBase64: String = "",
        spoofSubscriberSIMInsertedEnabled: Bool = false,
        spoofSubscriberSIMInserted: Bool = false,
        spoofRadioAccessTechnology: String = "",
        spoofHardwareModel: String = "",
        spoofHostName: String = "",
        spoofBoardModel: String = "",
        spoofKernelVersion: String = "Darwin Kernel Version 25.0.0",
        spoofBootTime: Int64 = 0,
        spoofCPUType: Int = 16_777_228,
        spoofCPUSubtype: Int = 2,
        spoofProcessorCount: Int = 6,
        spoofPhysicalMemory: Int64 = 6_442_450_944,
        spoofThermalState: Int = 0,
        spoofScreenWidth: Double = 1179,
        spoofScreenHeight: Double = 2556,
        spoofScreenScale: Double = 3,
        spoofScreenNativeScale: Double = 3,
        spoofMaximumFramesPerSecond: Int = 60,
        spoofScreenBrightness: Double = 0.5,
        spoofUserInterfaceStyle: Int = 1,
        spoofAccessibilityContrast: Int = 0,
        spoofDisplayGamut: Int = 2,
        spoofHorizontalSizeClass: Int = 1,
        spoofVerticalSizeClass: Int = 2,
        spoofPreferredContentSizeCategory: String = "UICTContentSizeCategoryL",
        spoofSafeAreaTop: Double = 59,
        spoofSafeAreaLeft: Double = 0,
        spoofSafeAreaBottom: Double = 34,
        spoofSafeAreaRight: Double = 0,
        spoofStorageTotalCapacity: Int64 = 137_438_953_472,
        spoofStorageAvailableCapacity: Int64 = 68_719_476_736,
        spoofGPUName: String = "Apple GPU",
        spoofAudioOutputVolume: Double = 0.5,
        bookmarkData: Data? = nil,
        resolvedContainerURL: URL? = nil
    ) {
        self.folderName = folderName
        self.name = name
        self.isShared = isShared
        self.isolateAppGroup = isolateAppGroup
        self.spoofIdentifierForVendor = spoofIdentifierForVendor
        self.strictTestMode = strictTestMode
        self.strictAutoWipeOnExit = strictAutoWipeOnExit
        self.blockDeviceInfoReads = blockDeviceInfoReads
        self.spoofProfileEnabled = spoofProfileEnabled
        self.rotateSpoofProfileOnLaunch = rotateSpoofProfileOnLaunch
        self.rotateOSMajorVersions = rotateOSMajorVersions
        self.rotateUsesRealDeviceTemplates = rotateUsesRealDeviceTemplates
        self.spoofIdentityCategoryEnabled = spoofIdentityCategoryEnabled
        self.spoofSystemCategoryEnabled = spoofSystemCategoryEnabled
        self.spoofDisplayCategoryEnabled = spoofDisplayCategoryEnabled
        self.spoofLocaleCategoryEnabled = spoofLocaleCategoryEnabled
        self.spoofBatteryCategoryEnabled = spoofBatteryCategoryEnabled
        self.spoofTelephonyCategoryEnabled = spoofTelephonyCategoryEnabled
        self.spoofNetworkHeadersCategoryEnabled = spoofNetworkHeadersCategoryEnabled
        self.spoofAccessibilityCategoryEnabled = spoofAccessibilityCategoryEnabled
        self.spoofStorageCategoryEnabled = spoofStorageCategoryEnabled
        self.spoofNetworkEnvironmentCategoryEnabled = spoofNetworkEnvironmentCategoryEnabled
        self.spoofAudioCategoryEnabled = spoofAudioCategoryEnabled
        self.spoofGraphicsCategoryEnabled = spoofGraphicsCategoryEnabled
        self.spoofWebViewCategoryEnabled = spoofWebViewCategoryEnabled
        self.spoofAppPrivacyCategoryEnabled = spoofAppPrivacyCategoryEnabled
        self.spoofSensorsAndUserDataCategoryEnabled = spoofSensorsAndUserDataCategoryEnabled
        self.spoofDeviceName = spoofDeviceName
        self.spoofDeviceModel = spoofDeviceModel
        self.spoofSystemName = spoofSystemName
        self.spoofSystemVersion = spoofSystemVersion
        self.spoofLocaleIdentifier = spoofLocaleIdentifier
        self.spoofTimeZoneIdentifier = spoofTimeZoneIdentifier
        self.spoofBatteryLevel = spoofBatteryLevel
        self.spoofBatteryState = spoofBatteryState
        self.spoofLowPowerModeEnabled = spoofLowPowerModeEnabled
        self.spoofSubscriberIdentifier = spoofSubscriberIdentifier
        self.spoofSubscriberCarrierTokenBase64 = spoofSubscriberCarrierTokenBase64
        self.spoofSubscriberSIMInsertedEnabled = spoofSubscriberSIMInsertedEnabled
        self.spoofSubscriberSIMInserted = spoofSubscriberSIMInserted
        self.spoofRadioAccessTechnology = spoofRadioAccessTechnology
        self.spoofHardwareModel = spoofHardwareModel
        self.spoofHostName = spoofHostName
        self.spoofBoardModel = spoofBoardModel
        self.spoofKernelVersion = spoofKernelVersion
        self.spoofBootTime = spoofBootTime
        self.spoofCPUType = spoofCPUType
        self.spoofCPUSubtype = spoofCPUSubtype
        self.spoofProcessorCount = spoofProcessorCount
        self.spoofPhysicalMemory = spoofPhysicalMemory
        self.spoofThermalState = spoofThermalState
        self.spoofScreenWidth = spoofScreenWidth
        self.spoofScreenHeight = spoofScreenHeight
        self.spoofScreenScale = spoofScreenScale
        self.spoofScreenNativeScale = spoofScreenNativeScale
        self.spoofMaximumFramesPerSecond = spoofMaximumFramesPerSecond
        self.spoofScreenBrightness = spoofScreenBrightness
        self.spoofUserInterfaceStyle = spoofUserInterfaceStyle
        self.spoofAccessibilityContrast = spoofAccessibilityContrast
        self.spoofDisplayGamut = spoofDisplayGamut
        self.spoofHorizontalSizeClass = spoofHorizontalSizeClass
        self.spoofVerticalSizeClass = spoofVerticalSizeClass
        self.spoofPreferredContentSizeCategory = spoofPreferredContentSizeCategory
        self.spoofSafeAreaTop = spoofSafeAreaTop
        self.spoofSafeAreaLeft = spoofSafeAreaLeft
        self.spoofSafeAreaBottom = spoofSafeAreaBottom
        self.spoofSafeAreaRight = spoofSafeAreaRight
        self.spoofStorageTotalCapacity = spoofStorageTotalCapacity
        self.spoofStorageAvailableCapacity = spoofStorageAvailableCapacity
        self.spoofGPUName = spoofGPUName
        self.spoofAudioOutputVolume = spoofAudioOutputVolume
        self.storageBookMark = bookmarkData
        self.resolvedContainerURL = resolvedContainerURL
    }
    
    convenience init(infoDict : [String : Any], isShared : Bool) {
        let bookmarkData : Data? = infoDict["bookmarkData"] as? Data
        
        self.init(folderName: infoDict["folderName"] as? String ?? "ERROR",
                  name: infoDict["name"] as? String ?? "ERROR",
                  isShared: isShared,
                  isolateAppGroup: false,
                  spoofIdentifierForVendor: false,
                  strictTestMode: false,
                  strictAutoWipeOnExit: false,
                  blockDeviceInfoReads: false,
                  spoofProfileEnabled: false,
                  rotateSpoofProfileOnLaunch: false,
                  rotateOSMajorVersions: "18,26,27",
                  rotateUsesRealDeviceTemplates: true,
                  spoofIdentityCategoryEnabled: true,
                  spoofSystemCategoryEnabled: true,
                  spoofDisplayCategoryEnabled: true,
                  spoofLocaleCategoryEnabled: true,
                  spoofBatteryCategoryEnabled: true,
                  spoofTelephonyCategoryEnabled: true,
                  spoofNetworkHeadersCategoryEnabled: true,
                  spoofAccessibilityCategoryEnabled: true,
                  spoofStorageCategoryEnabled: true,
                  spoofNetworkEnvironmentCategoryEnabled: true,
                  spoofAudioCategoryEnabled: true,
                  spoofGraphicsCategoryEnabled: true,
                  spoofWebViewCategoryEnabled: true,
                  spoofAppPrivacyCategoryEnabled: true,
                  spoofSensorsAndUserDataCategoryEnabled: true,
                  spoofDeviceName: "",
                  spoofDeviceModel: "",
                  spoofSystemName: "",
                  spoofSystemVersion: "",
                  spoofLocaleIdentifier: "",
                  spoofTimeZoneIdentifier: "",
                  spoofBatteryLevel: 0.8,
                  spoofBatteryState: 2,
                  spoofLowPowerModeEnabled: false,
                  spoofSubscriberIdentifier: "",
                  spoofSubscriberCarrierTokenBase64: "",
                  spoofSubscriberSIMInsertedEnabled: false,
                  spoofSubscriberSIMInserted: false,
                  spoofRadioAccessTechnology: "",
                  spoofHardwareModel: "",
                  spoofHostName: "",
                  spoofBoardModel: "",
                  spoofKernelVersion: "Darwin Kernel Version 25.0.0",
                  spoofBootTime: 0,
                  spoofCPUType: 16_777_228,
                  spoofCPUSubtype: 2,
                  spoofProcessorCount: 6,
                  spoofPhysicalMemory: 6_442_450_944,
                  spoofThermalState: 0,
                  spoofScreenWidth: 1179,
                  spoofScreenHeight: 2556,
                  spoofScreenScale: 3,
                  spoofScreenNativeScale: 3,
                  spoofMaximumFramesPerSecond: 60,
                  spoofScreenBrightness: 0.5,
                  spoofStorageTotalCapacity: 137_438_953_472,
                  spoofStorageAvailableCapacity: 68_719_476_736,
                  spoofGPUName: "Apple GPU",
                  spoofAudioOutputVolume: 0.5,
                  bookmarkData: bookmarkData,
                  resolvedContainerURL: nil
        )
        
        if let bookmarkData {

                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)

                    self.resolvedContainerURL = url

                } catch {
                    print(error.localizedDescription)
                }

                self.bookmarkResolved = true
        }
        
        do {
            let fm = FileManager.default
            if(!fm.fileExists(atPath: infoDictUrl.deletingLastPathComponent().path)) {
                try fm.createDirectory(at: infoDictUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            
            let plistInfo = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoDictUrl), format: nil)
            if let plistInfo = plistInfo as? [String : Any] {
                isolateAppGroup = plistInfo["isolateAppGroup"] as? Bool ?? false
                spoofIdentifierForVendor = plistInfo["spoofIdentifierForVendor"] as? Bool ?? false
                spoofedIdentifier = plistInfo["spoofedIdentifierForVendor"] as? String
                strictTestMode = plistInfo["strictTestMode"] as? Bool ?? false
                strictAutoWipeOnExit = plistInfo["strictAutoWipeOnExit"] as? Bool ?? false
                blockDeviceInfoReads = plistInfo["blockDeviceInfoReads"] as? Bool ?? false
                spoofProfileEnabled = plistInfo["spoofProfileEnabled"] as? Bool ?? false
                loadSpoofCategorySettings(from: plistInfo)
                spoofDeviceName = plistInfo["spoofDeviceName"] as? String ?? ""
                spoofDeviceModel = plistInfo["spoofDeviceModel"] as? String ?? ""
                spoofSystemName = plistInfo["spoofSystemName"] as? String ?? ""
                spoofSystemVersion = plistInfo["spoofSystemVersion"] as? String ?? ""
                spoofLocaleIdentifier = plistInfo["spoofLocaleIdentifier"] as? String ?? ""
                spoofTimeZoneIdentifier = plistInfo["spoofTimeZoneIdentifier"] as? String ?? ""
                spoofBatteryLevel = plistInfo["spoofBatteryLevel"] as? Double ?? 0.8
                spoofBatteryState = plistInfo["spoofBatteryState"] as? Int ?? 2
                spoofLowPowerModeEnabled = plistInfo["spoofLowPowerModeEnabled"] as? Bool ?? false
                spoofSubscriberIdentifier = plistInfo["spoofSubscriberIdentifier"] as? String ?? ""
                spoofSubscriberCarrierTokenBase64 = plistInfo["spoofSubscriberCarrierTokenBase64"] as? String ?? ""
                spoofSubscriberSIMInsertedEnabled = plistInfo["spoofSubscriberSIMInsertedEnabled"] as? Bool ?? false
                spoofSubscriberSIMInserted = plistInfo["spoofSubscriberSIMInserted"] as? Bool ?? false
                spoofRadioAccessTechnology = plistInfo["spoofRadioAccessTechnology"] as? String ?? ""
                spoofHardwareModel = plistInfo["spoofHardwareModel"] as? String ?? ""
                loadSystemDisplayProfile(from: plistInfo)
            }
        } catch {
            
        }
    }
    
    func toDict() -> [String : Any] {
        var ans : [String: Any] = [
            "folderName" : folderName,
            "name" : name
        ]
        if let storageBookMark {
            ans["bookmarkData"] = storageBookMark
        }
        return ans
    }
    
    func makeLCContainerInfoPlist(appIdentifier : String, keychainGroupId : Int) {
        infoDict = [
            "appIdentifier" : appIdentifier,
            "name" : name,
            "keychainGroupId" : keychainGroupId,
            "isolateAppGroup" : isolateAppGroup,
            "spoofIdentifierForVendor": spoofIdentifierForVendor,
            "strictTestMode": strictTestMode,
            "strictAutoWipeOnExit": strictAutoWipeOnExit,
            "blockDeviceInfoReads": blockDeviceInfoReads,
            "spoofProfileEnabled": spoofProfileEnabled,
            "rotateSpoofProfileOnLaunch": rotateSpoofProfileOnLaunch,
            "rotateOSMajorVersions": rotateOSMajorVersions,
            "rotateUsesRealDeviceTemplates": rotateUsesRealDeviceTemplates,
            "spoofIdentityCategoryEnabled": spoofIdentityCategoryEnabled,
            "spoofSystemCategoryEnabled": spoofSystemCategoryEnabled,
            "spoofDisplayCategoryEnabled": spoofDisplayCategoryEnabled,
            "spoofLocaleCategoryEnabled": spoofLocaleCategoryEnabled,
            "spoofBatteryCategoryEnabled": spoofBatteryCategoryEnabled,
            "spoofTelephonyCategoryEnabled": spoofTelephonyCategoryEnabled,
            "spoofNetworkHeadersCategoryEnabled": spoofNetworkHeadersCategoryEnabled,
            "spoofAccessibilityCategoryEnabled": spoofAccessibilityCategoryEnabled,
            "spoofStorageCategoryEnabled": spoofStorageCategoryEnabled,
            "spoofNetworkEnvironmentCategoryEnabled": spoofNetworkEnvironmentCategoryEnabled,
            "spoofAudioCategoryEnabled": spoofAudioCategoryEnabled,
            "spoofGraphicsCategoryEnabled": spoofGraphicsCategoryEnabled,
            "spoofWebViewCategoryEnabled": spoofWebViewCategoryEnabled,
            "spoofAppPrivacyCategoryEnabled": spoofAppPrivacyCategoryEnabled,
            "spoofSensorsAndUserDataCategoryEnabled": spoofSensorsAndUserDataCategoryEnabled
        ]
        if let spoofedIdentifier {
            infoDict!["spoofedIdentifierForVendor"] = spoofedIdentifier
        }
        if !spoofDeviceName.isEmpty {
            infoDict!["spoofDeviceName"] = spoofDeviceName
        }
        if !spoofDeviceModel.isEmpty {
            infoDict!["spoofDeviceModel"] = spoofDeviceModel
        }
        if !spoofSystemName.isEmpty {
            infoDict!["spoofSystemName"] = spoofSystemName
        }
        if !spoofSystemVersion.isEmpty {
            infoDict!["spoofSystemVersion"] = spoofSystemVersion
        }
        if !spoofLocaleIdentifier.isEmpty {
            infoDict!["spoofLocaleIdentifier"] = spoofLocaleIdentifier
        }
        if !spoofTimeZoneIdentifier.isEmpty {
            infoDict!["spoofTimeZoneIdentifier"] = spoofTimeZoneIdentifier
        }
        infoDict!["spoofBatteryLevel"] = spoofBatteryLevel
        infoDict!["spoofBatteryState"] = spoofBatteryState
        infoDict!["spoofLowPowerModeEnabled"] = spoofLowPowerModeEnabled
        if !spoofSubscriberIdentifier.isEmpty {
            infoDict!["spoofSubscriberIdentifier"] = spoofSubscriberIdentifier
        }
        if !spoofSubscriberCarrierTokenBase64.isEmpty {
            infoDict!["spoofSubscriberCarrierTokenBase64"] = spoofSubscriberCarrierTokenBase64
        }
        infoDict!["spoofSubscriberSIMInsertedEnabled"] = spoofSubscriberSIMInsertedEnabled
        infoDict!["spoofSubscriberSIMInserted"] = spoofSubscriberSIMInserted
        if !spoofRadioAccessTechnology.isEmpty {
            infoDict!["spoofRadioAccessTechnology"] = spoofRadioAccessTechnology
        }
        if !spoofHardwareModel.isEmpty {
            infoDict!["spoofHardwareModel"] = spoofHardwareModel
        }
        infoDict!["spoofStorageTotalCapacity"] = spoofStorageTotalCapacity
        infoDict!["spoofStorageAvailableCapacity"] = spoofStorageAvailableCapacity
        infoDict!["spoofGPUName"] = spoofGPUName
        infoDict!["spoofAudioOutputVolume"] = spoofAudioOutputVolume
        infoDict!["spoofUserInterfaceStyle"] = spoofUserInterfaceStyle
        infoDict!["spoofAccessibilityContrast"] = spoofAccessibilityContrast
        infoDict!["spoofDisplayGamut"] = spoofDisplayGamut
        infoDict!["spoofHorizontalSizeClass"] = spoofHorizontalSizeClass
        infoDict!["spoofVerticalSizeClass"] = spoofVerticalSizeClass
        infoDict!["spoofPreferredContentSizeCategory"] = spoofPreferredContentSizeCategory
        infoDict!["spoofSafeAreaTop"] = spoofSafeAreaTop
        infoDict!["spoofSafeAreaLeft"] = spoofSafeAreaLeft
        infoDict!["spoofSafeAreaBottom"] = spoofSafeAreaBottom
        infoDict!["spoofSafeAreaRight"] = spoofSafeAreaRight
        writeSystemDisplayProfile(to: &infoDict!)
        
        do {
            let fm = FileManager.default
            if(!fm.fileExists(atPath: infoDictUrl.deletingLastPathComponent().path)) {
                try fm.createDirectory(at: infoDictUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            
            let plistData = try PropertyListSerialization.data(fromPropertyList: infoDict as Any, format: .binary, options: 0)
            try plistData.write(to: infoDictUrl)
        } catch {
            
        }
    }
    
    func reloadInfoPlist() {
        infoDict = NSDictionary(contentsOf: infoDictUrl) as? [String : Any]
    }

    func loadName() {
        reloadInfoPlist()
        guard let infoDict else {
            return
        }
        name = infoDict["name"] as? String ?? "ERROR"
        isolateAppGroup = infoDict["isolateAppGroup"] as? Bool ?? false
        spoofIdentifierForVendor = infoDict["spoofIdentifierForVendor"] as? Bool ?? false
        spoofedIdentifier = infoDict["spoofedIdentifierForVendor"] as? String
        strictTestMode = infoDict["strictTestMode"] as? Bool ?? false
        strictAutoWipeOnExit = infoDict["strictAutoWipeOnExit"] as? Bool ?? false
        blockDeviceInfoReads = infoDict["blockDeviceInfoReads"] as? Bool ?? false
        spoofProfileEnabled = infoDict["spoofProfileEnabled"] as? Bool ?? false
        loadSpoofCategorySettings(from: infoDict)
        spoofDeviceName = infoDict["spoofDeviceName"] as? String ?? ""
        spoofDeviceModel = infoDict["spoofDeviceModel"] as? String ?? ""
        spoofSystemName = infoDict["spoofSystemName"] as? String ?? ""
        spoofSystemVersion = infoDict["spoofSystemVersion"] as? String ?? ""
        spoofLocaleIdentifier = infoDict["spoofLocaleIdentifier"] as? String ?? ""
        spoofTimeZoneIdentifier = infoDict["spoofTimeZoneIdentifier"] as? String ?? ""
        spoofBatteryLevel = infoDict["spoofBatteryLevel"] as? Double ?? 0.8
        spoofBatteryState = infoDict["spoofBatteryState"] as? Int ?? 2
        spoofLowPowerModeEnabled = infoDict["spoofLowPowerModeEnabled"] as? Bool ?? false
        spoofSubscriberIdentifier = infoDict["spoofSubscriberIdentifier"] as? String ?? ""
        spoofSubscriberCarrierTokenBase64 = infoDict["spoofSubscriberCarrierTokenBase64"] as? String ?? ""
        spoofSubscriberSIMInsertedEnabled = infoDict["spoofSubscriberSIMInsertedEnabled"] as? Bool ?? false
        spoofSubscriberSIMInserted = infoDict["spoofSubscriberSIMInserted"] as? Bool ?? false
        spoofRadioAccessTechnology = infoDict["spoofRadioAccessTechnology"] as? String ?? ""
        spoofHardwareModel = infoDict["spoofHardwareModel"] as? String ?? ""
        loadSystemDisplayProfile(from: infoDict)
    }

    private func loadSystemDisplayProfile(from dictionary: [String: Any]) {
        spoofHostName = dictionary["spoofHostName"] as? String ?? ""
        spoofBoardModel = dictionary["spoofBoardModel"] as? String ?? ""
        spoofKernelVersion = dictionary["spoofKernelVersion"] as? String ?? "Darwin Kernel Version 25.0.0"
        spoofBootTime = dictionary["spoofBootTime"] as? Int64
            ?? Int64(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
        spoofCPUType = dictionary["spoofCPUType"] as? Int ?? 16_777_228
        spoofCPUSubtype = dictionary["spoofCPUSubtype"] as? Int ?? 2
        spoofProcessorCount = dictionary["spoofProcessorCount"] as? Int ?? 6
        spoofPhysicalMemory = dictionary["spoofPhysicalMemory"] as? Int64 ?? 6_442_450_944
        spoofThermalState = dictionary["spoofThermalState"] as? Int ?? 0
        spoofScreenWidth = dictionary["spoofScreenWidth"] as? Double ?? 1179
        spoofScreenHeight = dictionary["spoofScreenHeight"] as? Double ?? 2556
        spoofScreenScale = dictionary["spoofScreenScale"] as? Double ?? 3
        spoofScreenNativeScale = dictionary["spoofScreenNativeScale"] as? Double ?? 3
        spoofMaximumFramesPerSecond = dictionary["spoofMaximumFramesPerSecond"] as? Int ?? 60
        spoofScreenBrightness = dictionary["spoofScreenBrightness"] as? Double ?? 0.5
        spoofStorageTotalCapacity = dictionary["spoofStorageTotalCapacity"] as? Int64 ?? 137_438_953_472
        spoofStorageAvailableCapacity = dictionary["spoofStorageAvailableCapacity"] as? Int64 ?? 68_719_476_736
        spoofGPUName = dictionary["spoofGPUName"] as? String ?? "Apple GPU"
        spoofAudioOutputVolume = dictionary["spoofAudioOutputVolume"] as? Double ?? 0.5
        spoofUserInterfaceStyle = dictionary["spoofUserInterfaceStyle"] as? Int ?? 1
        spoofAccessibilityContrast = dictionary["spoofAccessibilityContrast"] as? Int ?? 0
        spoofDisplayGamut = dictionary["spoofDisplayGamut"] as? Int ?? 2
        spoofHorizontalSizeClass = dictionary["spoofHorizontalSizeClass"] as? Int ?? 1
        spoofVerticalSizeClass = dictionary["spoofVerticalSizeClass"] as? Int ?? 2
        spoofPreferredContentSizeCategory = dictionary["spoofPreferredContentSizeCategory"] as? String ?? "UICTContentSizeCategoryL"
        spoofSafeAreaTop = dictionary["spoofSafeAreaTop"] as? Double ?? 59
        spoofSafeAreaLeft = dictionary["spoofSafeAreaLeft"] as? Double ?? 0
        spoofSafeAreaBottom = dictionary["spoofSafeAreaBottom"] as? Double ?? 34
        spoofSafeAreaRight = dictionary["spoofSafeAreaRight"] as? Double ?? 0
    }

    private func loadSpoofCategorySettings(from dictionary: [String: Any]) {
        rotateSpoofProfileOnLaunch = dictionary["rotateSpoofProfileOnLaunch"] as? Bool ?? false
        rotateOSMajorVersions = dictionary["rotateOSMajorVersions"] as? String ?? "18,26,27"
        rotateUsesRealDeviceTemplates = dictionary["rotateUsesRealDeviceTemplates"] as? Bool ?? true
        spoofIdentityCategoryEnabled = dictionary["spoofIdentityCategoryEnabled"] as? Bool ?? true
        spoofSystemCategoryEnabled = dictionary["spoofSystemCategoryEnabled"] as? Bool ?? true
        spoofDisplayCategoryEnabled = dictionary["spoofDisplayCategoryEnabled"] as? Bool ?? true
        spoofLocaleCategoryEnabled = dictionary["spoofLocaleCategoryEnabled"] as? Bool ?? true
        spoofBatteryCategoryEnabled = dictionary["spoofBatteryCategoryEnabled"] as? Bool ?? true
        spoofTelephonyCategoryEnabled = dictionary["spoofTelephonyCategoryEnabled"] as? Bool ?? true
        spoofNetworkHeadersCategoryEnabled = dictionary["spoofNetworkHeadersCategoryEnabled"] as? Bool ?? true
        spoofAccessibilityCategoryEnabled = dictionary["spoofAccessibilityCategoryEnabled"] as? Bool ?? true
        spoofStorageCategoryEnabled = dictionary["spoofStorageCategoryEnabled"] as? Bool ?? true
        spoofNetworkEnvironmentCategoryEnabled = dictionary["spoofNetworkEnvironmentCategoryEnabled"] as? Bool ?? true
        spoofAudioCategoryEnabled = dictionary["spoofAudioCategoryEnabled"] as? Bool ?? true
        spoofGraphicsCategoryEnabled = dictionary["spoofGraphicsCategoryEnabled"] as? Bool ?? true
        spoofWebViewCategoryEnabled = dictionary["spoofWebViewCategoryEnabled"] as? Bool ?? true
        spoofAppPrivacyCategoryEnabled = dictionary["spoofAppPrivacyCategoryEnabled"] as? Bool ?? true
        spoofSensorsAndUserDataCategoryEnabled = dictionary["spoofSensorsAndUserDataCategoryEnabled"] as? Bool ?? true
    }

    private func writeSystemDisplayProfile(to dictionary: inout [String: Any]) {
        if !spoofHostName.isEmpty { dictionary["spoofHostName"] = spoofHostName }
        if !spoofBoardModel.isEmpty { dictionary["spoofBoardModel"] = spoofBoardModel }
        if !spoofKernelVersion.isEmpty { dictionary["spoofKernelVersion"] = spoofKernelVersion }
        if spoofBootTime > 0 { dictionary["spoofBootTime"] = spoofBootTime }
        if spoofCPUType > 0 { dictionary["spoofCPUType"] = spoofCPUType }
        if spoofCPUSubtype >= 0 { dictionary["spoofCPUSubtype"] = spoofCPUSubtype }
        if spoofProcessorCount > 0 { dictionary["spoofProcessorCount"] = spoofProcessorCount }
        if spoofPhysicalMemory > 0 { dictionary["spoofPhysicalMemory"] = spoofPhysicalMemory }
        if spoofThermalState >= 0 { dictionary["spoofThermalState"] = spoofThermalState }
        if spoofScreenWidth > 0 { dictionary["spoofScreenWidth"] = spoofScreenWidth }
        if spoofScreenHeight > 0 { dictionary["spoofScreenHeight"] = spoofScreenHeight }
        if spoofScreenScale > 0 { dictionary["spoofScreenScale"] = spoofScreenScale }
        if spoofScreenNativeScale > 0 { dictionary["spoofScreenNativeScale"] = spoofScreenNativeScale }
        if spoofMaximumFramesPerSecond > 0 { dictionary["spoofMaximumFramesPerSecond"] = spoofMaximumFramesPerSecond }
        if spoofScreenBrightness >= 0 { dictionary["spoofScreenBrightness"] = spoofScreenBrightness }
    }
    
    static func == (lhs: LCContainer, rhs: LCContainer) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension LCAppInfo {
    var containers : [LCContainer] {
        get {
            if self is BuiltInSideStoreAppInfo {
                let container = LCContainer(folderName: "", name: "SideStore", isShared: false)
                container.resolvedContainerURL = LCPath.docPath.appendingPathComponent("SideStore")
                return [container]
            }
            
            var upgrade = false
            // upgrade
            if let oldDataUUID = dataUUID, containerInfo == nil {
                containerInfo = [[
                    "folderName": oldDataUUID,
                    "name": oldDataUUID
                ]]
                upgrade = true
            }
            let dictArr = containerInfo as? [[String : Any]] ?? []
            return dictArr.map{ dict in
                let ans = LCContainer(infoDict: dict, isShared: isShared)
                if upgrade {
                    ans.makeLCContainerInfoPlist(appIdentifier: bundleIdentifier()!, keychainGroupId: 0)
                }
                return ans
            }
        }
        set {
            containerInfo = newValue.map { container in
                return container.toDict()
            }
        }
    }

}
