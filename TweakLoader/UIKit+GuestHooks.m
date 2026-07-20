@import UIKit;
@import WebKit;
@import Metal;
@import AVFoundation;
@import Network;
@import CFNetwork;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 260100
@import Accessibility;
#endif
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "Localization.h"
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <ifaddrs.h>
#include <unistd.h>
#include <dns_sd.h>
#include <errno.h>
#include <math.h>
#include <mach/machine.h>

UIInterfaceOrientation LCOrientationLock = UIInterfaceOrientationUnknown;
NSMutableArray<NSString*>* LCSupportedUrlSchemes = nil;
NSUUID* idForVendorUUID = nil;
BOOL spoofProfileEnabled = NO;
BOOL spoofIdentityCategoryEnabled = YES;
BOOL spoofSystemCategoryEnabled = YES;
BOOL spoofDisplayCategoryEnabled = YES;
BOOL spoofLocaleCategoryEnabled = YES;
BOOL spoofBatteryCategoryEnabled = YES;
BOOL spoofTelephonyCategoryEnabled = YES;
BOOL spoofNetworkHeadersCategoryEnabled = YES;
BOOL spoofAccessibilityCategoryEnabled = YES;
BOOL spoofStorageCategoryEnabled = YES;
BOOL spoofNetworkEnvironmentCategoryEnabled = YES;
BOOL spoofAudioCategoryEnabled = YES;
BOOL spoofGraphicsCategoryEnabled = YES;
BOOL spoofWebViewCategoryEnabled = YES;
BOOL spoofAppPrivacyCategoryEnabled = YES;
BOOL spoofSensorsAndUserDataCategoryEnabled = YES;
NSArray<NSNumber *> *rotateOSMajorVersions = nil;
BOOL rotateUsesRealDeviceTemplates = YES;
BOOL blockDeviceInfoReads = NO;
BOOL strictTestMode = NO;
UIPasteboard *strictPrivatePasteboard = nil;
NSString *spoofDeviceName = nil;
NSString *spoofDeviceModel = nil;
NSString *spoofSystemName = nil;
NSString *spoofSystemVersion = nil;
NSLocale *spoofLocale = nil;
NSTimeZone *spoofTimeZone = nil;
NSOperatingSystemVersion spoofOperatingSystemVersion;
BOOL spoofOperatingSystemVersionValid = NO;
float spoofBatteryLevel = -1.0f;
NSInteger spoofBatteryState = UIDeviceBatteryStateUnknown;
BOOL spoofLowPowerModeEnabled = NO;
BOOL spoofLowPowerModeEnabledSet = NO;
NSString *spoofRadioAccessTechnology = nil;
NSString *spoofSubscriberIdentifier = nil;
NSData *spoofSubscriberCarrierToken = nil;
BOOL spoofSubscriberSIMInsertedEnabled = NO;
BOOL spoofSubscriberSIMInserted = NO;
NSString *spoofHardwareModel = nil;
NSString *spoofHostName = nil;
NSString *spoofBoardModel = nil;
NSString *spoofKernelVersion = nil;
time_t spoofBootTime = 0;
int32_t spoofCPUType = 0;
int32_t spoofCPUSubtype = -1;
NSInteger spoofProcessorCount = 0;
unsigned long long spoofPhysicalMemory = 0;
NSInteger spoofThermalState = -1;
CGFloat spoofScreenWidth = 0;
CGFloat spoofScreenHeight = 0;
CGFloat spoofScreenScale = 0;
CGFloat spoofScreenNativeScale = 0;
NSInteger spoofMaximumFramesPerSecond = 0;
CGFloat spoofScreenBrightness = -1;
NSInteger spoofUserInterfaceStyle = UIUserInterfaceStyleLight;
NSInteger spoofAccessibilityContrast = UIAccessibilityContrastNormal;
NSInteger spoofDisplayGamut = UIDisplayGamutP3;
NSInteger spoofHorizontalSizeClass = UIUserInterfaceSizeClassCompact;
NSInteger spoofVerticalSizeClass = UIUserInterfaceSizeClassRegular;
UIContentSizeCategory spoofPreferredContentSizeCategory = nil;
UIEdgeInsets spoofSafeAreaInsets = {59, 0, 34, 0};
long long spoofStorageTotalCapacity = 128LL * 1024LL * 1024LL * 1024LL;
long long spoofStorageAvailableCapacity = 64LL * 1024LL * 1024LL * 1024LL;
NSString *spoofGPUName = @"Apple GPU";
float spoofAudioOutputVolume = 0.5f;

@interface LCTelephonyNetworkInfoHookProvider : NSObject
@end

@interface LCSubscriberHookProvider : NSObject
@end

@interface LCSubscriberInfoHookProvider : NSObject
@end

@interface LCNetworkExtensionStrictHookProvider : NSObject
@end

