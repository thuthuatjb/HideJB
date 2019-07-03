
#import <version.h>
#import "../Classes/HideJBTweak.h"

%group UptoiOS11
%hook BSLaunchdUtilities
+ (BOOL)createJobWithLabel:(NSString *)jobLabel bundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path containerPath:(NSString *)containerPath arguments:(NSArray<NSString *> *)arguments environment:(NSMutableDictionary *)environment standardOutputPath:(NSString *)standardOutputPath standardErrorPath:(NSString *)standardErrorPath machServices:(NSArray<NSString *> *)machServices threadPriority:(NSInteger)threadPriority waitForDebugger:(BOOL)waitForDebugger denyCreatingOtherJobs:(BOOL)denyCreatingOtherJobs runAtLoad:(BOOL)runAtLoad disableASLR:(BOOL)disableASLR systemApp:(BOOL)systemApp {    
    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    NSString *currentBundleIdentifier = [tweak currentBundleIdentifier];

    if (!currentBundleIdentifier) {
        HideJBLog(@"currentBundleIdentifier is nil, HideJB shortcut was not invoked");
        return %orig();
    }

    if (![currentBundleIdentifier isEqualToString:bundleIdentifier]) {
        HideJBLogFormat(@"currentBundleIdentifier does not match app being launched, currentBundleIdentifier: %@ vs %@", currentBundleIdentifier, bundleIdentifier);
        return %orig();
    }

    [tweak setCurrentBundleIdentifier:nil];

    BOOL environmentShouldBeReleased = NO;
    if (![environment isKindOfClass:%c(NSMutableDictionary)]) {
        environment = [environment mutableCopy];
        environmentShouldBeReleased = YES;
    }

    [environment setObject:[tweak safeModeNumber] forKey:@"_MSSafeMode"];
    HideJBLogFormat(@"Resulting environment for app launched with HideJB: %@", environment);

    BOOL result = %orig();
    if (environmentShouldBeReleased) {
        [environment release];
    }

    return result;
}
%end
%end

%ctor {
    if (IS_IOS_OR_OLDER(iOS_10_3)) {
        %init(UptoiOS11);
    }
}
