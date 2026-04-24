@import UIKit;
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "Localization.h"

UIInterfaceOrientation LCOrientationLock = UIInterfaceOrientationUnknown;
NSMutableArray<NSString*>* LCSupportedUrlSchemes = nil;
NSUUID* idForVendorUUID = nil;
BOOL spoofProfileEnabled = NO;
BOOL blockDeviceInfoReads = NO;
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
NSString *spoofCarrierName = nil;
NSString *spoofMobileCountryCode = nil;
NSString *spoofMobileNetworkCode = nil;
NSString *spoofISOCountryCode = nil;
NSString *spoofRadioAccessTechnology = nil;

@interface CTTelephonyNetworkInfo : NSObject
@end

@interface LCSpoofCarrier : NSObject
@end

@implementation LCSpoofCarrier
- (NSString *)carrierName { return spoofCarrierName; }
- (NSString *)mobileCountryCode { return spoofMobileCountryCode; }
- (NSString *)mobileNetworkCode { return spoofMobileNetworkCode; }
- (NSString *)isoCountryCode { return spoofISOCountryCode; }
- (BOOL)allowsVOIP { return YES; }
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

__attribute__((constructor))
static void UIKitGuestHooksInit(void) {
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
            swizzle(UIViewController.class, @selector(__supportedInterfaceOrientations), @selector(hook___supportedInterfaceOrientations));
            swizzle(UIViewController.class, @selector(shouldAutorotateToInterfaceOrientation:), @selector(hook_shouldAutorotateToInterfaceOrientation:));
            swizzle(UIWindow.class, @selector(setAutorotates:forceUpdateInterfaceOrientation:), @selector(hook_setAutorotates:forceUpdateInterfaceOrientation:));
        }

    }
    NSDictionary* guestContainerInfo = [NSUserDefaults guestContainerInfo];
    blockDeviceInfoReads = [guestContainerInfo[@"blockDeviceInfoReads"] boolValue];

    BOOL shouldSpoofIdentifierForVendor = [guestContainerInfo[@"spoofIdentifierForVendor"] boolValue];
    if(shouldSpoofIdentifierForVendor) {
        NSString* idForVendorStr = guestContainerInfo[@"spoofedIdentifierForVendor"];
        if([idForVendorStr isKindOfClass:NSString.class]) {
            idForVendorUUID = [[NSUUID UUID] initWithUUIDString:idForVendorStr];
        }
    }
    if(blockDeviceInfoReads || (shouldSpoofIdentifierForVendor && idForVendorUUID != nil)) {
        swizzle(UIDevice.class, @selector(identifierForVendor), @selector(hook_identifierForVendor));
    }

    if([guestContainerInfo[@"spoofProfileEnabled"] boolValue]) {
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
        NSString *carrierName = guestContainerInfo[@"spoofCarrierName"];
        NSString *mobileCountryCode = guestContainerInfo[@"spoofMobileCountryCode"];
        NSString *mobileNetworkCode = guestContainerInfo[@"spoofMobileNetworkCode"];
        NSString *isoCountryCode = guestContainerInfo[@"spoofISOCountryCode"];
        NSString *radioAccessTechnology = guestContainerInfo[@"spoofRadioAccessTechnology"];

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
                if(!blockDeviceInfoReads) {
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
        if([carrierName isKindOfClass:NSString.class] && carrierName.length > 0) {
            spoofCarrierName = carrierName;
        }
        if([mobileCountryCode isKindOfClass:NSString.class] && mobileCountryCode.length > 0) {
            spoofMobileCountryCode = mobileCountryCode;
        }
        if([mobileNetworkCode isKindOfClass:NSString.class] && mobileNetworkCode.length > 0) {
            spoofMobileNetworkCode = mobileNetworkCode;
        }
        if([isoCountryCode isKindOfClass:NSString.class] && isoCountryCode.length > 0) {
            spoofISOCountryCode = isoCountryCode.lowercaseString;
        }
        if([radioAccessTechnology isKindOfClass:NSString.class] && radioAccessTechnology.length > 0) {
            spoofRadioAccessTechnology = radioAccessTechnology;
        }

    }

    if(blockDeviceInfoReads || spoofDeviceName || spoofDeviceModel || spoofSystemName || spoofSystemVersion) {
        swizzle(UIDevice.class, @selector(name), @selector(hook_name));
        swizzle(UIDevice.class, @selector(model), @selector(hook_model));
        swizzle(UIDevice.class, @selector(localizedModel), @selector(hook_localizedModel));
        swizzle(UIDevice.class, @selector(systemName), @selector(hook_systemName));
        swizzle(UIDevice.class, @selector(systemVersion), @selector(hook_systemVersion));
    }
    if(blockDeviceInfoReads || spoofBatteryLevel >= 0.0f || spoofBatteryState != UIDeviceBatteryStateUnknown) {
        swizzle(UIDevice.class, @selector(batteryLevel), @selector(hook_batteryLevel));
        swizzle(UIDevice.class, @selector(batteryState), @selector(hook_batteryState));
        swizzle(UIDevice.class, @selector(isBatteryMonitoringEnabled), @selector(hook_isBatteryMonitoringEnabled));
    }
    if(blockDeviceInfoReads || spoofOperatingSystemVersionValid || spoofSystemVersion) {
        swizzle(NSProcessInfo.class, @selector(operatingSystemVersion), @selector(hook_operatingSystemVersion));
        swizzle(NSProcessInfo.class, @selector(operatingSystemVersionString), @selector(hook_operatingSystemVersionString));
        swizzle(NSProcessInfo.class, @selector(isOperatingSystemAtLeastVersion:), @selector(hook_isOperatingSystemAtLeastVersion:));
    }
    if(blockDeviceInfoReads || spoofLowPowerModeEnabledSet) {
        swizzle(NSProcessInfo.class, @selector(isLowPowerModeEnabled), @selector(hook_isLowPowerModeEnabled));
    }
    if(blockDeviceInfoReads || spoofLocale) {
        LCSwizzleClassIfPresent(NSLocale.class, @selector(currentLocale), @selector(hook_currentLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(autoupdatingCurrentLocale), @selector(hook_autoupdatingCurrentLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(systemLocale), @selector(hook_systemLocale));
        LCSwizzleClassIfPresent(NSLocale.class, @selector(preferredLanguages), @selector(hook_preferredLanguages));
    }
    if(blockDeviceInfoReads || spoofTimeZone) {
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(localTimeZone), @selector(hook_localTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(systemTimeZone), @selector(hook_systemTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(defaultTimeZone), @selector(hook_defaultTimeZone));
        LCSwizzleClassIfPresent(NSTimeZone.class, @selector(autoupdatingCurrentTimeZone), @selector(hook_autoupdatingCurrentTimeZone));
        LCSwizzleClassIfPresent(NSCalendar.class, @selector(currentCalendar), @selector(hook_currentCalendar));
        LCSwizzleClassIfPresent(NSCalendar.class, @selector(autoupdatingCurrentCalendar), @selector(hook_autoupdatingCurrentCalendar));
    }
    if(blockDeviceInfoReads || spoofCarrierName || spoofMobileCountryCode || spoofMobileNetworkCode || spoofISOCountryCode || spoofRadioAccessTechnology) {
        Class telephonyClass = NSClassFromString(@"CTTelephonyNetworkInfo");
        LCSwizzleIfPresent(telephonyClass, @selector(subscriberCellularProvider), @selector(hook_subscriberCellularProvider));
        LCSwizzleIfPresent(telephonyClass, @selector(serviceSubscriberCellularProviders), @selector(hook_serviceSubscriberCellularProviders));
        LCSwizzleIfPresent(telephonyClass, @selector(currentRadioAccessTechnology), @selector(hook_currentRadioAccessTechnology));
        LCSwizzleIfPresent(telephonyClass, @selector(serviceCurrentRadioAccessTechnology), @selector(hook_serviceCurrentRadioAccessTechnology));
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
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
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
    window.windowLevel = LCOverlayWindowLevel();
    window.windowScene = LCForegroundWindowScene();
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void LCShowAlert(NSString* message) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = LCOverlayWindowLevel();
    window.windowScene = LCForegroundWindowScene();
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
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
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
    window.windowLevel = LCOverlayWindowLevel();
    window.windowScene = LCForegroundWindowScene();
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
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
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
    window.windowLevel = LCOverlayWindowLevel();
    window.windowScene = LCForegroundWindowScene();
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

void handleLiveContainerLaunch(NSURL* url) {
    // If it's not current app, then switch
    // check if there are other LCs is running this app
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
        return;
    }
    
    NSString* containerId = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
    if(!containerFolderName) {
        containerFolderName = findDefaultContainerWithBundleId(bundleName);
    }
    if ([bundleName isEqualToString:NSBundle.mainBundle.bundlePath.lastPathComponent] && [containerId isEqualToString:containerFolderName]) {
        if(openUrl) {
            openUniversalLink(openUrl);
        }
    } else {
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

// Handler for AppDelegate
@implementation UIApplication(LiveContainerHook)
- (void)hook__applicationOpenURLAction:(id)action payload:(NSDictionary *)payload origin:(id)origin {
    NSString *url = payload[UIApplicationLaunchOptionsURLKey];
    if ([url hasPrefix:@"file:"]) {
        [[NSURL URLWithString:url] startAccessingSecurityScopedResource];
        [self hook__applicationOpenURLAction:action payload:payload origin:origin];
        return;
    }
    
    if([url hasPrefix:@"sidestore:"]) {
        LCOpenSideStoreURL([NSURL URLWithString:url]);
        return;
    }
    
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-relaunch", NSUserDefaults.lcAppUrlScheme]]) {
        // Ignore
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.lcAppUrlScheme]]) {
        // launch to UI and open web page
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl, url);
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
        // pass url to guest app
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableDictionary* newPayload = [payload mutableCopy];
            newPayload[UIApplicationLaunchOptionsURLKey] = decodedUrl;
            [self hook__applicationOpenURLAction:action payload:newPayload origin:origin];
        }
        
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-launch?bundle-name=", NSUserDefaults.lcAppUrlScheme]]) {
        handleLiveContainerLaunch([NSURL URLWithString:url]);
        // Not what we're looking for, pass it
        
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://install", NSUserDefaults.lcAppUrlScheme]]) {
        LCShowAlert(@"lc.guestTweak.restartToInstall".loc);
        return;
    }
    [self hook__applicationOpenURLAction:action payload:payload origin:origin];
    return;
}

- (void)hook__connectUISceneFromFBSScene:(id)scene transitionContext:(UIApplicationSceneTransitionContext*)context {
#if !TARGET_OS_MACCATALYST
    NSString* urlStr;
    if(context.payload && (urlStr = context.payload[UIApplicationLaunchOptionsURLKey])) {
        BOOL urlDecodeSuccess = NO;
        do {
            if([urlStr hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
                NSURLComponents* lcUrl = [NSURLComponents componentsWithString:urlStr];
                NSString* realUrlEncoded = lcUrl.queryItems[0].value;
                if(!realUrlEncoded) break;
                // Convert the base64 encoded url into String
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
                NSString *decodedUrlStr = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                NSURL* decodedUrl = [NSURL URLWithString:decodedUrlStr];
                if(!canAppOpenItself(decodedUrl)) {
                    break;
                }
                urlDecodeSuccess = YES;
                
                NSMutableDictionary* newDict = [context.payload mutableCopy];
                newDict[UIApplicationLaunchOptionsURLKey] = decodedUrl;
                context.payload = newDict;
                
                if(context.actions) {
                    UIOpenURLAction *urlAction = nil;
                    for (id obj in context.actions.allObjects) {
                        if ([obj isKindOfClass:UIOpenURLAction.class]) {
                            urlAction = obj;
                            break;
                        }
                    }
                    if(!urlAction) {
                        break;
                    }
                    NSMutableSet *newActions = context.actions.mutableCopy;
                    [newActions removeObject:urlAction];

                    UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:decodedUrl];
                    [newActions addObject:newUrlAction];
                    context.actions = newActions;
                }

            }
        } while(0);

        if(!urlDecodeSuccess) {
            context.payload = nil;
            context.actions = nil;
        }
    }
    
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
    return canAppOpenItself(url) || shouldRedirectOpenURLToHost(url) || [self hook_canOpenURL:url];
}

- (void)hook_setDelegate:(id<UIApplicationDelegate>)delegate {
    if(![delegate respondsToSelector:@selector(application:configurationForConnectingSceneSession:options:)]) {
        // Fix old apps black screen when UIApplicationSupportsMultipleScenes is YES
        swizzle(UIWindow.class, @selector(makeKeyAndVisible), @selector(hook_makeKeyAndVisible));
        swizzle(UIWindow.class, @selector(makeKeyWindow), @selector(hook_makeKeyWindow));
        swizzle(UIWindow.class, @selector(setHidden:), @selector(hook_setHidden:));
        // Fix apps that do not support UISceneDelegate getting 0 status bar frame
        swizzle(UIApplication.class, @selector(statusBarFrame), @selector(hook_statusBarFrame));
    }
    [self hook_setDelegate:delegate];
}

+ (BOOL)_wantsApplicationBehaviorAsExtension {
    // Fix LiveProcess: Make _UIApplicationWantsExtensionBehavior return NO so delegate code runs in the run loop
    return YES;
}

- (CGRect)hook_statusBarFrame {
    UIStatusBarManager* manager = [(UIWindowScene*)(UIApplication.sharedApplication.connectedScenes.anyObject) statusBarManager];
    if(manager) {
        return manager.statusBarFrame;
    } else {
        return [self hook_statusBarFrame];
    }
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

    // Don't have UIOpenURLAction or is passing a file to app? pass it
    if (!urlAction || urlAction.url.isFileURL || (NSUserDefaults.isSideStore && ![urlAction.url.scheme isEqualToString:@"livecontainer"])) {
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }
    
    if (urlAction.url.isFileURL) {
        [urlAction.url startAccessingSecurityScopedResource];
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }
    
    if([urlAction.url.scheme isEqualToString:@"sidestore"]) {
        LCOpenSideStoreURL(urlAction.url);
        return;
    }

    NSString *url = urlAction.url.absoluteString;
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-relaunch", NSUserDefaults.lcAppUrlScheme]]) {
        // Ignore
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.lcAppUrlScheme]]) {
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // launch to UI and open web page
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl, url);
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
        // Open guest app's URL scheme
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableSet *newActions = actions.mutableCopy;
            [newActions removeObject:urlAction];
            NSURL* finalURL = [NSURL URLWithString:decodedUrl];
            if(finalURL) {
                UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:finalURL];
                [newActions addObject:newUrlAction];
                [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
            }
        }

    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-launch?bundle-name=", NSUserDefaults.lcAppUrlScheme]]){
        handleLiveContainerLaunch(urlAction.url);
        
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://install", NSUserDefaults.lcAppUrlScheme]]) {
        LCShowAlert(@"lc.guestTweak.restartToInstall".loc);
        return;
    }
    
    if ([urlAction.url.scheme isEqualToString:NSUserDefaults.lcAppUrlScheme]) {
        NSMutableSet *newActions = actions.mutableCopy;
        [newActions removeObject:urlAction];
        actions = newActions;
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

- (UIInterfaceOrientationMask)hook___supportedInterfaceOrientations {
    if(LCOrientationLock == UIInterfaceOrientationLandscapeRight) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }

}