static void LCSwizzleIfPresent(Class cls, SEL originalAction, SEL swizzledAction) {
    if(!cls) {
        return;
    }
    Method originalMethod = class_getInstanceMethod(cls, originalAction);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledAction);
    if(originalMethod && swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static void LCSwizzleIfPresentWithSourceClass(Class cls, Class sourceCls, SEL originalAction, SEL swizzledAction) {
    if(!cls || !sourceCls) {
        return;
    }
    Method originalMethod = class_getInstanceMethod(cls, originalAction);
    Method sourceMethod = class_getInstanceMethod(sourceCls, swizzledAction);
    if(!originalMethod || !sourceMethod) {
        return;
    }
    class_addMethod(
        cls,
        swizzledAction,
        method_getImplementation(sourceMethod),
        method_getTypeEncoding(sourceMethod)
    );
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledAction);
    if(swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static void LCSwizzleClassIfPresent(Class cls, SEL originalAction, SEL swizzledAction) {
    if(!cls) {
        return;
    }
    Method originalMethod = class_getClassMethod(cls, originalAction);
    Method swizzledMethod = class_getClassMethod(cls, swizzledAction);
    if(originalMethod && swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static void LCSwizzleClassIfPresentWithSourceClass(Class cls, Class sourceCls, SEL originalAction, SEL swizzledAction) {
    if(!cls || !sourceCls) {
        return;
    }
    Method originalMethod = class_getClassMethod(cls, originalAction);
    Method sourceMethod = class_getClassMethod(sourceCls, swizzledAction);
    if(!originalMethod || !sourceMethod) {
        return;
    }
    Class metaClass = object_getClass((id)cls);
    class_addMethod(
        metaClass,
        swizzledAction,
        method_getImplementation(sourceMethod),
        method_getTypeEncoding(sourceMethod)
    );
    Method swizzledMethod = class_getClassMethod(cls, swizzledAction);
    if(swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static BOOL LCNeutralAccessibilityFlag(id self, SEL _cmd) {
    return NO;
}

static id LCEmptyArrayGetter(id self, SEL _cmd) { return @[]; }
static NSString *LCNeutralStringGetter(id self, SEL _cmd) { return spoofGPUName ?: @"Apple GPU"; }
static BOOL LCTrueGetter(id self, SEL _cmd) { return YES; }
static BOOL LCTrueIntegerArgumentGetter(id self, SEL _cmd, NSInteger value) { return YES; }
static NSInteger LCDeniedAuthorizationGetter(id self, SEL _cmd) { return 2; }
static NSInteger LCDeniedAuthorizationArgumentGetter(id self, SEL _cmd, NSInteger value) { return 2; }
static double LCNeutralDoubleGetter(id self, SEL _cmd) { return 0.01; }
static float LCNeutralFloatGetter(id self, SEL _cmd) { return spoofAudioOutputVolume; }
static NSInteger LCNeutralChannelCountGetter(id self, SEL _cmd) { return 2; }
static unsigned long long LCNeutralWorkingSetGetter(id self, SEL _cmd) {
    return spoofPhysicalMemory > 0 ? spoofPhysicalMemory / 2 : 4ULL * 1024ULL * 1024ULL * 1024ULL;
}

static void LCReplaceInstanceMethod(Class cls, NSString *selectorName, IMP implementation) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
    if(method) method_setImplementation(method, implementation);
}

static void LCReplaceClassMethod(Class cls, NSString *selectorName, IMP implementation) {
    Method method = class_getClassMethod(cls, NSSelectorFromString(selectorName));
    if(method) method_setImplementation(method, implementation);
}

static void LCInstallNeutralAccessibilityProfile(void) {
    Class cls = NSClassFromString(@"UIAccessibility");
    NSArray<NSString *> *selectors = @[
        @"isVoiceOverRunning", @"isSwitchControlRunning", @"isGuidedAccessEnabled",
        @"isGrayscaleEnabled", @"isInvertColorsEnabled", @"isReduceMotionEnabled",
        @"isAssistiveTouchRunning", @"isShakeToUndoEnabled", @"isBoldTextEnabled",
        @"isDarkerSystemColorsEnabled", @"isReduceTransparencyEnabled", @"isMonoAudioEnabled",
        @"isSpeakScreenEnabled", @"isSpeakSelectionEnabled", @"isClosedCaptioningEnabled",
        @"isVideoAutoplayEnabled", @"shouldDifferentiateWithoutColor",
        @"isOnOffSwitchLabelsEnabled"
    ];
    for(NSString *selectorName in selectors) {
        Method method = class_getClassMethod(cls, NSSelectorFromString(selectorName));
        if(method) method_setImplementation(method, (IMP)LCNeutralAccessibilityFlag);
    }
}

static void LCInstallLocalePrivacyProfile(void) {
    LCReplaceClassMethod(UITextInputMode.class, @"activeInputModes", (IMP)LCEmptyArrayGetter);
}

static void LCInstallAudioPrivacyProfile(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    Class sessionClass = object_getClass(session) ? [session class] : AVAudioSession.class;
    LCReplaceInstanceMethod(sessionClass, @"availableInputs", (IMP)LCEmptyArrayGetter);
    LCReplaceInstanceMethod(sessionClass, @"sampleRate", (IMP)LCNeutralDoubleGetter);
    LCReplaceInstanceMethod(sessionClass, @"outputLatency", (IMP)LCNeutralDoubleGetter);
    LCReplaceInstanceMethod(sessionClass, @"inputLatency", (IMP)LCNeutralDoubleGetter);
    LCReplaceInstanceMethod(sessionClass, @"isOtherAudioPlaying", (IMP)LCNeutralAccessibilityFlag);
    LCReplaceInstanceMethod(sessionClass, @"outputVolume", (IMP)LCNeutralFloatGetter);
    LCReplaceInstanceMethod(sessionClass, @"outputNumberOfChannels", (IMP)LCNeutralChannelCountGetter);
    LCReplaceInstanceMethod(sessionClass, @"inputNumberOfChannels", (IMP)LCNeutralChannelCountGetter);
    id route = session.currentRoute;
    if(route) {
        LCReplaceInstanceMethod([route class], @"outputs", (IMP)LCEmptyArrayGetter);
        LCReplaceInstanceMethod([route class], @"inputs", (IMP)LCEmptyArrayGetter);
    }
}

static void LCInstallGraphicsPrivacyProfile(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if(!device) return;
    Class cls = [device class];
    LCReplaceInstanceMethod(cls, @"name", (IMP)LCNeutralStringGetter);
    LCReplaceInstanceMethod(cls, @"recommendedMaxWorkingSetSize", (IMP)LCNeutralWorkingSetGetter);
    LCReplaceInstanceMethod(cls, @"supportsRaytracing", (IMP)LCTrueGetter);
    LCReplaceInstanceMethod(cls, @"supportsFamily:", (IMP)LCTrueIntegerArgumentGetter);
}

static void LCInstallAppEnumerationPrivacyProfile(void) {
    LCReplaceClassMethod(UIFont.class, @"familyNames", (IMP)LCEmptyArrayGetter);
    LCReplaceClassMethod(AVSpeechSynthesisVoice.class, @"speechVoices", (IMP)LCEmptyArrayGetter);
}

static void LCInstallSensorsAndUserDataPrivacyProfile(void) {
    Class motionManager = NSClassFromString(@"CMMotionManager");
    for(NSString *selector in @[@"isAccelerometerAvailable", @"isGyroAvailable", @"isMagnetometerAvailable", @"isDeviceMotionAvailable"]) {
        LCReplaceInstanceMethod(motionManager, selector, (IMP)LCNeutralAccessibilityFlag);
    }
    Class pedometer = NSClassFromString(@"CMPedometer");
    for(NSString *selector in @[@"isStepCountingAvailable", @"isDistanceAvailable", @"isFloorCountingAvailable", @"isPaceAvailable", @"isCadenceAvailable", @"isPedometerEventTrackingAvailable"]) {
        LCReplaceClassMethod(pedometer, selector, (IMP)LCNeutralAccessibilityFlag);
    }
    Class altimeter = NSClassFromString(@"CMAltimeter");
    LCReplaceClassMethod(altimeter, @"isRelativeAltitudeAvailable", (IMP)LCNeutralAccessibilityFlag);
    LCReplaceClassMethod(altimeter, @"isAbsoluteAltitudeAvailable", (IMP)LCNeutralAccessibilityFlag);

    Class location = NSClassFromString(@"CLLocationManager");
    LCReplaceInstanceMethod(location, @"authorizationStatus", (IMP)LCDeniedAuthorizationGetter);
    LCReplaceClassMethod(NSClassFromString(@"AVCaptureDevice"), @"authorizationStatusForMediaType:", (IMP)LCDeniedAuthorizationArgumentGetter);
    LCReplaceClassMethod(NSClassFromString(@"PHPhotoLibrary"), @"authorizationStatusForAccessLevel:", (IMP)LCDeniedAuthorizationArgumentGetter);
    LCReplaceClassMethod(NSClassFromString(@"CNContactStore"), @"authorizationStatusForEntityType:", (IMP)LCDeniedAuthorizationArgumentGetter);
    LCReplaceClassMethod(NSClassFromString(@"EKEventStore"), @"authorizationStatusForEntityType:", (IMP)LCDeniedAuthorizationArgumentGetter);
    LCReplaceClassMethod(NSClassFromString(@"MPMediaLibrary"), @"authorizationStatus", (IMP)LCDeniedAuthorizationGetter);
    LCReplaceClassMethod(NSClassFromString(@"CBCentralManager"), @"authorization", (IMP)LCDeniedAuthorizationGetter);
}

static NSString *LCJSONString(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return array.length >= 2 ? [array substringWithRange:NSMakeRange(1, array.length - 2)] : @"\"\"";
}

static NSString *LCWebViewProfileScript(void) {
    NSString *platform = [spoofDeviceModel.lowercaseString containsString:@"ipad"] ? @"iPad" :
        (spoofDeviceModel.length > 0 ? spoofDeviceModel : @"iPhone");
    NSString *version = spoofSystemVersion.length > 0 ? [spoofSystemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"] : @"26_0";
    NSString *language = spoofLocale.localeIdentifier.length > 0
        ? [spoofLocale.localeIdentifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"] : @"en-US";
    NSString *ua = [NSString stringWithFormat:@"Mozilla/5.0 (%@; CPU %@ OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        platform, [platform isEqualToString:@"iPad"] ? @"iPad" : @"iPhone", version];
    NSInteger cores = spoofProcessorCount > 0 ? spoofProcessorCount : 6;
    unsigned long long memoryGB = spoofPhysicalMemory > 0 ? MAX(2, spoofPhysicalMemory / (1024ULL * 1024ULL * 1024ULL)) : 8;
    CGFloat pointsWidth = spoofScreenScale > 0 ? spoofScreenWidth / spoofScreenScale : spoofScreenWidth;
    CGFloat pointsHeight = spoofScreenScale > 0 ? spoofScreenHeight / spoofScreenScale : spoofScreenHeight;
    NSInteger timezoneOffset = spoofTimeZone ? -[spoofTimeZone secondsFromGMT] / 60 : 0;
    return [NSString stringWithFormat:
        @"(()=>{const d=(o,k,v)=>{try{Object.defineProperty(o,k,{get:()=>v,configurable:true})}catch(e){}};"
         "d(Navigator.prototype,'userAgent',%@);d(Navigator.prototype,'platform',%@);"
         "d(Navigator.prototype,'language',%@);d(Navigator.prototype,'languages',[%@]);"
         "d(Navigator.prototype,'hardwareConcurrency',%ld);d(Navigator.prototype,'deviceMemory',%llu);"
         "d(Screen.prototype,'width',%.0f);d(Screen.prototype,'height',%.0f);d(Screen.prototype,'colorDepth',24);d(Screen.prototype,'pixelDepth',24);"
         "d(window,'devicePixelRatio',%.3f);Date.prototype.getTimezoneOffset=function(){return %ld};"
         "const ir=Intl.DateTimeFormat.prototype.resolvedOptions;Intl.DateTimeFormat.prototype.resolvedOptions=function(){const r=ir.call(this);r.timeZone=%@;return r};"
         "const gp=typeof WebGLRenderingContext!=='undefined'&&WebGLRenderingContext.prototype.getParameter;if(gp)WebGLRenderingContext.prototype.getParameter=function(p){if(p===37445)return 'Apple Inc.';if(p===37446)return 'Apple GPU';return gp.call(this,p)};"
         "const td=typeof HTMLCanvasElement!=='undefined'&&HTMLCanvasElement.prototype.toDataURL;if(td)HTMLCanvasElement.prototype.toDataURL=function(){return 'data:image/png;base64,iVBORw0KGgo='};"
         "})();",
        LCJSONString(ua), LCJSONString(platform), LCJSONString(language), LCJSONString(language),
        (long)cores, memoryGB, pointsWidth > 0 ? pointsWidth : 393, pointsHeight > 0 ? pointsHeight : 852,
        spoofScreenScale > 0 ? spoofScreenScale : 3, (long)timezoneOffset,
        LCJSONString(spoofTimeZone.name ?: @"Etc/UTC")];
}

static BOOL LCParseVersionPart(NSString *part, NSInteger *outValue) {
    if(![part isKindOfClass:NSString.class] || part.length == 0) {
        return NO;
    }
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if([part rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NO;
    }
    long long parsedValue = part.longLongValue;
    if(parsedValue < 0 || parsedValue > NSIntegerMax) {
        return NO;
    }
    *outValue = (NSInteger)parsedValue;
    return YES;
}

static BOOL LCBoolWithDefault(NSDictionary *dictionary, NSString *key, BOOL defaultValue) {
    id value = dictionary[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultValue;
}

static BOOL LCParseSystemVersion(NSString *versionString, NSOperatingSystemVersion *outVersion) {
    if(![versionString isKindOfClass:NSString.class]) {
        return NO;
    }
    NSArray<NSString*> *parts = [versionString componentsSeparatedByString:@"."];
    if(parts.count == 0 || parts.count > 3) {
        return NO;
    }

    NSInteger major = 0;
    NSInteger minor = 0;
    NSInteger patch = 0;
    if(!LCParseVersionPart(parts[0], &major)) {
        return NO;
    }
    if(parts.count > 1 && !LCParseVersionPart(parts[1], &minor)) {
        return NO;
    }
    if(parts.count > 2 && !LCParseVersionPart(parts[2], &patch)) {
        return NO;
    }
    outVersion->majorVersion = major;
    outVersion->minorVersion = minor;
    outVersion->patchVersion = patch;
    return YES;
}

static NSInteger LCCompareOSVersion(NSOperatingSystemVersion lhs, NSOperatingSystemVersion rhs) {
    if(lhs.majorVersion != rhs.majorVersion) {
        return lhs.majorVersion < rhs.majorVersion ? -1 : 1;
    }
    if(lhs.minorVersion != rhs.minorVersion) {
        return lhs.minorVersion < rhs.minorVersion ? -1 : 1;
    }
    if(lhs.patchVersion != rhs.patchVersion) {
        return lhs.patchVersion < rhs.patchVersion ? -1 : 1;
    }
    return 0;
}

static NSTimeZone *LCBlockedTimeZone(void) {
    return [NSTimeZone timeZoneWithAbbreviation:@"GMT"] ?: [NSTimeZone systemTimeZone];
}

static NSLocale *LCBlockedLocale(void) {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"und"];
}

static NSCalendar *LCCalendarForProfile(NSTimeZone *timeZone) {
    NSCalendar *calendar = nil;
    if(!blockDeviceInfoReads && spoofLocaleCategoryEnabled && spoofLocale) {
        id localeCalendar = [spoofLocale objectForKey:NSLocaleCalendar];
        if([localeCalendar isKindOfClass:NSCalendar.class]) {
            calendar = [localeCalendar copy];
        }
    }
    if(!calendar) {
        calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    }
    if(timeZone) {
        calendar.timeZone = timeZone;
    }
    return calendar;
}

static UIWindowScene *LCForegroundWindowScene(void) {
    UIWindowScene *fallbackScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene;
        }
        if (!fallbackScene) {
            fallbackScene = windowScene;
        }
    }
    return fallbackScene;
}

static UIWindow *LCKeyWindowForScene(UIWindowScene *scene) {
    if (!scene) {
        return nil;
    }
    UIWindow *keyWindow = scene.keyWindow;
    if (keyWindow) {
        return keyWindow;
    }
    for (UIWindow *window in scene.windows) {
        if (window.isKeyWindow) {
            return window;
        }
    }
    return scene.windows.firstObject;
}

static UIWindowLevel LCOverlayWindowLevel(void) {
    UIWindow *keyWindow = LCKeyWindowForScene(LCForegroundWindowScene());
    return (keyWindow ? keyWindow.windowLevel : UIWindowLevelNormal) + 1;
}

static CGRect LCActiveScreenBounds(void) {
    UIWindow *keyWindow = LCKeyWindowForScene(LCForegroundWindowScene());
    if(keyWindow) return keyWindow.bounds;
    UIWindowScene *scene = LCForegroundWindowScene();
    return scene ? scene.screen.bounds : CGRectZero;
}

// MARK: - System & Display Profile: kernel identity
// Intercept low-level C APIs that analytics SDKs use to read the real hardware
// identifier (e.g. "iPhoneXX,X"). UIDevice.model only returns "iPhone" so apps
// bypass it entirely via these C calls.

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    NSString *spoofedValue = nil;
    if(name && !newp) {
        if((blockDeviceInfoReads || spoofIdentityCategoryEnabled) && strcmp(name, "hw.machine") == 0) {
            spoofedValue = spoofHardwareModel;
        } else if((blockDeviceInfoReads || spoofIdentityCategoryEnabled) && strcmp(name, "hw.model") == 0) {
            spoofedValue = spoofBoardModel ?: spoofHardwareModel;
        } else if((blockDeviceInfoReads || spoofIdentityCategoryEnabled) && strcmp(name, "kern.hostname") == 0) {
            spoofedValue = spoofHostName;
        } else if((blockDeviceInfoReads || spoofSystemCategoryEnabled) && strcmp(name, "kern.version") == 0) {
            spoofedValue = spoofKernelVersion;
        }
    }
    if(spoofedValue.length > 0 && oldlenp) {
        const char *spoofed = spoofedValue.UTF8String;
        size_t requiredLength = strlen(spoofed) + 1;
        if(!oldp) {
            *oldlenp = requiredLength;
            return 0;
        }
        if(*oldlenp < requiredLength) {
            *oldlenp = requiredLength;
            errno = ENOMEM;
            return -1;
        }
        memcpy(oldp, spoofed, requiredLength);
        *oldlenp = requiredLength;
        return 0;
    }
    const void *numericValue = nil;
    size_t numericLength = 0;
    int32_t cpuType = blockDeviceInfoReads ? CPU_TYPE_ARM64 : (spoofSystemCategoryEnabled ? spoofCPUType : 0);
    int32_t cpuSubtype = blockDeviceInfoReads ? 0 : (spoofSystemCategoryEnabled ? spoofCPUSubtype : -1);
    struct timeval bootTime = { .tv_sec = blockDeviceInfoReads ? 0 : (spoofSystemCategoryEnabled ? spoofBootTime : 0), .tv_usec = 0 };
    if(name && !newp) {
        if(strcmp(name, "hw.cputype") == 0 && cpuType > 0) {
            numericValue = &cpuType;
            numericLength = sizeof(cpuType);
        } else if(strcmp(name, "hw.cpusubtype") == 0 && cpuSubtype >= 0) {
            numericValue = &cpuSubtype;
            numericLength = sizeof(cpuSubtype);
        } else if(strcmp(name, "kern.boottime") == 0 && (blockDeviceInfoReads || spoofBootTime > 0)) {
            numericValue = &bootTime;
            numericLength = sizeof(bootTime);
        }
    }
    if(numericValue && oldlenp) {
        if(!oldp) {
            *oldlenp = numericLength;
            return 0;
        }
        if(*oldlenp < numericLength) {
            *oldlenp = numericLength;
            errno = ENOMEM;
            return -1;
        }
        memcpy(oldp, numericValue, numericLength);
        *oldlenp = numericLength;
        return 0;
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int hook_uname(struct utsname *uts) {
    int ret = uname(uts);
    if(ret == 0 && (blockDeviceInfoReads || spoofIdentityCategoryEnabled) && spoofHardwareModel) {
        strlcpy(uts->machine, spoofHardwareModel.UTF8String, sizeof(uts->machine));
    }
    if(ret == 0 && (blockDeviceInfoReads || spoofIdentityCategoryEnabled) && spoofHostName) {
        strlcpy(uts->nodename, spoofHostName.UTF8String, sizeof(uts->nodename));
    }
    if(ret == 0 && (blockDeviceInfoReads || spoofSystemCategoryEnabled) && spoofKernelVersion) {
        strlcpy(uts->version, spoofKernelVersion.UTF8String, sizeof(uts->version));
    }
    return ret;
}

static int hook_gethostname(char *name, size_t namelen) {
    if((blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) && namelen > 0) {
        NSString *value = spoofHostName.length > 0 ? spoofHostName : @"localhost";
        strlcpy(name, value.UTF8String, namelen);
        return 0;
    }
    return gethostname(name, namelen);
}

static int hook_getifaddrs(struct ifaddrs **ifap) {
    if(blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) {
        if(ifap) *ifap = NULL;
        return 0;
    }
    return getifaddrs(ifap);
}

#define LC_ACCESSIBILITY_HOOK(_name) \
    static BOOL hook_##_name(void) { \
        if(blockDeviceInfoReads || (spoofProfileEnabled && spoofAccessibilityCategoryEnabled)) return NO; \
        return _name(); \
    }

LC_ACCESSIBILITY_HOOK(UIAccessibilityIsVoiceOverRunning)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsMonoAudioEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsClosedCaptioningEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsInvertColorsEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsGuidedAccessEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsBoldTextEnabled)
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 260100
LC_ACCESSIBILITY_HOOK(AXShowBordersEnabled)
#endif
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsGrayscaleEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsReduceTransparencyEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsReduceMotionEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsVideoAutoplayEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityDarkerSystemColorsEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsSwitchControlRunning)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsSpeakSelectionEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsSpeakScreenEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsShakeToUndoEnabled)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsAssistiveTouchRunning)
LC_ACCESSIBILITY_HOOK(UIAccessibilityShouldDifferentiateWithoutColor)
LC_ACCESSIBILITY_HOOK(UIAccessibilityIsOnOffSwitchLabelsEnabled)

static void hook_nw_path_monitor_start(nw_path_monitor_t monitor) {
    if(blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) return;
    nw_path_monitor_start(monitor);
}

static void hook_nw_browser_start(nw_browser_t browser) {
    if(blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) return;
    nw_browser_start(browser);
}

static DNSServiceErrorType hook_DNSServiceBrowse(
    DNSServiceRef *sdRef,
    DNSServiceFlags flags,
    uint32_t interfaceIndex,
    const char *regtype,
    const char *domain,
    DNSServiceBrowseReply callback,
    void *context
) {
    if(blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) {
        if(sdRef) *sdRef = NULL;
        return kDNSServiceErr_PolicyDenied;
    }
    return DNSServiceBrowse(sdRef, flags, interfaceIndex, regtype, domain, callback, context);
}

static CFDictionaryRef hook_CFNetworkCopySystemProxySettings(void) {
    if(blockDeviceInfoReads || (spoofProfileEnabled && spoofNetworkEnvironmentCategoryEnabled)) {
        return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    return CFNetworkCopySystemProxySettings();
}

// DYLD_INTERPOSE lets us hook C functions from a loaded dylib without needing litehook or fishhook.
// The linker replaces calls to the original function with our hook at load time.
#define DYLD_INTERPOSE(_hook, _orig) \
    __attribute__((used)) static struct { const void *hook; const void *orig; } \
    _interpose_##_orig __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)&_hook, (const void *)&_orig }

// These interpose entries are conditionally effective — the hook functions
// check spoofHardwareModel at runtime and pass through if NULL.
DYLD_INTERPOSE(hook_sysctlbyname, sysctlbyname);
DYLD_INTERPOSE(hook_uname, uname);
DYLD_INTERPOSE(hook_gethostname, gethostname);
DYLD_INTERPOSE(hook_getifaddrs, getifaddrs);
DYLD_INTERPOSE(hook_nw_path_monitor_start, nw_path_monitor_start);
DYLD_INTERPOSE(hook_nw_browser_start, nw_browser_start);
DYLD_INTERPOSE(hook_DNSServiceBrowse, DNSServiceBrowse);
DYLD_INTERPOSE(hook_CFNetworkCopySystemProxySettings, CFNetworkCopySystemProxySettings);
DYLD_INTERPOSE(hook_UIAccessibilityIsVoiceOverRunning, UIAccessibilityIsVoiceOverRunning);
DYLD_INTERPOSE(hook_UIAccessibilityIsMonoAudioEnabled, UIAccessibilityIsMonoAudioEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsClosedCaptioningEnabled, UIAccessibilityIsClosedCaptioningEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsInvertColorsEnabled, UIAccessibilityIsInvertColorsEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsGuidedAccessEnabled, UIAccessibilityIsGuidedAccessEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsBoldTextEnabled, UIAccessibilityIsBoldTextEnabled);
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 260100
DYLD_INTERPOSE(hook_AXShowBordersEnabled, AXShowBordersEnabled);
#endif
DYLD_INTERPOSE(hook_UIAccessibilityIsGrayscaleEnabled, UIAccessibilityIsGrayscaleEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsReduceTransparencyEnabled, UIAccessibilityIsReduceTransparencyEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsReduceMotionEnabled, UIAccessibilityIsReduceMotionEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsVideoAutoplayEnabled, UIAccessibilityIsVideoAutoplayEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityDarkerSystemColorsEnabled, UIAccessibilityDarkerSystemColorsEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsSwitchControlRunning, UIAccessibilityIsSwitchControlRunning);
DYLD_INTERPOSE(hook_UIAccessibilityIsSpeakSelectionEnabled, UIAccessibilityIsSpeakSelectionEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsSpeakScreenEnabled, UIAccessibilityIsSpeakScreenEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsShakeToUndoEnabled, UIAccessibilityIsShakeToUndoEnabled);
DYLD_INTERPOSE(hook_UIAccessibilityIsAssistiveTouchRunning, UIAccessibilityIsAssistiveTouchRunning);
DYLD_INTERPOSE(hook_UIAccessibilityShouldDifferentiateWithoutColor, UIAccessibilityShouldDifferentiateWithoutColor);
DYLD_INTERPOSE(hook_UIAccessibilityIsOnOffSwitchLabelsEnabled, UIAccessibilityIsOnOffSwitchLabelsEnabled);

// MARK: - HTTP Header Device Identity Rewriting
// Intercepts ALL outgoing HTTP headers to rewrite User-Agent strings containing
// real device info. This covers native iOS (NSURLSession), Flutter (Dart HTTP),
// React Native (fetch/axios), Expo, and all analytics SDKs (Firebase, PostHog,
// Adjust, AppsFlyer, etc.) since they ALL go through NSMutableURLRequest.

// Helper: Rewrite a User-Agent string, replacing real hw.machine and iOS version
// with spoofed values. Handles all known User-Agent formats:
//
// Format 1 (Custom app UAs):
//   ExampleApp/10.0 iOS/18.2 (Apple;iPhoneXX,X;;;;;1;2024)
//
// Format 2 (WebKit/Safari/WKWebView):
//   Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15
//
// Format 3 (NSURLSession default / CFNetwork):
//   AppName/1.0 CFNetwork/1568.200.51 Darwin/24.1.0
//
// Format 4 (Dart/Flutter):
//   Dart/3.5 (dart:io) MyApp/1.0 (iOS 18.0; iPhoneXX,X)
//
// Also catches any raw occurrence of the hw.machine identifier
// embedded anywhere in the string.

static NSRegularExpression *_uaHwMachineRegex = nil;
static NSRegularExpression *_uaIOSVersionSlashRegex = nil;
static NSRegularExpression *_uaIOSVersionCPURegex = nil;
static NSRegularExpression *_uaIOSVersionParenRegex = nil;

static void LCInitUserAgentRegexes(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Match hw.machine identifiers: iPhoneXX,X  iPadXX,X  etc.
        // This is the most important one — catches ALL formats
        _uaHwMachineRegex = [NSRegularExpression
            regularExpressionWithPattern:@"(iPhone|iPad|iPod)\\d+,\\d+"
            options:0 error:nil];

        // Match "iOS/XX.X" or "iOS/XX.X.X" (common custom UA format)
        _uaIOSVersionSlashRegex = [NSRegularExpression
            regularExpressionWithPattern:@"iOS/[\\d.]+"
            options:0 error:nil];

        // Match "CPU iPhone OS 18_0 like Mac OS X" (WebKit/Safari UA)
        _uaIOSVersionCPURegex = [NSRegularExpression
            regularExpressionWithPattern:@"CPU iPhone OS [\\d_]+ like Mac OS X"
            options:0 error:nil];

        // Match "(iOS 18.0;" or "iOS 18.0)" (Dart/Flutter, generic)
        _uaIOSVersionParenRegex = [NSRegularExpression
            regularExpressionWithPattern:@"iOS [\\d.]+"
            options:0 error:nil];
    });
}

static NSString* LCRewriteUserAgent(NSString *ua) {
    if(!ua || ua.length == 0) return ua;

    NSMutableString *result = [ua mutableCopy];
    NSRange fullRange = NSMakeRange(0, result.length);

    // 1. Replace all hw.machine identifiers (iPhoneXX,X → spoofed)
    // This is the primary catch-all — works for ANY format
    if(spoofHardwareModel) {
        [_uaHwMachineRegex replaceMatchesInString:result
            options:0 range:fullRange
            withTemplate:spoofHardwareModel];
        fullRange = NSMakeRange(0, result.length);
    }

    // 2. Replace iOS version in various formats
    if(spoofSystemVersion) {
        // "iOS/XX.X" → "iOS/{spoofed}" (custom app UAs, analytics SDKs, etc.)
        [_uaIOSVersionSlashRegex replaceMatchesInString:result
            options:0 range:fullRange
            withTemplate:[NSString stringWithFormat:@"iOS/%@", spoofSystemVersion]];
        fullRange = NSMakeRange(0, result.length);

        // "CPU iPhone OS 18_0 like Mac OS X" → spoofed (WebKit)
        NSString *underscoreVersion = [spoofSystemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        NSString *cpuReplacement = [NSString stringWithFormat:@"CPU iPhone OS %@ like Mac OS X", underscoreVersion];
        [_uaIOSVersionCPURegex replaceMatchesInString:result
            options:0 range:fullRange
            withTemplate:cpuReplacement];
        fullRange = NSMakeRange(0, result.length);

        // "iOS 18.0" → "iOS {spoofed}" (Dart/Flutter, generic)
        [_uaIOSVersionParenRegex replaceMatchesInString:result
            options:0 range:fullRange
            withTemplate:[NSString stringWithFormat:@"iOS %@", spoofSystemVersion]];
    }

    return result;
}

// Helper: check if a header name is User-Agent (case-insensitive per HTTP spec)
static BOOL LCIsUserAgentHeader(NSString *field) {
    return [field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame;
}

// Helper: rewrite a User-Agent value in a dictionary (for HTTPAdditionalHeaders)
static NSDictionary* LCRewriteHeaderDict(NSDictionary *headers) {
    if(!headers) return headers;
    NSMutableDictionary *result = nil;
    for(NSString *key in headers) {
        if(LCIsUserAgentHeader(key)) {
            NSString *val = headers[key];
            if([val isKindOfClass:NSString.class]) {
                NSString *rewritten = LCRewriteUserAgent(val);
                if(![rewritten isEqualToString:val]) {
                    if(!result) result = [headers mutableCopy];
                    result[key] = rewritten;
                }
            }
        }
    }
    return result ?: headers;
}

// --- NSMutableURLRequest hooks ---
// These intercept User-Agent being set on ANY outgoing HTTP request.
// Covers: NSURLSession (native iOS, React Native, Expo),
//         CFNetwork (Flutter dart:io), Firebase, PostHog, Adjust, AppsFlyer, etc.

@interface NSMutableURLRequest(LCDeviceSpoof)
@end

@implementation NSMutableURLRequest(LCDeviceSpoof)

- (void)hook_setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if(value && LCIsUserAgentHeader(field)) {
        value = LCRewriteUserAgent(value);
    }
    [self hook_setValue:value forHTTPHeaderField:field];
}

- (void)hook_addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if(value && LCIsUserAgentHeader(field)) {
        value = LCRewriteUserAgent(value);
    }
    [self hook_addValue:value forHTTPHeaderField:field];
}

- (void)hook_setAllHTTPHeaderFields:(NSDictionary *)headerFields {
    [self hook_setAllHTTPHeaderFields:LCRewriteHeaderDict(headerFields)];
}

@end

// --- NSURLSessionConfiguration hooks ---
// Catches apps that set User-Agent at the session level via HTTPAdditionalHeaders.
// This is the recommended Apple API for setting global headers, used by:
// - React Native (RCTSetCustomNSURLSessionConfigurationProvider)
// - Firebase SDK
// - Alamofire (Swift networking library)
// - Any app following Apple best practices

@interface NSURLSessionConfiguration(LCDeviceSpoof)
@end

@implementation NSURLSessionConfiguration(LCDeviceSpoof)

- (void)hook_setHTTPAdditionalHeaders:(NSDictionary *)headers {
    [self hook_setHTTPAdditionalHeaders:LCRewriteHeaderDict(headers)];
}

@end

// MARK: - Per-launch profile rotation

static id LCRandomArrayValue(NSArray *values) {
    if(values.count == 0) return nil;
    return values[arc4random_uniform((uint32_t)values.count)];
}

static NSArray<NSNumber *> *LCParseRotationOSMajorVersions(id value) {
    if(![value isKindOfClass:NSString.class]) return @[@18, @26, @27];
    NSMutableOrderedSet<NSNumber *> *versions = [NSMutableOrderedSet orderedSet];
    for(NSString *component in [(NSString *)value componentsSeparatedByString:@","]) {
        NSString *trimmed = [component stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger major = 0;
        if(trimmed.length == 0 || ![scanner scanInteger:&major] || !scanner.isAtEnd || major < 1 || major > 99) {
            return @[@18, @26, @27];
        }
        [versions addObject:@(major)];
    }
    return versions.count > 0 ? versions.array : @[@18, @26, @27];
}

static void LCApplyRotatingDeviceTemplateMetrics(void) {
    if(!rotateUsesRealDeviceTemplates || spoofHardwareModel.length == 0) return;
    BOOL isPad = [spoofHardwareModel hasPrefix:@"iPad"];
    BOOL isLarge = [spoofHardwareModel hasSuffix:@",2"] || [spoofHardwareModel hasSuffix:@",4"] || [spoofHardwareModel hasSuffix:@",5"] ||
        [spoofHardwareModel hasSuffix:@",10"];
    BOOL isPro = [spoofHardwareModel hasPrefix:@"iPhone18,1"] || [spoofHardwareModel hasPrefix:@"iPhone18,2"] ||
        [spoofHardwareModel hasPrefix:@"iPhone17,1"] || [spoofHardwareModel hasPrefix:@"iPhone17,2"] ||
        [spoofHardwareModel hasPrefix:@"iPhone16,1"] || [spoofHardwareModel hasPrefix:@"iPhone16,2"];
    if(isPad) {
        spoofScreenWidth = isLarge ? 2064 : 1668;
        spoofScreenHeight = isLarge ? 2752 : 2420;
        spoofScreenScale = 2;
        spoofScreenNativeScale = 2;
        spoofMaximumFramesPerSecond = [spoofHardwareModel hasPrefix:@"iPad16"] ? 120 : 60;
        spoofProcessorCount = [spoofHardwareModel hasPrefix:@"iPad16"] ? 10 : 8;
        spoofPhysicalMemory = 8ULL * 1024ULL * 1024ULL * 1024ULL;
        spoofHorizontalSizeClass = UIUserInterfaceSizeClassRegular;
        spoofVerticalSizeClass = UIUserInterfaceSizeClassRegular;
        spoofSafeAreaInsets = UIEdgeInsetsMake(24, 0, 20, 0);
    } else {
        spoofScreenWidth = isLarge ? 1290 : (isPro ? 1206 : 1179);
        spoofScreenHeight = isLarge ? 2796 : (isPro ? 2622 : 2556);
        spoofScreenScale = 3;
        spoofScreenNativeScale = 3;
        spoofMaximumFramesPerSecond = isPro ? 120 : 60;
        spoofProcessorCount = 6;
        spoofPhysicalMemory = 8ULL * 1024ULL * 1024ULL * 1024ULL;
        spoofHorizontalSizeClass = UIUserInterfaceSizeClassCompact;
        spoofVerticalSizeClass = UIUserInterfaceSizeClassRegular;
        spoofSafeAreaInsets = UIEdgeInsetsMake(59, 0, 34, 0);
    }
}

static void LCRotateSpoofProfile(void) {
    if(spoofIdentityCategoryEnabled) {
        idForVendorUUID = NSUUID.UUID;
        if(rotateUsesRealDeviceTemplates) {
            BOOL usePad = [spoofDeviceModel.lowercaseString containsString:@"ipad"] ||
                [spoofHardwareModel hasPrefix:@"iPad"];
            NSArray<NSString *> *models = usePad
                ? @[@"iPad16,3", @"iPad16,5", @"iPad14,8", @"iPad14,10"]
                : @[@"iPhone18,1", @"iPhone18,2", @"iPhone18,3", @"iPhone18,4",
                    @"iPhone17,1", @"iPhone17,2", @"iPhone17,3", @"iPhone17,4",
                    @"iPhone16,1", @"iPhone16,2", @"iPhone15,4", @"iPhone15,5"];
            spoofDeviceModel = usePad ? @"iPad" : @"iPhone";
            spoofHardwareModel = LCRandomArrayValue(models);
            LCApplyRotatingDeviceTemplateMetrics();
        }
    }

    if(spoofSystemCategoryEnabled) {
        if(spoofSystemVersion.length > 0) {
            NSInteger major = [LCRandomArrayValue(rotateOSMajorVersions ?: @[@18, @26, @27]) integerValue];
            NSInteger minor = arc4random_uniform(8);
            NSInteger patch = arc4random_uniform(4);
            spoofSystemVersion = patch == 0
                ? [NSString stringWithFormat:@"%ld.%ld", (long)major, (long)minor]
                : [NSString stringWithFormat:@"%ld.%ld.%ld", (long)major, (long)minor, (long)patch];
            spoofOperatingSystemVersionValid = LCParseSystemVersion(spoofSystemVersion, &spoofOperatingSystemVersion);
            if(rotateUsesRealDeviceTemplates && spoofKernelVersion.length > 0) {
                NSInteger darwinMajor = major >= 26 ? major - 1 : major + 6;
                spoofKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %ld.0.0", (long)darwinMajor];
            }
        }
        if(spoofBootTime > 0) spoofBootTime = time(NULL) - (time_t)(3600 + arc4random_uniform(1209600));
        if(spoofProcessorCount > 0) spoofProcessorCount = 2 + arc4random_uniform(11);
        if(spoofPhysicalMemory > 0) spoofPhysicalMemory = (2 + arc4random_uniform(15)) * 1024ULL * 1024ULL * 1024ULL;
    }

    if(spoofDisplayCategoryEnabled) {
        if(!rotateUsesRealDeviceTemplates && spoofScreenWidth > 0 && spoofScreenHeight > 0) {
            CGFloat aspectRatio = spoofScreenHeight / spoofScreenWidth;
            spoofScreenWidth = 900 + arc4random_uniform(1201);
            spoofScreenHeight = round(spoofScreenWidth * aspectRatio);
        }
        if(!rotateUsesRealDeviceTemplates && spoofScreenScale > 0) spoofScreenScale = (CGFloat)(200 + arc4random_uniform(101)) / 100.0;
        if(!rotateUsesRealDeviceTemplates && spoofScreenNativeScale > 0) spoofScreenNativeScale = spoofScreenScale;
        if(!rotateUsesRealDeviceTemplates && spoofMaximumFramesPerSecond > 0) spoofMaximumFramesPerSecond = arc4random_uniform(2) == 0 ? 60 : 120;
        if(spoofScreenBrightness >= 0) spoofScreenBrightness = (CGFloat)arc4random_uniform(101) / 100.0;
        spoofUserInterfaceStyle = arc4random_uniform(2) == 0 ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
        spoofDisplayGamut = arc4random_uniform(4) == 0 ? UIDisplayGamutSRGB : UIDisplayGamutP3;
        NSArray<NSString *> *contentSizes = @[
            UIContentSizeCategoryMedium, UIContentSizeCategoryLarge, UIContentSizeCategoryExtraLarge
        ];
        spoofPreferredContentSizeCategory = LCRandomArrayValue(contentSizes);
    }

    if(spoofAccessibilityCategoryEnabled) {
        spoofAccessibilityContrast = arc4random_uniform(6) == 0 ? UIAccessibilityContrastHigh : UIAccessibilityContrastNormal;
    }

    if(spoofStorageCategoryEnabled && spoofStorageTotalCapacity > 0) {
        long long minimumFree = MIN(spoofStorageTotalCapacity, 8LL * 1024LL * 1024LL * 1024LL);
        long long variableRange = MAX(1LL, spoofStorageTotalCapacity - minimumFree);
        double fraction = (double)arc4random_uniform(10001) / 10000.0;
        spoofStorageAvailableCapacity = minimumFree + (long long)(fraction * (double)variableRange);
    }
    if(spoofAudioCategoryEnabled) spoofAudioOutputVolume = (float)arc4random_uniform(101) / 100.0f;

    if(spoofLocaleCategoryEnabled) {
        if(spoofLocale) {
            NSArray<NSString *> *localeIdentifiers = [NSLocale availableLocaleIdentifiers];
            NSString *localeIdentifier = nil;
            for(NSUInteger attempt = 0; attempt < 32 && localeIdentifier.length == 0; attempt++) {
                NSString *candidate = LCRandomArrayValue(localeIdentifiers);
                NSLocale *candidateLocale = [[NSLocale alloc] initWithLocaleIdentifier:candidate];
                NSString *countryCode = [candidateLocale objectForKey:NSLocaleCountryCode];
                if(countryCode.length > 0) localeIdentifier = candidate;
            }
            if(localeIdentifier.length > 0) spoofLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier];
        }
        NSString *timeZoneName = spoofTimeZone ? LCRandomArrayValue([NSTimeZone knownTimeZoneNames]) : nil;
        if(spoofTimeZone && timeZoneName.length > 0) {
            spoofTimeZone = [NSTimeZone timeZoneWithName:timeZoneName];
            if(spoofTimeZone) [NSTimeZone setDefaultTimeZone:spoofTimeZone];
        }
    }

    if(spoofBatteryCategoryEnabled) {
        spoofBatteryLevel = (float)(15 + arc4random_uniform(86)) / 100.0f;
        spoofBatteryState = 1 + arc4random_uniform(3);
        spoofLowPowerModeEnabled = spoofBatteryLevel < 0.25f;
        spoofLowPowerModeEnabledSet = YES;
        if(spoofThermalState >= 0) spoofThermalState = arc4random_uniform(5) == 0
            ? NSProcessInfoThermalStateFair : NSProcessInfoThermalStateNominal;
    }

    if(spoofTelephonyCategoryEnabled) {
        if(spoofSubscriberIdentifier.length > 0) spoofSubscriberIdentifier = NSUUID.UUID.UUIDString;
        if(spoofSubscriberCarrierToken) {
            uint8_t tokenBytes[24];
            arc4random_buf(tokenBytes, sizeof(tokenBytes));
            spoofSubscriberCarrierToken = [NSData dataWithBytes:tokenBytes length:sizeof(tokenBytes)];
        }
        if(spoofSubscriberSIMInsertedEnabled) spoofSubscriberSIMInserted = arc4random_uniform(2) == 1;
    }
}

BOOL launchURLProcessed = NO;

__attribute__((constructor))
static void UIKitGuestHooksInit() {
    if(!NSUserDefaults.lcGuestAppId) return;
    swizzle(UIApplication.class, @selector(_applicationOpenURLAction:payload:origin:), @selector(hook__applicationOpenURLAction:payload:origin:));
    swizzle(UIApplication.class, @selector(_connectUISceneFromFBSScene:transitionContext:), @selector(hook__connectUISceneFromFBSScene:transitionContext:));
    swizzle(UIApplication.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    swizzle(UIApplication.class, @selector(canOpenURL:), @selector(hook_canOpenURL:));
    swizzle(UIApplication.class, @selector(setDelegate:), @selector(hook_setDelegate:));
    swizzle(UIScene.class, @selector(scene:didReceiveActions:fromTransitionContext:), @selector(hook_scene:didReceiveActions:fromTransitionContext:));
    swizzle(UIScene.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    NSInteger LCOrientationLockDirection = [NSUserDefaults.guestAppInfo[@"LCOrientationLock"] integerValue];
    if(LCOrientationLockDirection != 0 && [UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        switch (LCOrientationLockDirection) {
            case 1:
                LCOrientationLock = UIInterfaceOrientationLandscapeRight;
                break;
            case 2:
                LCOrientationLock = UIInterfaceOrientationPortrait;
                break;
            default:
                break;
        }
        if(!NSUserDefaults.isLiveProcess && LCOrientationLock != UIInterfaceOrientationUnknown) {
//            swizzle(UIApplication.class, @selector(_handleDelegateCallbacksWithOptions:isSuspended:restoreState:), @selector(hook__handleDelegateCallbacksWithOptions:isSuspended:restoreState:));
            swizzle(FBSSceneParameters.class, @selector(initWithXPCDictionary:), @selector(hook_initWithXPCDictionary:));
            swizzle(UIViewController.class, @selector(supportedInterfaceOrientations), @selector(hook_supportedInterfaceOrientations));
            swizzle(UIWindow.class, @selector(setAutorotates:forceUpdateInterfaceOrientation:), @selector(hook_setAutorotates:forceUpdateInterfaceOrientation:));
        }

    }
    NSDictionary* guestContainerInfo = [NSUserDefaults guestContainerInfo];
    strictTestMode = [guestContainerInfo[@"strictTestMode"] boolValue];
    blockDeviceInfoReads = strictTestMode || [guestContainerInfo[@"blockDeviceInfoReads"] boolValue];

    if(strictTestMode) {
        strictPrivatePasteboard = [UIPasteboard pasteboardWithUniqueName];
        LCSwizzleClassIfPresent(UIPasteboard.class, @selector(generalPasteboard), @selector(hook_generalPasteboard));
    }
    if(strictTestMode) {
        LCSwizzleIfPresent(NSURLSessionTask.class, @selector(resume), @selector(hook_resume));
        Class hotspotNetworkClass = NSClassFromString(@"NEHotspotNetwork");
        LCSwizzleClassIfPresentWithSourceClass(
            hotspotNetworkClass,
            LCNetworkExtensionStrictHookProvider.class,
            @selector(fetchCurrentWithCompletionHandler:),
            @selector(hook_fetchCurrentWithCompletionHandler:)
        );
    }

    BOOL shouldEnableSpoofProfile = [guestContainerInfo[@"spoofProfileEnabled"] boolValue];
    spoofIdentityCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofIdentityCategoryEnabled", YES);
    spoofSystemCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofSystemCategoryEnabled", YES);
    spoofDisplayCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofDisplayCategoryEnabled", YES);
    spoofLocaleCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofLocaleCategoryEnabled", YES);
    spoofBatteryCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofBatteryCategoryEnabled", YES);
    spoofTelephonyCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofTelephonyCategoryEnabled", YES);
    spoofNetworkHeadersCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofNetworkHeadersCategoryEnabled", YES);
    spoofAccessibilityCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofAccessibilityCategoryEnabled", YES);
    spoofStorageCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofStorageCategoryEnabled", YES);
    spoofNetworkEnvironmentCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofNetworkEnvironmentCategoryEnabled", YES);
    spoofAudioCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofAudioCategoryEnabled", YES);
    spoofGraphicsCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofGraphicsCategoryEnabled", YES);
    spoofWebViewCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofWebViewCategoryEnabled", YES);
    spoofAppPrivacyCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofAppPrivacyCategoryEnabled", YES);
    spoofSensorsAndUserDataCategoryEnabled = LCBoolWithDefault(guestContainerInfo, @"spoofSensorsAndUserDataCategoryEnabled", YES);
    if(shouldEnableSpoofProfile && spoofAppPrivacyCategoryEnabled && !strictTestMode) {
        strictPrivatePasteboard = [UIPasteboard pasteboardWithUniqueName];
        LCSwizzleClassIfPresent(UIPasteboard.class, @selector(generalPasteboard), @selector(hook_generalPasteboard));
    }
    rotateOSMajorVersions = LCParseRotationOSMajorVersions(guestContainerInfo[@"rotateOSMajorVersions"]);
    rotateUsesRealDeviceTemplates = LCBoolWithDefault(guestContainerInfo, @"rotateUsesRealDeviceTemplates", YES);
    BOOL rotateSpoofProfileOnLaunch = [guestContainerInfo[@"rotateSpoofProfileOnLaunch"] boolValue];
    BOOL shouldSpoofIdentifierForVendor = shouldEnableSpoofProfile && spoofIdentityCategoryEnabled &&
        [guestContainerInfo[@"spoofIdentifierForVendor"] boolValue];
    if(shouldSpoofIdentifierForVendor) {
        NSString* idForVendorStr = guestContainerInfo[@"spoofedIdentifierForVendor"];
        if([idForVendorStr isKindOfClass:NSString.class]) {
            idForVendorUUID = [[NSUUID UUID] initWithUUIDString:idForVendorStr];
        }
    }
    if(blockDeviceInfoReads || (shouldSpoofIdentifierForVendor && (idForVendorUUID != nil || rotateSpoofProfileOnLaunch))) {
        swizzle(UIDevice.class, @selector(identifierForVendor), @selector(hook_identifierForVendor));
    }

    if(shouldEnableSpoofProfile) {
        spoofProfileEnabled = YES;
        NSString *deviceName = guestContainerInfo[@"spoofDeviceName"];
        NSString *deviceModel = guestContainerInfo[@"spoofDeviceModel"];
        NSString *systemName = guestContainerInfo[@"spoofSystemName"];
        NSString *systemVersion = guestContainerInfo[@"spoofSystemVersion"];
        NSString *localeIdentifier = guestContainerInfo[@"spoofLocaleIdentifier"];
        NSString *timeZoneIdentifier = guestContainerInfo[@"spoofTimeZoneIdentifier"];
        NSNumber *batteryLevelNumber = guestContainerInfo[@"spoofBatteryLevel"];
        NSNumber *batteryStateNumber = guestContainerInfo[@"spoofBatteryState"];
        NSNumber *lowPowerModeNumber = guestContainerInfo[@"spoofLowPowerModeEnabled"];
        NSString *radioAccessTechnology = guestContainerInfo[@"spoofRadioAccessTechnology"];
        NSString *subscriberIdentifier = guestContainerInfo[@"spoofSubscriberIdentifier"];
        NSString *subscriberCarrierTokenBase64 = guestContainerInfo[@"spoofSubscriberCarrierTokenBase64"];
        NSNumber *subscriberSIMInsertedEnabledNumber = guestContainerInfo[@"spoofSubscriberSIMInsertedEnabled"];
        NSNumber *subscriberSIMInsertedNumber = guestContainerInfo[@"spoofSubscriberSIMInserted"];
        NSString *hostName = guestContainerInfo[@"spoofHostName"];
        NSString *boardModel = guestContainerInfo[@"spoofBoardModel"];
        NSNumber *processorCount = guestContainerInfo[@"spoofProcessorCount"];
        NSNumber *physicalMemory = guestContainerInfo[@"spoofPhysicalMemory"];
        NSNumber *thermalState = guestContainerInfo[@"spoofThermalState"];
        NSNumber *screenWidth = guestContainerInfo[@"spoofScreenWidth"];
        NSNumber *screenHeight = guestContainerInfo[@"spoofScreenHeight"];
        NSNumber *screenScale = guestContainerInfo[@"spoofScreenScale"];
        NSNumber *screenNativeScale = guestContainerInfo[@"spoofScreenNativeScale"];
        NSNumber *maximumFramesPerSecond = guestContainerInfo[@"spoofMaximumFramesPerSecond"];
        NSNumber *screenBrightness = guestContainerInfo[@"spoofScreenBrightness"];
        NSNumber *userInterfaceStyle = guestContainerInfo[@"spoofUserInterfaceStyle"];
        NSNumber *accessibilityContrast = guestContainerInfo[@"spoofAccessibilityContrast"];
        NSNumber *displayGamut = guestContainerInfo[@"spoofDisplayGamut"];
        NSNumber *horizontalSizeClass = guestContainerInfo[@"spoofHorizontalSizeClass"];
        NSNumber *verticalSizeClass = guestContainerInfo[@"spoofVerticalSizeClass"];
        NSString *preferredContentSizeCategory = guestContainerInfo[@"spoofPreferredContentSizeCategory"];
        NSNumber *safeAreaTop = guestContainerInfo[@"spoofSafeAreaTop"];
        NSNumber *safeAreaLeft = guestContainerInfo[@"spoofSafeAreaLeft"];
        NSNumber *safeAreaBottom = guestContainerInfo[@"spoofSafeAreaBottom"];
        NSNumber *safeAreaRight = guestContainerInfo[@"spoofSafeAreaRight"];
        NSString *kernelVersion = guestContainerInfo[@"spoofKernelVersion"];
        NSNumber *bootTime = guestContainerInfo[@"spoofBootTime"];
        NSNumber *cpuType = guestContainerInfo[@"spoofCPUType"];
        NSNumber *cpuSubtype = guestContainerInfo[@"spoofCPUSubtype"];
        NSString *hardwareModel = guestContainerInfo[@"spoofHardwareModel"];
        NSNumber *storageTotalCapacity = guestContainerInfo[@"spoofStorageTotalCapacity"];
        NSNumber *storageAvailableCapacity = guestContainerInfo[@"spoofStorageAvailableCapacity"];
        NSString *gpuName = guestContainerInfo[@"spoofGPUName"];
        NSNumber *audioOutputVolume = guestContainerInfo[@"spoofAudioOutputVolume"];

        if([deviceName isKindOfClass:NSString.class] && deviceName.length > 0) {
            spoofDeviceName = deviceName;
        }
        if([deviceModel isKindOfClass:NSString.class] && deviceModel.length > 0) {
            spoofDeviceModel = deviceModel;
        }
        if([systemName isKindOfClass:NSString.class] && systemName.length > 0) {
            spoofSystemName = systemName;
        }
        if([systemVersion isKindOfClass:NSString.class] && systemVersion.length > 0) {
            spoofSystemVersion = systemVersion;
            spoofOperatingSystemVersionValid = LCParseSystemVersion(systemVersion, &spoofOperatingSystemVersion);
        }

        if([localeIdentifier isKindOfClass:NSString.class] && localeIdentifier.length > 0) {
            NSLocale *candidateLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier];
            if(candidateLocale.localeIdentifier.length > 0) {
                spoofLocale = candidateLocale;
            }
        }

        if([timeZoneIdentifier isKindOfClass:NSString.class] && timeZoneIdentifier.length > 0) {
            NSTimeZone *candidateTimeZone = [NSTimeZone timeZoneWithName:timeZoneIdentifier];
            if(candidateTimeZone) {
                spoofTimeZone = candidateTimeZone;
                if(!blockDeviceInfoReads && spoofLocaleCategoryEnabled) {
                    [NSTimeZone setDefaultTimeZone:candidateTimeZone];
                }
            }
        }
        if([batteryLevelNumber isKindOfClass:NSNumber.class]) {
            float level = batteryLevelNumber.floatValue;
            if(level >= 0.0f && level <= 1.0f) {
                spoofBatteryLevel = level;
            }
        }
        if([batteryStateNumber isKindOfClass:NSNumber.class]) {
            NSInteger value = batteryStateNumber.integerValue;
            if(value >= UIDeviceBatteryStateUnknown && value <= UIDeviceBatteryStateFull) {
                spoofBatteryState = value;
            }
        }
        if([lowPowerModeNumber isKindOfClass:NSNumber.class]) {
            spoofLowPowerModeEnabled = lowPowerModeNumber.boolValue;
            spoofLowPowerModeEnabledSet = YES;
        }
        if([radioAccessTechnology isKindOfClass:NSString.class] && radioAccessTechnology.length > 0) {
            spoofRadioAccessTechnology = radioAccessTechnology;
        }
        if([subscriberIdentifier isKindOfClass:NSString.class] && subscriberIdentifier.length > 0) {
            spoofSubscriberIdentifier = subscriberIdentifier;
        }
        if([subscriberCarrierTokenBase64 isKindOfClass:NSString.class] && subscriberCarrierTokenBase64.length > 0) {
            NSData *decodedToken = [[NSData alloc] initWithBase64EncodedString:subscriberCarrierTokenBase64 options:0];
            if(decodedToken.length > 0) {
                spoofSubscriberCarrierToken = decodedToken;
            }
        }
        if([subscriberSIMInsertedEnabledNumber isKindOfClass:NSNumber.class]) {
            spoofSubscriberSIMInsertedEnabled = subscriberSIMInsertedEnabledNumber.boolValue;
        }
        if([subscriberSIMInsertedNumber isKindOfClass:NSNumber.class]) {
            spoofSubscriberSIMInserted = subscriberSIMInsertedNumber.boolValue;
        }
        if([hostName isKindOfClass:NSString.class] && hostName.length > 0) {
            spoofHostName = hostName;
        }
        if([boardModel isKindOfClass:NSString.class] && boardModel.length > 0) {
            spoofBoardModel = boardModel;
        }
        if([processorCount isKindOfClass:NSNumber.class] && processorCount.integerValue > 0) {
            spoofProcessorCount = processorCount.integerValue;
        }
        if([physicalMemory isKindOfClass:NSNumber.class] && physicalMemory.unsignedLongLongValue > 0) {
            spoofPhysicalMemory = physicalMemory.unsignedLongLongValue;
        }
        if([thermalState isKindOfClass:NSNumber.class] && thermalState.integerValue >= 0 && thermalState.integerValue <= 3) {
            spoofThermalState = thermalState.integerValue;
        }
        if([screenWidth isKindOfClass:NSNumber.class] && screenWidth.doubleValue > 0) spoofScreenWidth = screenWidth.doubleValue;
        if([screenHeight isKindOfClass:NSNumber.class] && screenHeight.doubleValue > 0) spoofScreenHeight = screenHeight.doubleValue;
        if([screenScale isKindOfClass:NSNumber.class] && screenScale.doubleValue > 0) spoofScreenScale = screenScale.doubleValue;
        if([screenNativeScale isKindOfClass:NSNumber.class] && screenNativeScale.doubleValue > 0) spoofScreenNativeScale = screenNativeScale.doubleValue;
        if([maximumFramesPerSecond isKindOfClass:NSNumber.class] && maximumFramesPerSecond.integerValue > 0) {
            spoofMaximumFramesPerSecond = maximumFramesPerSecond.integerValue;
        }
        if([screenBrightness isKindOfClass:NSNumber.class] && screenBrightness.doubleValue >= 0 && screenBrightness.doubleValue <= 1) {
            spoofScreenBrightness = screenBrightness.doubleValue;
        }
        if([userInterfaceStyle isKindOfClass:NSNumber.class] && userInterfaceStyle.integerValue >= UIUserInterfaceStyleUnspecified && userInterfaceStyle.integerValue <= UIUserInterfaceStyleDark) {
            spoofUserInterfaceStyle = userInterfaceStyle.integerValue;
        }
        if([accessibilityContrast isKindOfClass:NSNumber.class] && accessibilityContrast.integerValue >= UIAccessibilityContrastNormal && accessibilityContrast.integerValue <= UIAccessibilityContrastHigh) {
            spoofAccessibilityContrast = accessibilityContrast.integerValue;
        }
        if([displayGamut isKindOfClass:NSNumber.class] && displayGamut.integerValue >= UIDisplayGamutUnspecified && displayGamut.integerValue <= UIDisplayGamutP3) {
            spoofDisplayGamut = displayGamut.integerValue;
        }
        if([horizontalSizeClass isKindOfClass:NSNumber.class] && horizontalSizeClass.integerValue >= UIUserInterfaceSizeClassUnspecified && horizontalSizeClass.integerValue <= UIUserInterfaceSizeClassRegular) {
            spoofHorizontalSizeClass = horizontalSizeClass.integerValue;
        }
        if([verticalSizeClass isKindOfClass:NSNumber.class] && verticalSizeClass.integerValue >= UIUserInterfaceSizeClassUnspecified && verticalSizeClass.integerValue <= UIUserInterfaceSizeClassRegular) {
            spoofVerticalSizeClass = verticalSizeClass.integerValue;
        }
        if([preferredContentSizeCategory isKindOfClass:NSString.class] && preferredContentSizeCategory.length > 0) {
            spoofPreferredContentSizeCategory = preferredContentSizeCategory;
        }
        if([safeAreaTop isKindOfClass:NSNumber.class]) spoofSafeAreaInsets.top = MAX(0, safeAreaTop.doubleValue);
        if([safeAreaLeft isKindOfClass:NSNumber.class]) spoofSafeAreaInsets.left = MAX(0, safeAreaLeft.doubleValue);
        if([safeAreaBottom isKindOfClass:NSNumber.class]) spoofSafeAreaInsets.bottom = MAX(0, safeAreaBottom.doubleValue);
        if([safeAreaRight isKindOfClass:NSNumber.class]) spoofSafeAreaInsets.right = MAX(0, safeAreaRight.doubleValue);
        if([kernelVersion isKindOfClass:NSString.class] && kernelVersion.length > 0) spoofKernelVersion = kernelVersion;
        if([bootTime isKindOfClass:NSNumber.class] && bootTime.longLongValue > 0) spoofBootTime = (time_t)bootTime.longLongValue;
        if([cpuType isKindOfClass:NSNumber.class] && cpuType.intValue > 0) spoofCPUType = cpuType.intValue;
        if([cpuSubtype isKindOfClass:NSNumber.class] && cpuSubtype.intValue >= 0) spoofCPUSubtype = cpuSubtype.intValue;
        if([hardwareModel isKindOfClass:NSString.class] && hardwareModel.length > 0) spoofHardwareModel = hardwareModel;
        if([storageTotalCapacity isKindOfClass:NSNumber.class] && storageTotalCapacity.longLongValue > 0) {
            spoofStorageTotalCapacity = storageTotalCapacity.longLongValue;
        }
        if([storageAvailableCapacity isKindOfClass:NSNumber.class] && storageAvailableCapacity.longLongValue >= 0) {
            spoofStorageAvailableCapacity = MIN(spoofStorageTotalCapacity, storageAvailableCapacity.longLongValue);
        }
        if([gpuName isKindOfClass:NSString.class]) spoofGPUName = gpuName;
        if([audioOutputVolume isKindOfClass:NSNumber.class]) {
            spoofAudioOutputVolume = MIN(1, MAX(0, audioOutputVolume.floatValue));
        }

    }

    if(shouldEnableSpoofProfile && spoofAccessibilityCategoryEnabled) {
        LCInstallNeutralAccessibilityProfile();
        LCSwizzleIfPresent(UITraitCollection.class, @selector(accessibilityContrast), @selector(hook_accessibilityContrast));
    }
    if(shouldEnableSpoofProfile && spoofLocaleCategoryEnabled) {
        LCInstallLocalePrivacyProfile();
    }
    if(shouldEnableSpoofProfile && spoofAudioCategoryEnabled) {
        LCInstallAudioPrivacyProfile();
    }
    if(shouldEnableSpoofProfile && spoofGraphicsCategoryEnabled) {
        LCInstallGraphicsPrivacyProfile();
    }
    if(shouldEnableSpoofProfile && spoofAppPrivacyCategoryEnabled) {
        LCInstallAppEnumerationPrivacyProfile();
    }
    if(shouldEnableSpoofProfile && spoofSensorsAndUserDataCategoryEnabled) {
        LCInstallSensorsAndUserDataPrivacyProfile();
    }
    if(shouldEnableSpoofProfile && spoofSystemCategoryEnabled) {
        LCSwizzleIfPresent(NSUserDefaults.class, @selector(boolForKey:), @selector(hook_boolForKey:));
    }
    if(shouldEnableSpoofProfile && spoofStorageCategoryEnabled) {
        Class concreteURLClass = [[NSURL fileURLWithPath:NSHomeDirectory()] class];
        LCSwizzleIfPresentWithSourceClass(concreteURLClass, NSURL.class,
            @selector(resourceValuesForKeys:error:), @selector(hook_resourceValuesForKeys:error:));
        LCSwizzleIfPresentWithSourceClass(concreteURLClass, NSURL.class,
            @selector(getResourceValue:forKey:error:), @selector(hook_getResourceValue:forKey:error:));
    }
    if(shouldEnableSpoofProfile && spoofAppPrivacyCategoryEnabled) {
        LCSwizzleIfPresent(NSFileManager.class, @selector(ubiquityIdentityToken), @selector(hook_ubiquityIdentityToken));
    }
    if(shouldEnableSpoofProfile && spoofWebViewCategoryEnabled) {
        LCSwizzleIfPresent(WKWebView.class, @selector(initWithFrame:configuration:), @selector(hook_initWithFrame:configuration:));
    }

    if(shouldEnableSpoofProfile && rotateSpoofProfileOnLaunch) {
        LCRotateSpoofProfile();
    }
    if(blockDeviceInfoReads) {
        spoofHardwareModel = @"iPhone";
        spoofHostName = @"localhost";
        spoofBoardModel = @"Unknown";
        spoofKernelVersion = @"Unknown";
    }

    if(blockDeviceInfoReads ||
       (spoofIdentityCategoryEnabled && (spoofDeviceName || spoofDeviceModel)) ||
       (spoofSystemCategoryEnabled && (spoofSystemName || spoofSystemVersion))) {
        swizzle(UIDevice.class, @selector(name), @selector(hook_name));
        swizzle(UIDevice.class, @selector(model), @selector(hook_model));
        swizzle(UIDevice.class, @selector(localizedModel), @selector(hook_localizedModel));
        swizzle(UIDevice.class, @selector(systemName), @selector(hook_systemName));
        swizzle(UIDevice.class, @selector(systemVersion), @selector(hook_systemVersion));
    }
    if(blockDeviceInfoReads || (spoofBatteryCategoryEnabled &&
       (spoofBatteryLevel >= 0.0f || spoofBatteryState != UIDeviceBatteryStateUnknown))) {
        swizzle(UIDevice.class, @selector(batteryLevel), @selector(hook_batteryLevel));
        swizzle(UIDevice.class, @selector(batteryState), @selector(hook_batteryState));
        swizzle(UIDevice.class, @selector(isBatteryMonitoringEnabled), @selector(hook_isBatteryMonitoringEnabled));
    }
    if(blockDeviceInfoReads || (spoofSystemCategoryEnabled && (spoofOperatingSystemVersionValid || spoofSystemVersion))) {
        swizzle(NSProcessInfo.class, @selector(operatingSystemVersion), @selector(hook_operatingSystemVersion));
        swizzle(NSProcessInfo.class, @selector(operatingSystemVersionString), @selector(hook_operatingSystemVersionString));
        swizzle(NSProcessInfo.class, @selector(isOperatingSystemAtLeastVersion:), @selector(hook_isOperatingSystemAtLeastVersion:));
    }
    if(blockDeviceInfoReads || (spoofBatteryCategoryEnabled && spoofLowPowerModeEnabledSet)) {
        swizzle(NSProcessInfo.class, @selector(isLowPowerModeEnabled), @selector(hook_isLowPowerModeEnabled));
    }
    if(blockDeviceInfoReads || (spoofSystemCategoryEnabled &&
       (spoofProcessorCount > 0 || spoofPhysicalMemory > 0))) {
        swizzle(NSProcessInfo.class, @selector(processorCount), @selector(hook_processorCount));
        swizzle(NSProcessInfo.class, @selector(activeProcessorCount), @selector(hook_activeProcessorCount));
        swizzle(NSProcessInfo.class, @selector(physicalMemory), @selector(hook_physicalMemory));
    }
    if(blockDeviceInfoReads || (spoofBatteryCategoryEnabled && spoofThermalState >= 0)) {
        swizzle(NSProcessInfo.class, @selector(thermalState), @selector(hook_thermalState));
    }
    if(blockDeviceInfoReads || (spoofDisplayCategoryEnabled &&
       (spoofScreenWidth > 0 || spoofScreenHeight > 0 || spoofScreenScale > 0 ||
        spoofScreenNativeScale > 0 || spoofMaximumFramesPerSecond > 0 || spoofScreenBrightness >= 0))) {
        swizzle(UIScreen.class, @selector(nativeBounds), @selector(hook_nativeBounds));
        swizzle(UIScreen.class, @selector(scale), @selector(hook_scale));
        swizzle(UIScreen.class, @selector(nativeScale), @selector(hook_nativeScale));
        swizzle(UIScreen.class, @selector(maximumFramesPerSecond), @selector(hook_maximumFramesPerSecond));
        swizzle(UIScreen.class, @selector(brightness), @selector(hook_brightness));
        LCSwizzleIfPresent(UITraitCollection.class, @selector(displayGamut), @selector(hook_displayGamut));
        LCSwizzleIfPresent(UITraitCollection.class, @selector(horizontalSizeClass), @selector(hook_horizontalSizeClass));
        LCSwizzleIfPresent(UITraitCollection.class, @selector(verticalSizeClass), @selector(hook_verticalSizeClass));
        LCSwizzleIfPresent(UITraitCollection.class, @selector(preferredContentSizeCategory), @selector(hook_preferredContentSizeCategory));
        LCSwizzleIfPresent(UITraitCollection.class, @selector(userInterfaceStyle), @selector(hook_userInterfaceStyle));
        LCSwizzleIfPresent(UIWindow.class, @selector(safeAreaInsets), @selector(hook_safeAreaInsets));
    }
    if(blockDeviceInfoReads || (spoofLocaleCategoryEnabled && spoofLocale)) {
        LCSwizzleClassIfPresent(NSLocale.class, @selector(currentLocale), @selector(hook_currentLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(autoupdatingCurrentLocale), @selector(hook_autoupdatingCurrentLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(systemLocale), @selector(hook_systemLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(preferredLanguages), @selector(hook_preferredLanguages));
    }
    if(blockDeviceInfoReads || (spoofLocaleCategoryEnabled && (spoofTimeZone || spoofLocale))) {
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(localTimeZone), @selector(hook_localTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(systemTimeZone), @selector(hook_systemTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(defaultTimeZone), @selector(hook_defaultTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(autoupdatingCurrentTimeZone), @selector(hook_autoupdatingCurrentTimeZone));
        LCSwizzleClassIfPresent(NSCalendar.class, @selector(currentCalendar), @selector(hook_currentCalendar));
        LCSwizzleClassIfPresent(NSCalendar.class, @selector(autoupdatingCurrentCalendar), @selector(hook_autoupdatingCurrentCalendar));
    }
    if(blockDeviceInfoReads || (spoofTelephonyCategoryEnabled && spoofRadioAccessTechnology)) {
        Class telephonyClass = NSClassFromString(@"CTTelephonyNetworkInfo");
        LCSwizzleIfPresentWithSourceClass(telephonyClass, LCTelephonyNetworkInfoHookProvider.class, @selector(serviceCurrentRadioAccessTechnology), @selector(hook_serviceCurrentRadioAccessTechnology));
    }
    if(blockDeviceInfoReads || (spoofTelephonyCategoryEnabled &&
       (spoofSubscriberIdentifier || spoofSubscriberCarrierToken || spoofSubscriberSIMInsertedEnabled))) {
        Class subscriberClass = NSClassFromString(@"CTSubscriber");
        LCSwizzleIfPresentWithSourceClass(subscriberClass, LCSubscriberHookProvider.class, NSSelectorFromString(@"identifier"), @selector(hook_identifier));
        LCSwizzleIfPresentWithSourceClass(subscriberClass, LCSubscriberHookProvider.class, NSSelectorFromString(@"carrierToken"), @selector(hook_carrierToken));
        LCSwizzleIfPresentWithSourceClass(subscriberClass, LCSubscriberHookProvider.class, NSSelectorFromString(@"isSIMInserted"), @selector(hook_isSIMInserted));

        Class subscriberInfoClass = NSClassFromString(@"CTSubscriberInfo");
        LCSwizzleClassIfPresentWithSourceClass(subscriberInfoClass, LCSubscriberInfoHookProvider.class, @selector(subscribers), @selector(hook_subscribers));
    }

    // HTTP header device identity rewriting
    // Hook NSMutableURLRequest to rewrite User-Agent in ALL outgoing HTTP requests.
    // This catches native iOS, Flutter, React Native, Expo, Firebase, PostHog,
    // Adjust, AppsFlyer, and any analytics SDK — they all go through NSMutableURLRequest.
    if((blockDeviceInfoReads || spoofNetworkHeadersCategoryEnabled) && (spoofHardwareModel || spoofSystemVersion)) {
        LCInitUserAgentRegexes();
        swizzle(NSMutableURLRequest.class,
            @selector(setValue:forHTTPHeaderField:),
            @selector(hook_setValue:forHTTPHeaderField:));
        swizzle(NSMutableURLRequest.class,
            @selector(addValue:forHTTPHeaderField:),
            @selector(hook_addValue:forHTTPHeaderField:));
        swizzle(NSMutableURLRequest.class,
            @selector(setAllHTTPHeaderFields:),
            @selector(hook_setAllHTTPHeaderFields:));
        swizzle(NSURLSessionConfiguration.class,
            @selector(setHTTPAdditionalHeaders:),
            @selector(hook_setHTTPAdditionalHeaders:));
    }
}

NSString* findDefaultContainerWithBundleId(NSString* bundleId) {
    // find app's default container
    NSString *appGroupPath = [NSUserDefaults lcAppGroupPath];
    NSString* appGroupFolder = [appGroupPath stringByAppendingPathComponent:@"LiveContainer"];

    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    if(!infoDict) {
        NSString* lcDocFolder = [[NSString stringWithUTF8String:getenv("LC_HOME_PATH")] stringByAppendingPathComponent:@"Documents"];

        bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", lcDocFolder, bundleId];
        infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    }

    return infoDict[@"LCDataUUID"];
}

void forEachInstalledNotCurrentLC(BOOL isFree, void (^block)(NSString* scheme, BOOL* isBreak)) {
    for(NSString* scheme in [NSClassFromString(@"LCSharedUtils") lcUrlSchemes]) {
        if([scheme isEqualToString:NSUserDefaults.lcAppUrlScheme]) {
            continue;
        }
        BOOL isInstalled = [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString: [NSString stringWithFormat: @"%@://", scheme]]];
        if(!isInstalled) {
            continue;
        }
        BOOL isBreak = false;
        if(isFree && [NSClassFromString(@"LCSharedUtils") isLCSchemeInUse:scheme]) {
            continue;
        }
        block(scheme, &isBreak);
        if(isBreak) {
            return;
        }
    }
}

void LCShowSwitchAppConfirmation(NSURL *url, NSString* bundleId, bool isSharedApp) {
    NSURLComponents* newUrlComp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];

    // check if there's any free LiveContainer to run the app
    if(isSharedApp) {
        __block BOOL anotherLCLaunched = false;
        forEachInstalledNotCurrentLC(YES, ^(NSString * scheme, BOOL* isBreak) {
            newUrlComp.scheme = scheme;
            [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
            *isBreak = YES;
            anotherLCLaunched = YES;
            return;
        });
        if(anotherLCLaunched) {
            return;
        }
    }

    // if LCSwitchAppWithoutAsking is enabled we directly open the app in current lc
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCSwitchAppWithoutAsking"]) {
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        return;
    }

    NSString *message = [@"lc.guestTweak.appSwitchTip %@" localizeWithFormat:bundleId];
    UIWindow *window = [[UIWindow alloc] initWithFrame:LCActiveScreenBounds()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSUserDefaults.lcUserDefaults setBool:NO forKey:@"LCOpenSideStore"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        window.windowScene = nil;
    }];
    [alert addAction:okAction];

    if(isSharedApp) {
        forEachInstalledNotCurrentLC(NO, ^(NSString * scheme, BOOL* isBreak) {
            UIAlertAction* openlcAction = [UIAlertAction actionWithTitle:[@"lc.guestTweak.openInLc %@" localizeWithFormat:scheme] style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                newUrlComp.scheme = scheme;
                [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
                window.windowScene = nil;
            }];
            [alert addAction:openlcAction];
        });
    }

    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LCShowAlert(NSString* message) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:LCActiveScreenBounds()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LCShowAppNotFoundAlert(NSString* bundleId) {
    LCShowAlert([@"lc.guestTweak.error.bundleNotFound %@" localizeWithFormat: bundleId]);
}

void openUniversalLink(NSString* decodedUrl) {
    NSURL* urlToOpen = [NSURL URLWithString: decodedUrl];
    if(![urlToOpen.scheme isEqualToString:@"https"] && ![urlToOpen.scheme isEqualToString:@"http"]) {
        NSData *data = [decodedUrl dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];

        NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", NSUserDefaults.lcAppUrlScheme, encodedUrl];
        NSURL* url = [NSURL URLWithString: finalUrl];

        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }

    UIActivityContinuationManager* uacm = [[UIApplication sharedApplication] _getActivityContinuationManager];
    NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = urlToOpen;
    NSDictionary* dict = @{
        @"UIApplicationLaunchOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityKey": activity,
        @"UIApplicationLaunchOptionsUserActivityIdentifierKey": NSUUID.UUID.UUIDString,
        @"UINSUserActivitySourceApplicationKey": @"com.apple.mobilesafari",
        @"UIApplicationLaunchOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb
    };

    [uacm handleActivityContinuation:dict isSuspended:nil];
}

void LCOpenWebPage(NSString* webPageUrlString, NSString* originalUrl) {
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCOpenWebPageWithoutAsking"]) {
        openUniversalLink(webPageUrlString);
        return;
    }

    NSURLComponents* newUrlComp = [NSURLComponents componentsWithString:originalUrl];
    __block BOOL anotherLCLaunched = false;
    forEachInstalledNotCurrentLC(YES, ^(NSString * scheme, BOOL* isBreak) {
        newUrlComp.scheme = scheme;
        [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
        *isBreak = YES;
        anotherLCLaunched = YES;
        return;
    });
    if(anotherLCLaunched) {
        return;
    }

    NSString *message = @"lc.guestTweak.openWebPageTip".loc;
    UIWindow *window = [[UIWindow alloc] initWithFrame:LCActiveScreenBounds()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSClassFromString(@"LCSharedUtils") setWebPageUrlForNextLaunch:webPageUrlString];
        [NSClassFromString(@"LCSharedUtils") launchToGuestApp];
    }];
    [alert addAction:okAction];
    UIAlertAction* openNowAction = [UIAlertAction actionWithTitle:@"lc.guestTweak.openInCurrentApp".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        openUniversalLink(webPageUrlString);
        window.windowScene = nil;
    }];

    forEachInstalledNotCurrentLC(NO, ^(NSString * scheme, BOOL* isBreak) {
        UIAlertAction* openlc2Action = [UIAlertAction actionWithTitle:[@"lc.guestTweak.openInLc %@" localizeWithFormat:scheme] style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            newUrlComp.scheme = scheme;
            [UIApplication.sharedApplication openURL:newUrlComp.URL options:@{} completionHandler:nil];
            window.windowScene = nil;
        }];
        [alert addAction:openlc2Action];
    });

    [alert addAction:openNowAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);


}

void LCOpenSideStoreURL(NSURL* sidestoreUrl) {
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCSwitchAppWithoutAsking"]) {
        [NSUserDefaults.lcUserDefaults setObject:sidestoreUrl.absoluteString forKey:@"launchAppUrlScheme"];
        [NSUserDefaults.lcUserDefaults setObject:@"builtinSideStore" forKey:@"selected"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestApp];
    }
    NSString *message = [@"lc.guestTweak.appSwitchTip %@" localizeWithFormat:@"SideStore"];
    UIWindow *window = [[UIWindow alloc] initWithFrame:LCActiveScreenBounds()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSUserDefaults.lcUserDefaults setObject:sidestoreUrl.absoluteString forKey:@"launchAppUrlScheme"];
        [NSUserDefaults.lcUserDefaults setObject:@"builtinSideStore" forKey:@"selected"];
        [NSClassFromString(@"LCSharedUtils") launchToGuestApp];
    }];
    [alert addAction:okAction];

    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel".loc style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

}

