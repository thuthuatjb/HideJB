
#import <version.h>
#import "../Classes/HideJBTweak.h"

%group iOS9Up
%hook SBApplicationShortcutStoreManager
- (void)_installedAppsDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    NSSet *removedBundleIdentifiers =
        [userInfo objectForKey:@"SBInstalledApplicationsRemovedBundleIDs"];

    if (removedBundleIdentifiers) {
        HideJBTweak *tweak = [HideJBTweak sharedInstance];
        NSMutableDictionary *cachedShortcutItems = [tweak cachedShortcutItems];

        for (NSString *removedBundleIdentifier in removedBundleIdentifiers) {
            [cachedShortcutItems removeObjectForKey:removedBundleIdentifier];
        }
    }

    %orig();
}
%end
%end

%ctor {
    if (IS_IOS_OR_NEWER(iOS_9_0)) {
        %init(iOS9Up);
    }
}