- (BOOL)hook_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation {
    return YES;
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

@implementation UIDevice(hook)

- (NSUUID*)hook_identifierForVendor {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(idForVendorUUID) {
        return idForVendorUUID;
    }
    return [self hook_identifierForVendor];
}

- (NSString *)hook_name {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofDeviceName.length > 0) {
        return spoofDeviceName;
    }
    return [self hook_name];
}

- (NSString *)hook_model {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofDeviceModel.length > 0) {
        return spoofDeviceModel;
    }
    return [self hook_model];
}

- (NSString *)hook_localizedModel {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofDeviceModel.length > 0) {
        return spoofDeviceModel;
    }
    return [self hook_localizedModel];
}

- (NSString *)hook_systemName {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofSystemName.length > 0) {
        return spoofSystemName;
    }
    return [self hook_systemName];
}

- (NSString *)hook_systemVersion {
    if(blockDeviceInfoReads) {
        return @"0.0";
    }
    if(spoofProfileEnabled && spoofSystemVersion.length > 0) {
        return spoofSystemVersion;
    }
    return [self hook_systemVersion];
}

- (float)hook_batteryLevel {
    if(blockDeviceInfoReads) {
        return -1.0f;
    }
    if(spoofProfileEnabled && spoofBatteryLevel >= 0.0f) {
        return spoofBatteryLevel;
    }
    return [self hook_batteryLevel];
}

