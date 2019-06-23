#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>

#ifdef DEBUG
#define NSLog(args...) NSLog(@"[hidejb] "args)
#else
#define NSLog(...);
#endif

#define DPKG_INFO_PATH      @"/var/lib/dpkg/info"
#define PREFS_TWEAK_ID      @"com.thuthuatjb.hidejb"
#define BLACKLIST_PATH      @"com.thuthuatjb.hidejb"
#define APPS_PATH           @"com.thuthuatjb.hidejb"
/ #define DLFCN_PATH          @"com.thuthuatjb.hidejb.apps.dlfcn"
/ #define TWEAKCOMPAT_PATH    @"com.thuthuatjb.hidejb.apps.compat.tweak"
/ #define INJECTCOMPAT_PATH   @"com.thuthuatjb.hidejb.apps.compat.injection"
/ #define LOCKDOWN_PATH       @"com.thuthuatjb.hidejb.apps.lockdown"

@interface HideJB : NSObject {
    NSMutableDictionary *link_map;
    NSMutableDictionary *path_map;
    NSMutableArray *url_set;
}

@property (nonatomic, assign) BOOL useTweakCompatibilityMode;
@property (nonatomic, assign) BOOL useInjectCompatibilityMode;
@property (readonly) BOOL passthrough;

- (NSArray *)generateDyldArray;

+ (NSArray *)generateFileMap;
+ (NSArray *)generateSchemeArray;

+ (NSError *)generateFileNotFoundError;

- (BOOL)isImageRestricted:(NSString *)name;
- (BOOL)isPathRestricted:(NSString *)path;
- (BOOL)isPathRestricted:(NSString *)path partial:(BOOL)partial;
- (BOOL)isPathRestricted:(NSString *)path manager:(NSFileManager *)fm;
- (BOOL)isPathRestricted:(NSString *)path manager:(NSFileManager *)fm partial:(BOOL)partial;
- (BOOL)isURLRestricted:(NSURL *)url;
- (BOOL)isURLRestricted:(NSURL *)url partial:(BOOL)partial;
- (BOOL)isURLRestricted:(NSURL *)url manager:(NSFileManager *)fm;
- (BOOL)isURLRestricted:(NSURL *)url manager:(NSFileManager *)fm partial:(BOOL)partial;

- (void)addPath:(NSString *)path restricted:(BOOL)restricted;
- (void)addPath:(NSString *)path restricted:(BOOL)restricted hidden:(BOOL)hidden;
- (void)addPath:(NSString *)path restricted:(BOOL)restricted hidden:(BOOL)hidden prestricted:(BOOL)prestricted phidden:(BOOL)phidden;
- (void)addRestrictedPath:(NSString *)path;
- (void)addPathsFromFileMap:(NSArray *)file_map;
- (void)addSchemesFromURLSet:(NSArray *)set;
- (void)addLinkFromPath:(NSString *)from toPath:(NSString *)to;
- (NSString *)resolveLinkInPath:(NSString *)path;

@end