void authenticateUser(void (^completion)(BOOL success, NSError *error)) {
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;

    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
        NSString *reason = @"lc.utils.requireAuthentication".loc;

        // Evaluate the policy for both biometric and passcode authentication
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                localizedReason:reason
                          reply:^(BOOL success, NSError * _Nullable evaluationError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    completion(YES, nil);
                } else {
                    completion(NO, evaluationError);
                }
            });
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if([error code] == LAErrorPasscodeNotSet) {
                completion(YES, nil);
            } else {
                completion(NO, error);
            }
        });
    }
}

void handleLiveContainerLaunch(NSString* bundleName, NSString* containerFolderName, NSURL* url) {
    // check if there are other LCs is running this app
        NSString* runningLC = [NSClassFromString(@"LCSharedUtils") getContainerUsingLCSchemeWithFolderName:containerFolderName];
        // the app is running in an lc, that lc is not me, also is not my avatar
        if(runningLC) {
            if([runningLC hasSuffix:@"liveprocess"]) {
                runningLC = runningLC.stringByDeletingPathExtension;
            }
            NSString* urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@&container-folder-name=%@", runningLC, bundleName, containerFolderName];
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:urlStr] options:@{} completionHandler:nil];
            return;
        }

        bool isSharedApp = false;
        NSBundle* bundle = [NSClassFromString(@"LCSharedUtils") findBundleWithBundleId: bundleName isSharedAppOut:&isSharedApp];
        NSDictionary* lcAppInfo;
        if(bundle) {
            lcAppInfo = [NSDictionary dictionaryWithContentsOfURL:[bundle URLForResource:@"LCAppInfo" withExtension:@"plist"]];
        }

        if(!bundle || ([lcAppInfo[@"isHidden"] boolValue] && [NSUserDefaults.lcSharedDefaults boolForKey:@"LCStrictHiding"])) {
            LCShowAppNotFoundAlert(bundleName);
        } else if ([lcAppInfo[@"isLocked"] boolValue]) {
            // need authentication
            authenticateUser(^(BOOL success, NSError *error) {
                if (success) {
                    LCShowSwitchAppConfirmation(url, bundleName, isSharedApp);
                } else {
                    if ([error.domain isEqualToString:LAErrorDomain]) {
                        if (error.code != LAErrorUserCancel) {
                            NSLog(@"[LC] Authentication Error: %@", error.localizedDescription);
                        }
                    } else {
                        NSLog(@"[LC] Authentication Error: %@", error.localizedDescription);
                    }
                }
            });
        } else {
            LCShowSwitchAppConfirmation(url, bundleName, isSharedApp);
        }

}

