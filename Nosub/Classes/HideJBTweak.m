
#import "HideJBTweak.h"

@interface HideJBTweak ()
@property (nonatomic, strong) NSDictionary *preferences;
@end

#ifdef DEBUG
static FILE *logFile = NULL;
#endif

static CFStringRef applicationID = (__bridge CFStringRef)@"com.thuthuatjb.hidejb";

static void InitializePreferences(NSDictionary **preferences) {
    if (CFPreferencesAppSynchronize(applicationID)) {
        CFArrayRef keyList =
            CFPreferencesCopyKeyList(applicationID,
                                     kCFPreferencesCurrentUser,
                                     kCFPreferencesAnyHost);

        if (keyList) {
            *preferences =
                (NSDictionary *)CFPreferencesCopyMultiple(
                    keyList,
                    applicationID,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost);

            CFRelease(keyList);
        }
    }

    if (!*preferences) {
        NSNumber *enabledNumber = [[NSNumber alloc] initWithBool:YES];
        *preferences =
            [[NSDictionary alloc] initWithObjectsAndKeys:enabledNumber,
                                                         @"enabled_nosub",
                                                         nil];

        [enabledNumber release];
    }
}

static void LoadPreferences() {
    NSDictionary *preferences = nil;
    InitializePreferences(&preferences);

    HideJBTweak *tweak = [HideJBTweak sharedInstance];
    HideJBLogFormat(@"Loaded preferences: %@, old: %@",
                              preferences,
                              [tweak preferences]);

    [tweak setPreferences:preferences];
}

static CFStringRef preferencesChangedNotificationString =
(__bridge CFStringRef)@"ThuthuatJBHideJBPreferencesChangedNotification";

@implementation HideJBTweak
+ (instancetype)sharedInstance {
    static HideJBTweak *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[HideJBTweak alloc] init];

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)LoadPreferences,
            preferencesChangedNotificationString,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    });

    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _cachedShortcutItems = [[NSMutableDictionary alloc] init];
        _currentBundleIdentifier = nil;
        _safeModeNumber = [[NSNumber alloc] initWithBool:YES];

#ifdef DEBUG
        logFile = fopen("/User/HideJB_Logs.txt", "w");
#endif

        InitializePreferences(&_preferences);
    }

    return self;
}

- (BOOL)isEnabled {
    return [[_preferences objectForKey:@"enabled_nosub"] boolValue];
}

#ifdef DEBUG
- (void)logString:(NSString *)string {
    if (logFile) {
        fprintf(logFile, "%s\n", [string UTF8String]);
        fflush(logFile);
    }
}
#endif

- (void)dealloc {
    [_cachedShortcutItems release];
    [_safeModeNumber release];

#ifdef DEBUG
    if (logFile) {
        fclose(logFile);
    }
#endif

    [_preferences release];
    [super dealloc];
}
@end