- (UIDeviceBatteryState)hook_batteryState {
    if(blockDeviceInfoReads) {
        return UIDeviceBatteryStateUnknown;
    }
    if(spoofProfileEnabled && spoofBatteryState >= UIDeviceBatteryStateUnknown && spoofBatteryState <= UIDeviceBatteryStateFull) {
        return (UIDeviceBatteryState)spoofBatteryState;
    }
    return [self hook_batteryState];
}

- (BOOL)hook_isBatteryMonitoringEnabled {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && (spoofBatteryLevel >= 0.0f || spoofBatteryState != UIDeviceBatteryStateUnknown)) {
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
    if(spoofProfileEnabled && spoofOperatingSystemVersionValid) {
        return spoofOperatingSystemVersion;
    }
    return [self hook_operatingSystemVersion];
}

- (NSString *)hook_operatingSystemVersionString {
    if(blockDeviceInfoReads) {
        return @"Unknown";
    }
    if(spoofProfileEnabled && spoofSystemVersion.length > 0) {
        NSString *name = spoofSystemName.length > 0 ? spoofSystemName : @"iOS";
        return [NSString stringWithFormat:@"%@ %@", name, spoofSystemVersion];
    }
    return [self hook_operatingSystemVersionString];
}

- (BOOL)hook_isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofOperatingSystemVersionValid) {
        return LCCompareOSVersion(spoofOperatingSystemVersion, version) >= 0;
    }
    return [self hook_isOperatingSystemAtLeastVersion:version];
}