BOOL shouldRedirectOpenURLToHost(NSURL* url) {
    NSUserDefaults *ud = NSUserDefaults.lcSharedDefaults;
    return NSUserDefaults.isLiveProcess &&
    [ud boolForKey:@"LCRedirectURLToHost"] &&
    [[ud arrayForKey:@"LCGuestURLSchemes"] containsObject:url.scheme];
}
BOOL canAppOpenItself(NSURL* url) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSArray *urlTypes = [infoDictionary objectForKey:@"CFBundleURLTypes"];
        LCSupportedUrlSchemes = [[NSMutableArray alloc] init];
        for (NSDictionary *urlType in urlTypes) {
            NSArray *schemes = [urlType objectForKey:@"CFBundleURLSchemes"];
            for(NSString* scheme in schemes) {
                [LCSupportedUrlSchemes addObject:[scheme lowercaseString]];
            }
        }
    });
    return [LCSupportedUrlSchemes containsObject:[url.scheme lowercaseString]];
}

typedef NS_ENUM(NSInteger, LCControlAppURLHandling) {
    LCControlAppURLHandlingPassThrough,
    LCControlAppURLHandlingReplaceURL,
    LCControlAppURLHandlingStop,
};

static NSString* LCDecodedURLStringFromControlURL(NSURL *url) {
    NSURLComponents* lcUrl = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString* realUrlEncoded = nil;
    for(NSURLQueryItem *queryItem in lcUrl.queryItems) {
        if([queryItem.name isEqualToString:@"url"]) {
            realUrlEncoded = queryItem.value;
            break;
        }
    }
    if(!realUrlEncoded) {
        realUrlEncoded = lcUrl.queryItems.firstObject.value;
    }
    if(!realUrlEncoded) {
        return nil;
    }
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
    if(!decodedData) {
        return nil;
    }
    return [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
}

static void resolveLaunchExtensionFileBookmark(void) {
    NSData* bookmarkData = [NSUserDefaults.lcSharedDefaults dataForKey:@"LCLaunchExtensionFileBookmark"];
    if(!bookmarkData) {
        return;
    }
    BOOL isStale = NO;
    NSError* error = nil;
    NSURL* resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData
                                                   options:(1UL << 10)
                                             relativeToURL:nil
                                       bookmarkDataIsStale:&isStale
                                                     error:&error];
    if(!resolvedURL) {
        NSLog(@"[LC] Failed to resolve shared file bookmark: %@", error.localizedDescription);
    }
    [NSUserDefaults.lcSharedDefaults removeObjectForKey:@"LCLaunchExtensionFileBookmark"];

}

