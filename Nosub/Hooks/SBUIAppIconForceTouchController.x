

#import <version.h>
#import "../Classes/HideJBTweak.h"

#import "../Headers/FrontBoard/FBSystemService.h"
#import "../Headers/SpringBoardUI/SBUIAppIconForceTouchShortcutViewController.h"

%group iOS10Up
%hook SBUIAppIconForceTouchController
- (void)appIconForceTouchShortcutViewController:(SBUIAppIconForceTouchShortcutViewController *)shortcutViewController activateApplicationShortcutItem:(SBSApplicationShortcutItem *)shortcutItem {
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
    if (IS_IOS_OR_NEWER(iOS_10_0)) {
        %init(iOS10Up);
    }
}
