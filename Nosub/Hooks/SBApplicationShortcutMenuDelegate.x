
#import <version.h>
#import "../Classes/HideJBTweak.h"

#import "../Headers/BaseBoard/BSAuditToken.h"
#import "../Headers/FrontBoard/FBSystemService.h"
#import "../Headers/SpringBoard/SBApplicationShortcutMenu.h"

%group iOS9
%hook SBApplicationShortcutMenuDelegate
- (void)applicationShortcutMenu:(SBApplicationShortcutMenu *)applicationShortcutMenu activateShortcutItem:(SBSApplicationShortcutItem *)shortcutItem index:(NSUInteger)index {
    NSString *shortcutItemType = [shortcutItem type];
    if (![shortcutItemType isEqualToString:kHideJBShortcutItemIdentifier]) {
        HideJBLogFormat(@"did not invoke HideJB shortcut, invoked shortcut with \"type\": %@", shortcutItemType);
        return %orig();
    }

    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    
    NSString *bundleIdentifier = [shortcutItem bundleIdentifierToLaunch];
    [tweak setCurrentBundleIdentifier:bundleIdentifier];

    BSAuditToken *token = [%c(BSAuditToken)tokenForCurrentProcess];
    [[%c(FBSystemService) sharedInstance] terminateApplication:bundleIdentifier
                                                     forReason:1
                                                     andReport:NO
                                               withDescription:nil
                                                        source:token
                                                    completion:nil];

    %orig();
}

%end
%end

%ctor {
    if (IS_IOS_BETWEEN(iOS_9_0, iOS_9_3)) {
        %init(iOS9);
    }
}