static LCControlAppURLHandling LCHandleControlAppURL(NSURL *url, NSString** modifiedURLStr) {
    if(!url || url.isFileURL) {
        return LCControlAppURLHandlingPassThrough;
    }

    // pass through sidestore urls
    if(NSUserDefaults.isSideStore && ![url.scheme isEqualToString:@"livecontainer"]) {
        return LCControlAppURLHandlingPassThrough;
    }

    if([url.scheme isEqualToString:@"sidestore"]) {
        LCOpenSideStoreURL(url);
        return LCControlAppURLHandlingStop;
    }

    NSString *lcScheme = NSUserDefaults.lcAppUrlScheme;
    // pass through any url that should not be handled by current lc
    if(![url.scheme isEqualToString:lcScheme]) {
        return LCControlAppURLHandlingPassThrough;
    }
    NSString* urlHost = url.host;

    if([urlHost isEqualToString:@"livecontainer-relaunch"]) {
        return LCControlAppURLHandlingStop;
    }

    if([urlHost isEqualToString:@"livecontainer-launch"]) {
        // If it's not current app, then switch, otherwise check if we need to open the url
        NSString* bundleName = nil;
        NSString* openUrl = nil;
        NSString* containerFolderName = nil;
        NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem* queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"bundle-name"]) {
                bundleName = queryItem.value;
            } else if ([queryItem.name isEqualToString:@"open-url"]) {
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
                openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
                containerFolderName = queryItem.value;
            }
        }

        // launch to LiveContainerUI
        if([bundleName isEqualToString:@"ui"]) {
            LCShowSwitchAppConfirmation(url, @"LiveContainer", false);
            return LCControlAppURLHandlingStop;
        }

        NSString* containerId = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
        if(!containerFolderName) {
            containerFolderName = findDefaultContainerWithBundleId(bundleName);
        }
        // current bundlename and container folder name matches OR sidestore is running and we are launching builtinSideStore
        if (([bundleName isEqualToString:NSBundle.mainBundle.bundlePath.lastPathComponent] && [containerId isEqualToString:containerFolderName]) ||
            (NSUserDefaults.isSideStore && [bundleName isEqualToString:@"builtinSideStore"])) {
            if(openUrl) {
                if([openUrl hasPrefix:@"file:"]) {
                    resolveLaunchExtensionFileBookmark();
                    *modifiedURLStr = openUrl;
                    return LCControlAppURLHandlingReplaceURL;
                } else {
                    openUniversalLink(openUrl);
                }
            }
        } else {
            if([bundleName isEqualToString:@"builtinSideStore"]) {
                LCShowSwitchAppConfirmation(url, @"SideStore", NO);
                return LCControlAppURLHandlingStop;
            }
            handleLiveContainerLaunch(bundleName, containerFolderName, url);
        }

        return LCControlAppURLHandlingStop;
    }

    if([urlHost isEqualToString:@"open-web-page"]) {
        NSString *decodedUrl = LCDecodedURLStringFromControlURL(url);
        if(decodedUrl) {
            LCOpenWebPage(decodedUrl, url.absoluteString);
        }
        return LCControlAppURLHandlingStop;
    }

    if([urlHost isEqualToString:@"open-url"]) {
        NSString *decodedUrl = LCDecodedURLStringFromControlURL(url);
        if(!decodedUrl) {
            return LCControlAppURLHandlingStop;
        }
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
            return LCControlAppURLHandlingStop;
        }
        *modifiedURLStr = decodedUrl;
        return LCControlAppURLHandlingReplaceURL;
    }

    if([urlHost isEqualToString:@"install"]) {
        LCShowAlert(@"lc.guestTweak.restartToInstall".loc);
        return LCControlAppURLHandlingStop;
    }

    return LCControlAppURLHandlingStop;
}

