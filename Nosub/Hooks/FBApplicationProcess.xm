

#import <version.h>
#import "../Classes/HideJBTweak.h"

#import "../Headers/FrontBoard/FBMutableProcessExecutionContext.h"
#import "../Headers/FrontBoard/FBApplicationProcess.h"

%group iOS11Up
%hook FBApplicationProcess
- (BOOL)_queue_bootstrapAndExecWithContext:(FBMutableProcessExecutionContext *)context {
    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    NSString *currentBundleIdentifier = [tweak currentBundleIdentifier];

    if (!currentBundleIdentifier) {
        HideJBLog(@"currentBundleIdentifier is nil, HideJB shortcut was not invoked");
        return %orig();
    }

    FBApplicationInfo *applicationInfo = [self applicationInfo];
    NSString *bundleIdentifier = MSHookIvar<NSString *>(applicationInfo, "_bundleIdentifier");

    if (![currentBundleIdentifier isEqualToString:bundleIdentifier]) {
        HideJBLogFormat(@"currentBundleIdentifier does not match app being launched, currentBundleIdentifier: %@ vs %@", currentBundleIdentifier, bundleIdentifier);
        return %orig();
    }

    [tweak setCurrentBundleIdentifier:nil];

    NSDictionary *environment = [context environment];
    NSMutableDictionary *mutableEnvironment = [environment mutableCopy];

    [mutableEnvironment setObject:[tweak safeModeNumber] forKey:@"_MSSafeMode"];
    [context setEnvironment:mutableEnvironment];

    [mutableEnvironment release];

    HideJBLogFormat(@"Resulting environment for app launched with HideJB: %@",
                              [context environment]);
    return %orig();   
}
%end
%end

%ctor {
    if (IS_IOS_OR_NEWER(iOS_11_0)) {
        %init(iOS11Up);
    }
}