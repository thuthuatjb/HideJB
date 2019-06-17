
#import <Foundation/Foundation.h>
#import "../Headers/SpringBoardServices/SBSApplicationShortcutItem.h"

#ifdef DEBUG
#define HideJBLog(str) \
do { \
    NSString *formattedString = [[NSString alloc] initWithFormat:@"%s " str, __PRETTY_FUNCTION__]; \
    [[HideJBTweak sharedInstance] logString:formattedString]; \
    \
    [formattedString release]; \
} while (false);

#define HideJBLogFormat(str, ...) \
do { \
    NSString *formattedString = [[NSString alloc] initWithFormat:@"%s " str, __PRETTY_FUNCTION__, ##__VA_ARGS__]; \
    [[HideJBTweak sharedInstance] logString:formattedString]; \
    \
    [formattedString release]; \
} while (false);
#else
#define HideJBLog(str)
#define HideJBLogFormat(str, ...)
#endif

static NSString *const kHideJBShortcutItemIdentifier =
    @"com.thuthuatjb.hidejb.nosub";

@interface HideJBTweak : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isEnabled;

#ifdef DEBUG
- (void)logString:(NSString *)string;
#endif

@property (nonatomic, strong) NSString *currentBundleIdentifier;
@property (nonatomic, strong) NSNumber *safeModeNumber;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SBSApplicationShortcutItem *> *cachedShortcutItems;
@end