// Handler for AppDelegate
@implementation UIApplication(LiveContainerHook)
- (void)hook__applicationOpenURLAction:(id)action payload:(NSDictionary *)payload origin:(id)origin {
    NSURL *url = [NSURL URLWithString:payload[UIApplicationLaunchOptionsURLKey]];
    NSString* replacementURLString = nil;
    LCControlAppURLHandling decision = LCHandleControlAppURL(url, &replacementURLString);
    if(decision == LCControlAppURLHandlingStop) {
        return;
    }
    if(decision == LCControlAppURLHandlingReplaceURL) {
        NSMutableDictionary* newPayload = [payload mutableCopy];
        newPayload[UIApplicationLaunchOptionsURLKey] = replacementURLString;
        [self hook__applicationOpenURLAction:action payload:newPayload origin:origin];
        return;
    }
    [self hook__applicationOpenURLAction:action payload:payload origin:origin];
}

- (void)hook__connectUISceneFromFBSScene:(id)scene transitionContext:(UIApplicationSceneTransitionContext*)context {
#if !TARGET_OS_MACCATALYST
    NSString* decodedUrlStr = launchURLProcessed ? nil : NSUserDefaults.lcLaunchURL;
    launchURLProcessed = YES;
    NSString* urlStr;

    if(!decodedUrlStr && context.payload && (urlStr = context.payload[UIApplicationLaunchOptionsURLKey])) {
        do {
            if([urlStr hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
                NSURLComponents* lcUrl = [NSURLComponents componentsWithString:urlStr];
                NSString* realUrlEncoded = lcUrl.queryItems[0].value;
                if(!realUrlEncoded) break;
                // Convert the base64 encoded url into String
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
                decodedUrlStr = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            } else if([urlStr hasPrefix:NSUserDefaults.lcAppUrlScheme]) {
                context.payload = nil;
                context.actions = nil;
            }
        } while (0);
    }

    do {
        if(!decodedUrlStr) break;
        NSURL* decodedUrl = [NSURL URLWithString:decodedUrlStr];
        if(decodedUrl.isFileURL) {
            resolveLaunchExtensionFileBookmark();
        }

        NSMutableDictionary* newDict = [context.payload mutableCopy];
        if(!newDict) newDict = [NSMutableDictionary new];
        newDict[UIApplicationLaunchOptionsURLKey] = decodedUrlStr;
        context.payload = newDict;


        UIOpenURLAction *urlAction = nil;
        for (id obj in context.actions.allObjects) {
            if ([obj isKindOfClass:UIOpenURLAction.class]) {
                urlAction = obj;
                break;
            }
        }

        NSMutableSet *newActions = context.actions.mutableCopy;
        if(newActions && urlAction) {
            [newActions removeObject:urlAction];
        }
        if(!newActions) newActions = [NSMutableSet new];

        UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:decodedUrl];
        [newActions addObject:newUrlAction];
        context.actions = newActions;

    } while(0);

#endif
    [self hook__connectUISceneFromFBSScene:scene transitionContext:context];
}

