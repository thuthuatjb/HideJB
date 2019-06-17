

#import <version.h>
#import "../Classes/HideJBTweak.h"

#import "../Headers/SpringBoardServices/SBSApplicationShortcutItem.h"
#import "../Headers/SpringBoardUI/SBUIAppIconForceTouchControllerDataProvider.h"

%group iOS10Up
%hook SBUIAppIconForceTouchControllerDataProvider
- (NSArray *)applicationShortcutItems {
    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    NSMutableArray *originalShortcutItems = (NSMutableArray *)%orig();

    BOOL isEnabled = [tweak isEnabled];
    if (!isEnabled) {
        HideJBLog(@"Nosub mode is not enabled");
        return originalShortcutItems;
    }

    NSMutableDictionary *cachedShortcutItems = [tweak cachedShortcutItems];
    NSString *bundleIdentifier = [self applicationBundleIdentifier];

    if (!bundleIdentifier || ![bundleIdentifier isKindOfClass:%c(NSString)]) {
        HideJBLogFormat(@"bundleIdentifier is invalid, %@", bundleIdentifier);
        return originalShortcutItems;
    }

    SBSApplicationShortcutItem *shortcutItem =
        [cachedShortcutItems objectForKey:bundleIdentifier];

    if (!shortcutItem) {
        shortcutItem = [[%c(SBSApplicationShortcutItem) alloc] init];

        [shortcutItem setLocalizedTitle:@"HideJB Nosub"];
        [shortcutItem setBundleIdentifierToLaunch:bundleIdentifier];
        [shortcutItem setType:kHideJBShortcutItemIdentifier];

        [cachedShortcutItems setObject:shortcutItem forKey:bundleIdentifier];
        [shortcutItem release];
    }

    if (![originalShortcutItems isKindOfClass:%c(NSMutableArray)]) {
        NSMutableArray *newShortcutItems = [originalShortcutItems mutableCopy];
        [newShortcutItems addObject:shortcutItem];

        HideJBLogFormat(@"newShortcutItems: %@", newShortcutItems);
        return [newShortcutItems autorelease];
    }

    [originalShortcutItems addObject:shortcutItem];
        
    HideJBLogFormat(@"originalShortcutItems: %@", originalShortcutItems);
    return originalShortcutItems;
}

%end
%end

%ctor {
    if (IS_IOS_OR_NEWER(iOS_10_0)) {
        %init(iOS10Up);
    }
}
