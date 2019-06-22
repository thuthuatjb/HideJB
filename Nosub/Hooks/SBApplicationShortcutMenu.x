

#import <version.h>

#import "../Classes/HideJBTweak.h"
#import "../Headers/SpringBoard/SBApplicationShortcutMenu.h"

%group iOS9
%hook SBApplicationShortcutMenu
- (NSArray<SBSApplicationShortcutItem *> *)_shortcutItemsToDisplay {
    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    NSMutableArray *originalShortcutItems = (NSMutableArray *)%orig();

    BOOL isEnabled = [tweak isEnabled];
    if (!isEnabled) {
        HideJBLog(@"Nosub mode is not enabled");
        return originalShortcutItems;
    }

    SBApplication *application = [self application];
    NSString *bundleIdentifier = [application bundleIdentifier];

    NSMutableDictionary *cachedShortcutItems = [tweak cachedShortcutItems];
    SBSApplicationShortcutItem *shortcutItem =
        [cachedShortcutItems objectForKey:bundleIdentifier];

    if (!shortcutItem) {
        shortcutItem = [[%c(SBSApplicationShortcutItem) alloc] init];

        [shortcutItem setLocalizedTitle:@"HideJB NoSub"];
        [shortcutItem setLocalizedSubtitle:@"Disable tweaks - Tắt tweaks"];			
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
    if (IS_IOS_BETWEEN(iOS_9_0, iOS_9_3)) {
        %init(iOS9);
    }
}