- (BOOL)hook_isLowPowerModeEnabled {
    if(blockDeviceInfoReads) {
        return NO;
    }
    if(spoofProfileEnabled && spoofLowPowerModeEnabledSet) {
        return spoofLowPowerModeEnabled;
    }
    return [self hook_isLowPowerModeEnabled];
}

@end

@implementation NSLocale(hook)

+ (NSLocale *)hook_currentLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_currentLocale];
}

+ (NSLocale *)hook_autoupdatingCurrentLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_autoupdatingCurrentLocale];
}

+ (NSLocale *)hook_systemLocale {
    if(blockDeviceInfoReads) {
        return LCBlockedLocale();
    }
    if(spoofProfileEnabled && spoofLocale) {
        return spoofLocale;
    }
    return [self hook_systemLocale];
}

+ (NSArray<NSString *> *)hook_preferredLanguages {
    if(blockDeviceInfoReads) {
        return @[@"und"];
    }
    if(spoofProfileEnabled && spoofLocale) {
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
    if(spoofProfileEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_localTimeZone];
}

+ (NSTimeZone *)hook_systemTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_systemTimeZone];
}

+ (NSTimeZone *)hook_defaultTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_defaultTimeZone];
}

+ (NSTimeZone *)hook_autoupdatingCurrentTimeZone {
    if(blockDeviceInfoReads) {
        return LCBlockedTimeZone();
    }
    if(spoofProfileEnabled && spoofTimeZone) {
        return spoofTimeZone;
    }
    return [self hook_autoupdatingCurrentTimeZone];
}