-(BOOL)hook__handleDelegateCallbacksWithOptions:(id)arg1 isSuspended:(BOOL)arg2 restoreState:(BOOL)arg3 {
    BOOL ans = [self hook__handleDelegateCallbacksWithOptions:arg1 isSuspended:arg2 restoreState:arg3];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.apple.springboard"];
            [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:NSUserDefaults.lcMainBundle.bundleIdentifier];
        });

    });


    return ans;
}

- (void)hook_openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options completionHandler:(void (^)(_Bool))completion {
    if(NSUserDefaults.isSideStore && ![url.scheme isEqualToString:@"livecontainer"]) {
        [self hook_openURL:url options:options completionHandler:completion];
        return;
    }

    BOOL openSelf = canAppOpenItself(url);
    BOOL redirectToHost = shouldRedirectOpenURLToHost(url);;
    if(openSelf || redirectToHost) {
        NSString* schemeToUse = openSelf ? NSUserDefaults.lcAppUrlScheme : @"livecontainer";
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", schemeToUse, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
- (BOOL)hook_canOpenURL:(NSURL *) url {
    if(canAppOpenItself(url) || shouldRedirectOpenURLToHost(url)) return YES;
    if(spoofProfileEnabled && spoofAppPrivacyCategoryEnabled) return NO;
    return [self hook_canOpenURL:url];
}

- (void)hook_setDelegate:(id<UIApplicationDelegate>)delegate {
    if(![delegate respondsToSelector:@selector(application:configurationForConnectingSceneSession:options:)]) {
        // Fix old apps black screen when UIApplicationSupportsMultipleScenes is YES
        swizzle(UIWindow.class, @selector(makeKeyAndVisible), @selector(hook_makeKeyAndVisible));
        swizzle(UIWindow.class, @selector(makeKeyWindow), @selector(hook_makeKeyWindow));
        swizzle(UIWindow.class, @selector(setHidden:), @selector(hook_setHidden:));
    }
    [self hook_setDelegate:delegate];
}

+ (BOOL)_wantsApplicationBehaviorAsExtension {
    // Fix LiveProcess: Make _UIApplicationWantsExtensionBehavior return NO so delegate code runs in the run loop
    return YES;
}

@end

// Handler for SceneDelegate
@implementation UIScene(LiveContainerHook)
- (void)hook_scene:(id)scene didReceiveActions:(NSSet *)actions fromTransitionContext:(id)context {
    UIOpenURLAction *urlAction = nil;
    for (id obj in actions.allObjects) {
        if ([obj isKindOfClass:UIOpenURLAction.class]) {
            urlAction = obj;
            break;
        }
    }

    if(!urlAction) {
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }
    NSString* replacementURLString = nil;
    LCControlAppURLHandling decision = LCHandleControlAppURL(urlAction.url, &replacementURLString);
    if(decision == LCControlAppURLHandlingStop) {
        return;
    }
    if(decision == LCControlAppURLHandlingReplaceURL) {
        NSURL* finalURL = [NSURL URLWithString:replacementURLString];
        if(!finalURL) {
            return;
        }
        NSMutableSet *newActions = actions.mutableCopy;
        [newActions removeObject:urlAction];
        UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:finalURL];
        [newActions addObject:newUrlAction];
        [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
        return;
    }
    [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
}

- (void)hook_openURL:(NSURL *)url options:(UISceneOpenExternalURLOptions *)options completionHandler:(void (^)(BOOL success))completion {
    BOOL openSelf = canAppOpenItself(url);
    BOOL redirectToHost = shouldRedirectOpenURLToHost(url);
    if(openSelf || redirectToHost) {
        NSString* schemeToUse = openSelf ? NSUserDefaults.lcAppUrlScheme : @"livecontainer";
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", schemeToUse, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
@end

@implementation FBSSceneParameters(LiveContainerHook)
- (instancetype)hook_initWithXPCDictionary:(NSDictionary*)dict {

    FBSSceneParameters* ans = [self hook_initWithXPCDictionary:dict];
    UIMutableApplicationSceneSettings* settings = [ans.settings mutableCopy];
    UIMutableApplicationSceneClientSettings* clientSettings = [ans.clientSettings mutableCopy];
    [settings setInterfaceOrientation:LCOrientationLock];
    [clientSettings setInterfaceOrientation:LCOrientationLock];
    ans.settings = settings;
    ans.clientSettings = clientSettings;
    return ans;
}
@end



@implementation UIViewController(LiveContainerHook)

- (UIInterfaceOrientationMask)hook_supportedInterfaceOrientations {
    if(LCOrientationLock == UIInterfaceOrientationLandscapeRight) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }

}

@end

@implementation UIWindow(hook)
- (void)hook_setAutorotates:(BOOL)autorotates forceUpdateInterfaceOrientation:(BOOL)force {
    [self hook_setAutorotates:YES forceUpdateInterfaceOrientation:YES];
}

- (void)hook_makeKeyAndVisible {
    [self updateWindowScene];
    [self hook_makeKeyAndVisible];
}
- (void)hook_makeKeyWindow {
    [self updateWindowScene];
    [self hook_makeKeyWindow];
}
- (void)hook_resignKeyWindow {
    [self updateWindowScene];
    [self hook_resignKeyWindow];
}
- (void)hook_setHidden:(BOOL)hidden {
    [self updateWindowScene];
    [self hook_setHidden:hidden];
}
- (void)updateWindowScene {
    for(UIWindowScene *windowScene in UIApplication.sharedApplication.connectedScenes) {
        if(!self.windowScene && self.screen == windowScene.screen) {
            self.windowScene = windowScene;
            break;
        }
    }
}
@end
@implementation UIPasteboard(hook)

+ (UIPasteboard *)hook_generalPasteboard {
    if(strictTestMode || (spoofProfileEnabled && spoofAppPrivacyCategoryEnabled)) {
        return strictPrivatePasteboard ?: [self hook_generalPasteboard];
    }
    return [self hook_generalPasteboard];
}

@end

@implementation NSURLSessionTask(hook)

- (void)hook_resume {
    if(strictTestMode) {
        [self cancel];
        return;
    }
    [self hook_resume];
}

@end

@implementation NSUserDefaults(LCFingerprintProfile)

- (BOOL)hook_boolForKey:(NSString *)defaultName {
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && [defaultName isEqualToString:@"LDMGlobalEnabled"]) return NO;
    return [self hook_boolForKey:defaultName];
}

@end

static id LCStorageProfileValue(NSURLResourceKey key) {
    if([key isEqualToString:NSURLCreationDateKey]) return [NSDate dateWithTimeIntervalSince1970:1735689600];
    if([key isEqualToString:NSURLVolumeTotalCapacityKey]) return @(spoofStorageTotalCapacity);
    if([key isEqualToString:NSURLVolumeAvailableCapacityKey]) return @(spoofStorageAvailableCapacity);
    if([key isEqualToString:NSURLVolumeAvailableCapacityForImportantUsageKey]) return @(spoofStorageAvailableCapacity);
    if([key isEqualToString:NSURLVolumeAvailableCapacityForOpportunisticUsageKey]) return @(spoofStorageAvailableCapacity);
    if([key isEqualToString:NSURLVolumeCreationDateKey]) return [NSDate dateWithTimeIntervalSince1970:1704067200];
    if([key isEqualToString:NSURLVolumeUUIDStringKey]) return @"00000000-0000-0000-0000-000000000000";
    if([key isEqualToString:NSURLVolumeNameKey] || [key isEqualToString:NSURLVolumeLocalizedNameKey]) return @"Data";
    return nil;
}

@implementation NSURL(LCFingerprintProfile)

- (NSDictionary<NSURLResourceKey, id> *)hook_resourceValuesForKeys:(NSArray<NSURLResourceKey> *)keys error:(NSError **)error {
    NSDictionary *original = [self hook_resourceValuesForKeys:keys error:error];
    if(!spoofProfileEnabled || !spoofStorageCategoryEnabled) return original;
    NSMutableDictionary *values = original ? [original mutableCopy] : [NSMutableDictionary dictionary];
    for(NSURLResourceKey key in keys) {
        id replacement = LCStorageProfileValue(key);
        if(replacement) values[key] = replacement;
    }
    return values;
}

- (BOOL)hook_getResourceValue:(out id _Nullable *)value forKey:(NSURLResourceKey)key error:(NSError **)error {
    if(spoofProfileEnabled && spoofStorageCategoryEnabled) {
        id replacement = LCStorageProfileValue(key);
        if(replacement) {
            if(value) *value = replacement;
            return YES;
        }
    }
    return [self hook_getResourceValue:value forKey:key error:error];
}

@end

@implementation NSFileManager(LCFingerprintProfile)

- (id)hook_ubiquityIdentityToken {
    if(spoofProfileEnabled && spoofAppPrivacyCategoryEnabled) return nil;
    return [self hook_ubiquityIdentityToken];
}

@end

@implementation WKWebView(LCFingerprintProfile)

- (instancetype)hook_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    NSString *profileScript = nil;
    if(spoofProfileEnabled && spoofWebViewCategoryEnabled) {
        profileScript = LCWebViewProfileScript();
        WKUserScript *script = [[WKUserScript alloc] initWithSource:profileScript
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart
            forMainFrameOnly:NO];
        [configuration.userContentController addUserScript:script];
        if(spoofSystemVersion.length > 0) configuration.applicationNameForUserAgent = @"Mobile/15E148";
    }
    WKWebView *webView = [self hook_initWithFrame:frame configuration:configuration];
    if(profileScript.length > 0) {
        [webView evaluateJavaScript:profileScript completionHandler:nil];
    }
    return webView;
}

@end

@implementation UIDevice(hook)

- (NSUUID*)hook_identifierForVendor {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(spoofIdentityCategoryEnabled && idForVendorUUID) {
        return idForVendorUUID;
    }
    return [self hook_identifierForVendor];
}

- (NSString *)hook_name {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofIdentityCategoryEnabled && spoofDeviceName.length > 0) {
        return spoofDeviceName;
    }
    return [self hook_name];
}

- (NSString *)hook_model {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofIdentityCategoryEnabled && spoofDeviceModel.length > 0) {
        return spoofDeviceModel;
    }
    return [self hook_model];
}