@end

@implementation NSCalendar(hook)

+ (NSCalendar *)hook_currentCalendar {
    if(blockDeviceInfoReads) {
        NSCalendar *calendar = [self hook_currentCalendar];
        calendar.timeZone = LCBlockedTimeZone();
        return calendar;
    }
    if(spoofProfileEnabled && spoofTimeZone) {
        NSCalendar *calendar = [self hook_currentCalendar];
        calendar.timeZone = spoofTimeZone;
        return calendar;
    }
    return [self hook_currentCalendar];
}

+ (NSCalendar *)hook_autoupdatingCurrentCalendar {
    if(blockDeviceInfoReads) {
        NSCalendar *calendar = [self hook_autoupdatingCurrentCalendar];
        calendar.timeZone = LCBlockedTimeZone();
        return calendar;
    }
    if(spoofProfileEnabled && spoofTimeZone) {
        NSCalendar *calendar = [self hook_autoupdatingCurrentCalendar];
        calendar.timeZone = spoofTimeZone;
        return calendar;
    }
    return [self hook_autoupdatingCurrentCalendar];
}

@end

@implementation CTTelephonyNetworkInfo(hook)

- (id)hook_subscriberCellularProvider {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(spoofProfileEnabled && (spoofCarrierName || spoofMobileCountryCode || spoofMobileNetworkCode || spoofISOCountryCode)) {
        return [LCSpoofCarrier new];
    }
    return [self hook_subscriberCellularProvider];
}

- (id)hook_serviceSubscriberCellularProviders {
    if(blockDeviceInfoReads) {
        return @{};
    }
    if(spoofProfileEnabled && (spoofCarrierName || spoofMobileCountryCode || spoofMobileNetworkCode || spoofISOCountryCode)) {
        return @{
            @"0000000100000001": [LCSpoofCarrier new]
        };
    }
    return [self hook_serviceSubscriberCellularProviders];
}

- (id)hook_currentRadioAccessTechnology {
    if(blockDeviceInfoReads) {
        return nil;
    }
    if(spoofProfileEnabled && spoofRadioAccessTechnology.length > 0) {
        return spoofRadioAccessTechnology;
    }
    return [self hook_currentRadioAccessTechnology];
}

- (id)hook_serviceCurrentRadioAccessTechnology {
    if(blockDeviceInfoReads) {
        return @{};
    }
    if(spoofProfileEnabled && spoofRadioAccessTechnology.length > 0) {
        return @{
            @"0000000100000001": spoofRadioAccessTechnology
        };
    }
    return [self hook_serviceCurrentRadioAccessTechnology];
}

@end