- (NSString *)hook_localizedModel {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofIdentityCategoryEnabled && spoofDeviceModel.length > 0) {
        return spoofDeviceModel;
    }
    return [self hook_localizedModel];
}

- (NSString *)hook_systemName {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofSystemName.length > 0) {
        return spoofSystemName;
    }
    return [self hook_systemName];
}

- (NSString *)hook_systemVersion {
    if(blockDeviceInfoReads) {
        return @"0.0";
    }
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofSystemVersion.length > 0) {
        return spoofSystemVersion;
    }
    return [self hook_systemVersion];
}

- (float)hook_batteryLevel {
    if(blockDeviceInfoReads) {
        return -1.0f;
    }
    if(spoofProfileEnabled && spoofBatteryCategoryEnabled && spoofBatteryLevel >= 0.0f) {
        return spoofBatteryLevel;
    }
    return [self hook_batteryLevel];
}

- (UIDeviceBatteryState)hook_batteryState {
    if(blockDeviceInfoReads) {
        return UIDeviceBatteryStateUnknown;
    }
    if(spoofProfileEnabled && spoofBatteryCategoryEnabled && spoofBatteryState >= UIDeviceBatteryStateUnknown && spoofBatteryState <= UIDeviceBatteryStateFull) {
        return (UIDeviceBatteryState)spoofBatteryState;
    }
    return [self hook_batteryState];
}

- (BOOL)hook_isBatteryMonitoringEnabled {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofBatteryCategoryEnabled && (spoofBatteryLevel >= 0.0f || spoofBatteryState != UIDeviceBatteryStateUnknown)) {
        return YES;
    }
    return [self hook_isBatteryMonitoringEnabled];
}

@end

@implementation NSProcessInfo(hook)

- (NSOperatingSystemVersion)hook_operatingSystemVersion {
    if(blockDeviceInfoReads) {
        return (NSOperatingSystemVersion){ .majorVersion = 0, .minorVersion = 0, .patchVersion = 0 };
    }
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofOperatingSystemVersionValid) {
        return spoofOperatingSystemVersion;
    }
    return [self hook_operatingSystemVersion];
}

- (NSString *)hook_operatingSystemVersionString {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofSystemVersion.length > 0) {
        NSString *name = spoofSystemName.length > 0 ? spoofSystemName : @"iOS";
        return [NSString stringWithFormat:@"%@ %@", name, spoofSystemVersion];
    }
    return [self hook_operatingSystemVersionString];
}

- (BOOL)hook_isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofOperatingSystemVersionValid) {
        return LCCompareOSVersion(spoofOperatingSystemVersion, version) >= 0;
    }
    return [self hook_isOperatingSystemAtLeastVersion:version];
}

- (BOOL)hook_isLowPowerModeEnabled {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofBatteryCategoryEnabled && spoofLowPowerModeEnabledSet) {
        return spoofLowPowerModeEnabled;
    }
    return [self hook_isLowPowerModeEnabled];
}

- (NSUInteger)hook_processorCount {
    if(blockDeviceInfoReads) return 1;
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofProcessorCount > 0) return spoofProcessorCount;
    return [self hook_processorCount];
}

- (NSUInteger)hook_activeProcessorCount {
    if(blockDeviceInfoReads) return 1;
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofProcessorCount > 0) return spoofProcessorCount;
    return [self hook_activeProcessorCount];
}

- (unsigned long long)hook_physicalMemory {
    if(blockDeviceInfoReads) return 0;
    if(spoofProfileEnabled && spoofSystemCategoryEnabled && spoofPhysicalMemory > 0) return spoofPhysicalMemory;
    return [self hook_physicalMemory];
}

- (NSProcessInfoThermalState)hook_thermalState {
    if(blockDeviceInfoReads) return NSProcessInfoThermalStateNominal;
    if(spoofProfileEnabled && spoofBatteryCategoryEnabled && spoofThermalState >= NSProcessInfoThermalStateNominal &&
       spoofThermalState <= NSProcessInfoThermalStateCritical) {
        return (NSProcessInfoThermalState)spoofThermalState;
    }
    return [self hook_thermalState];
}

@end

// MARK: - System & Display Profile: screen fingerprint

@implementation UIScreen(LCSystemDisplayProfile)

- (CGRect)hook_nativeBounds {
    if(blockDeviceInfoReads) return CGRectMake(0, 0, 1, 1);
    CGRect bounds = [self hook_nativeBounds];
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofScreenWidth > 0) bounds.size.width = spoofScreenWidth;
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofScreenHeight > 0) bounds.size.height = spoofScreenHeight;
    return bounds;
}

- (CGFloat)hook_scale {
    if(blockDeviceInfoReads) return 1;
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofScreenScale > 0) return spoofScreenScale;
    return [self hook_scale];
}

- (CGFloat)hook_nativeScale {
    if(blockDeviceInfoReads) return 1;
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofScreenNativeScale > 0) return spoofScreenNativeScale;
    return [self hook_nativeScale];
}

- (NSInteger)hook_maximumFramesPerSecond {
    if(blockDeviceInfoReads) return 60;
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofMaximumFramesPerSecond > 0) return spoofMaximumFramesPerSecond;
    return [self hook_maximumFramesPerSecond];
}

- (CGFloat)hook_brightness {
    if(blockDeviceInfoReads) return 0.5;
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofScreenBrightness >= 0) return spoofScreenBrightness;
    return [self hook_brightness];
}

@end

@implementation UITraitCollection(LCFingerprintProfile)

- (UIDisplayGamut)hook_displayGamut {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled) return (UIDisplayGamut)spoofDisplayGamut;
    return [self hook_displayGamut];
}

- (UIUserInterfaceSizeClass)hook_horizontalSizeClass {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled) return (UIUserInterfaceSizeClass)spoofHorizontalSizeClass;
    return [self hook_horizontalSizeClass];
}

- (UIUserInterfaceSizeClass)hook_verticalSizeClass {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled) return (UIUserInterfaceSizeClass)spoofVerticalSizeClass;
    return [self hook_verticalSizeClass];
}

- (UIContentSizeCategory)hook_preferredContentSizeCategory {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled) {
        return spoofPreferredContentSizeCategory ?: UIContentSizeCategoryLarge;
    }
    return [self hook_preferredContentSizeCategory];
}

- (UIUserInterfaceStyle)hook_userInterfaceStyle {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled && spoofUserInterfaceStyle != UIUserInterfaceStyleUnspecified) {
        return (UIUserInterfaceStyle)spoofUserInterfaceStyle;
    }
    return [self hook_userInterfaceStyle];
}

- (UIAccessibilityContrast)hook_accessibilityContrast {
    if(spoofProfileEnabled && spoofAccessibilityCategoryEnabled) return (UIAccessibilityContrast)spoofAccessibilityContrast;
    return [self hook_accessibilityContrast];
}

@end

@implementation UIWindow(LCFingerprintProfile)

- (UIEdgeInsets)hook_safeAreaInsets {
    if(spoofProfileEnabled && spoofDisplayCategoryEnabled) {
        return spoofSafeAreaInsets;
    }
    return [self hook_safeAreaInsets];
}

@end

@implementation NSLocale(hook)

+ (NSLocale *)hook_currentLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_currentLocale];
}

+ (NSLocale *)hook_autoupdatingCurrentLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_autoupdatingCurrentLocale];
}

+ (NSLocale *)hook_systemLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_systemLocale];
}

+ (NSArray<NSString *> *)hook_preferredLanguages {
    if(blockDeviceInfoReads) {
        return @[@"und"];
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofLocale) {
        NSString *languageIdentifier = [spoofLocale objectForKey:NSLocaleIdentifier];
        if(languageIdentifier.length > 0) {
            return @[languageIdentifier];
        }
    }
    return [self hook_preferredLanguages];
}

@end

@implementation NSTimeZone(hook)

+ (NSTimeZone *)hook_localTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_localTimeZone];
}

+ (NSTimeZone *)hook_systemTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_systemTimeZone];
}

+ (NSTimeZone *)hook_defaultTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_defaultTimeZone];
}

+ (NSTimeZone *)hook_autoupdatingCurrentTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_autoupdatingCurrentTimeZone];
}

@end

@implementation NSCalendar(hook)

+ (NSCalendar *)hook_currentCalendar {
    if(blockDeviceInfoReads) {
        return LCCalendarForProfile(LCBlockedTimeZone());
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && (spoofLocale || spoofTimeZone)) {
        return LCCalendarForProfile(spoofTimeZone);
    }
    return [self hook_currentCalendar];
}

+ (NSCalendar *)hook_autoupdatingCurrentCalendar {
    if(blockDeviceInfoReads) {
        return LCCalendarForProfile(LCBlockedTimeZone());
    }
    if(spoofProfileEnabled && spoofLocaleCategoryEnabled && (spoofLocale || spoofTimeZone)) {
        return LCCalendarForProfile(spoofTimeZone);
    }
    return [self hook_autoupdatingCurrentCalendar];
}

@end

@implementation LCTelephonyNetworkInfoHookProvider

- (id)hook_serviceCurrentRadioAccessTechnology {
    if(blockDeviceInfoReads) {
        return @{};
    }
    if(spoofProfileEnabled && spoofTelephonyCategoryEnabled && spoofRadioAccessTechnology.length > 0) {
        return @{
            @"0000000100000001": spoofRadioAccessTechnology
        };
    }
    return [self hook_serviceCurrentRadioAccessTechnology];
}

@end

@implementation LCSubscriberHookProvider

- (id)hook_identifier {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(spoofProfileEnabled && spoofTelephonyCategoryEnabled && spoofSubscriberIdentifier.length > 0) {
        return spoofSubscriberIdentifier;
    }
    return [self hook_identifier];
}

- (id)hook_carrierToken {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(spoofProfileEnabled && spoofTelephonyCategoryEnabled && spoofSubscriberCarrierToken) {
        return spoofSubscriberCarrierToken;
    }
    return [self hook_carrierToken];
}

- (BOOL)hook_isSIMInserted {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofTelephonyCategoryEnabled && spoofSubscriberSIMInsertedEnabled) {
        return spoofSubscriberSIMInserted;
    }
    return [self hook_isSIMInserted];
}

@end

@implementation LCSubscriberInfoHookProvider

+ (id)hook_subscribers {
    if(blockDeviceInfoReads) {
        return @[];
    }
    return [self hook_subscribers];
}

@end

@implementation LCNetworkExtensionStrictHookProvider

+ (void)hook_fetchCurrentWithCompletionHandler:(void (^)(id currentNetwork))completionHandler {
    if(strictTestMode) {
        if(completionHandler) {
            completionHandler(nil);
        }
        return;
    }
    [self hook_fetchCurrentWithCompletionHandler:completionHandler];
}

@end
