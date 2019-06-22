
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Cephei/HBPreferences.h>
#import "Includes/HideJB.h"

HideJB *_hidejb = nil;

NSArray *dyld_array = nil;
uint32_t dyld_array_count = 0;

// Stable Hooks
%group hook_libc
// #include "Hooks/Stable/libc.xm"
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <unistd.h>
#include <spawn.h>
#include <fcntl.h>
#include <errno.h>

%hookf(int, access, const char *pathname, int mode) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        // workaround for tweaks not loading properly in Substrate
        if([_hidejb useInjectCompatibilityMode]) {
            if([[path pathExtension] isEqualToString:@"plist"] && [path containsString:@"DynamicLibraries/"]) {
                return %orig;
            }
        }

        if([_hidejb isPathRestricted:path]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}

%hookf(char *, getenv, const char *name) {
    if(name) {
        NSString *env = [NSString stringWithUTF8String:name];

        if([env isEqualToString:@"DYLD_INSERT_LIBRARIES"]
        || [env isEqualToString:@"_MSSafeMode"]
        || [env isEqualToString:@"_SafeMode"]) {
            return NULL;
        }
    }

    return %orig;
}

%hookf(FILE *, fopen, const char *pathname, const char *mode) {
    if(pathname) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:pathname]]) {
            errno = ENOENT;
            return NULL;
        }
    }

    return %orig;
}

%hookf(FILE *, freopen, const char *pathname, const char *mode, FILE *stream) {
    if(pathname) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:pathname]]) {
            fclose(stream);
            errno = ENOENT;
            return NULL;
        }
    }

    return %orig;
}

%hookf(int, stat, const char *pathname, struct stat *statbuf) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        if([_hidejb isPathRestricted:path]) {
            errno = ENOENT;
            return -1;
        }

        // Maybe some filesize overrides?
        if(statbuf) {
            if([path isEqualToString:@"/bin"]) {
                int ret = %orig;

                if(ret == 0 && statbuf->st_size > 128) {
                    statbuf->st_size = 128;
                    return ret;
                }
            }
        }
    }

    return %orig;
}

%hookf(int, lstat, const char *pathname, struct stat *statbuf) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        if([_hidejb isPathRestricted:path]) {
            errno = ENOENT;
            return -1;
        }

        // Maybe some filesize overrides?
        if(statbuf) {
            if([path isEqualToString:@"/Applications"]
            || [path isEqualToString:@"/usr/share"]
            || [path isEqualToString:@"/usr/libexec"]
            || [path isEqualToString:@"/usr/include"]
            || [path isEqualToString:@"/Library/Ringtones"]
            || [path isEqualToString:@"/Library/Wallpaper"]) {
                int ret = %orig;

                if(ret == 0 && (statbuf->st_mode & S_IFLNK) == S_IFLNK) {
                    statbuf->st_mode &= ~S_IFLNK;
                    return ret;
                }
            }

            if([path isEqualToString:@"/bin"]) {
                int ret = %orig;

                if(ret == 0 && statbuf->st_size > 128) {
                    statbuf->st_size = 128;
                    return ret;
                }
            }
        }
    }

    return %orig;
}

%hookf(int, fstatfs, int fd, struct statfs *buf) {
    int ret = %orig;

    if(ret == 0) {
        // Get path of dirfd.
        char path[PATH_MAX];

        if(fcntl(fd, F_GETPATH, path) != -1) {
            NSString *pathname = [NSString stringWithUTF8String:path];

            if([_hidejb isPathRestricted:pathname]) {
                errno = ENOENT;
                return -1;
            }

            pathname = [_hidejb resolveLinkInPath:pathname];
            
            if(![pathname hasPrefix:@"/var"]
            && ![pathname hasPrefix:@"/private/var"]) {
                if(buf) {
                    // Ensure root fs is marked read-only.
                    buf->f_flags |= MNT_RDONLY | MNT_ROOTFS;
                    return ret;
                }
            } else {
                // Ensure var fs is marked NOSUID.
                buf->f_flags |= MNT_NOSUID | MNT_NODEV;
                return ret;
            }
        }
    }

    return ret;
}

%hookf(int, statfs, const char *path, struct statfs *buf) {
    int ret = %orig;

    if(ret == 0) {
        NSString *pathname = [NSString stringWithUTF8String:path];

        if([_hidejb isPathRestricted:pathname]) {
            errno = ENOENT;
            return -1;
        }

        pathname = [_hidejb resolveLinkInPath:pathname];

        if([pathname hasPrefix:@"/var/mobile/Containers/Data/Application"]) {
            if(buf) {
                // Ensure application sandbox is marked NOSUID.
                buf->f_flags |= MNT_NOSUID | MNT_NODEV;
                return ret;
            }
        }
        
        if(![pathname hasPrefix:@"/var"]
        && ![pathname hasPrefix:@"/private/var"]) {
            if(buf) {
                // Ensure root is marked read-only.
                buf->f_flags |= MNT_RDONLY | MNT_ROOTFS;
                return ret;
            }
        }
    }

    return ret;
}

%hookf(int, posix_spawn, pid_t *pid, const char *pathname, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        if([_hidejb isPathRestricted:path]) {
            return ENOENT;
        }
    }

    return %orig;
}

%hookf(int, posix_spawnp, pid_t *pid, const char *pathname, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        if([_hidejb isPathRestricted:path]) {
            return ENOENT;
        }
    }

    return %orig;
}

%hookf(char *, realpath, const char *pathname, char *resolved_path) {
    BOOL doFree = (resolved_path != NULL);

    if(pathname) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:pathname]]) {
            errno = ENOENT;
            return NULL;
        }
    }

    char *ret = %orig;

    // Recheck resolved path.
    if(ret) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:ret]]) {
            errno = ENOENT;

            // Free resolved_path if it was allocated by libc.
            if(doFree) {
                free(ret);
            }

            return NULL;
        }

        if(strcmp(ret, pathname) != 0) {
            // Possible symbolic link? Track it in HideJB
            [_hidejb addLinkFromPath:[NSString stringWithUTF8String:pathname] toPath:[NSString stringWithUTF8String:ret]];
        }
    }

    return ret;
}

%hookf(int, symlink, const char *path1, const char *path2) {
    if(path1 && path2) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:path1]] || [_hidejb isPathRestricted:[NSString stringWithUTF8String:path2]]) {
            errno = ENOENT;
            return -1;
        }
    }

    int ret = %orig;

    if(ret == 0) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:[NSString stringWithUTF8String:path1] toPath:[NSString stringWithUTF8String:path2]];
    }

    return ret;
}

%hookf(int, link, const char *path1, const char *path2) {
    if(path1 && path2) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:path1]] || [_hidejb isPathRestricted:[NSString stringWithUTF8String:path2]]) {
            errno = ENOENT;
            return -1;
        }
    }

    int ret = %orig;

    if(ret == 0) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:[NSString stringWithUTF8String:path1] toPath:[NSString stringWithUTF8String:path2]];
    }

    return ret;
}

%hookf(int, fstatat, int dirfd, const char *pathname, struct stat *buf, int flags) {
    if(pathname) {
        NSString *path = [NSString stringWithUTF8String:pathname];

        if(![path isAbsolutePath]) {
            // Get path of dirfd.
            char dirfdpath[PATH_MAX];
        
            if(fcntl(dirfd, F_GETPATH, dirfdpath) != -1) {
                NSString *dirfd_path = [NSString stringWithUTF8String:dirfdpath];
                path = [dirfd_path stringByAppendingPathComponent:path];
            }
        }
        
        if([_hidejb isPathRestricted:path]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}
%end

%group hook_libc_inject
%hookf(int, fstat, int fd, struct stat *buf) {
    // Get path of dirfd.
    char fdpath[PATH_MAX];

    if(fcntl(fd, F_GETPATH, fdpath) != -1) {
        NSString *fd_path = [NSString stringWithUTF8String:fdpath];
        
        if([_hidejb isPathRestricted:fd_path]) {
            errno = EBADF;
            return -1;
        }

        if(buf) {
            if([fd_path isEqualToString:@"/bin"]) {
                int ret = %orig;

                if(ret == 0 && buf->st_size > 128) {
                    buf->st_size = 128;
                    return ret;
                }
            }
        }
    }

    return %orig;
}
%end

%group hook_dlopen_inject
%hookf(void *, dlopen, const char *path, int mode) {
    if(path) {
        NSString *image_name = [NSString stringWithUTF8String:path];

        if([_hidejb isImageRestricted:image_name]) {
            return NULL;
        }
    }

    return %orig;
}
%end

%group hook_NSFileHandle
// #include "Hooks/Stable/NSFileHandle.xm"
%hook NSFileHandle
+ (instancetype)fileHandleForReadingAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path]) {
        return nil;
    }

    return %orig;
}

+ (instancetype)fileHandleForReadingFromURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (instancetype)fileHandleForWritingAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path]) {
        return nil;
    }

    return %orig;
}

+ (instancetype)fileHandleForWritingToURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (instancetype)fileHandleForUpdatingAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path]) {
        return nil;
    }

    return %orig;
}

+ (instancetype)fileHandleForUpdatingURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}
%end
%end

%group hook_NSFileManager
// #include "Hooks/Stable/NSFileManager.xm"
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)isDeletableFileAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)isExecutableFileAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)replaceItemAtURL:(NSURL *)originalItemURL withItemAtURL:(NSURL *)newItemURL backupItemName:(NSString *)backupItemName options:(NSFileManagerItemReplacementOptions)options resultingItemURL:(NSURL * _Nullable *)resultingURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:originalItemURL manager:self] || [_hidejb isURLRestricted:newItemURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (NSArray<NSURL *> *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSURLResourceKey> *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    // Filter array.
    NSMutableArray *filtered_ret = nil;
    NSArray *ret = %orig;

    if(ret) {
        filtered_ret = [NSMutableArray new];

        for(NSURL *ret_url in ret) {
            if(![_hidejb isURLRestricted:ret_url manager:self]) {
                [filtered_ret addObject:ret_url];
            }
        }
    }

    return ret ? [filtered_ret copy] : ret;
}

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    // Filter array.
    NSMutableArray *filtered_ret = nil;
    NSArray *ret = %orig;

    if(ret) {
        filtered_ret = [NSMutableArray new];

        for(NSString *ret_path in ret) {
            // Ensure absolute path for path.
            if(![_hidejb isPathRestricted:[path stringByAppendingPathComponent:ret_path] manager:self]) {
                [filtered_ret addObject:ret_path];
            }
        }
    }

    return ret ? [filtered_ret copy] : ret;
}

- (NSDirectoryEnumerator<NSURL *> *)enumeratorAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSURLResourceKey> *)keys options:(NSDirectoryEnumerationOptions)mask errorHandler:(BOOL (^)(NSURL *url, NSError *error))handler {
    if([_hidejb isURLRestricted:url manager:self]) {
        return %orig([NSURL fileURLWithPath:@"file:///.file"], keys, mask, handler);
    }

    return %orig;
}

- (NSDirectoryEnumerator<NSString *> *)enumeratorAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return %orig(@"/.file");
    }

    return %orig;
}

- (NSArray<NSString *> *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    // Filter array.
    NSMutableArray *filtered_ret = nil;
    NSArray *ret = %orig;

    if(ret) {
        filtered_ret = [NSMutableArray new];

        for(NSString *ret_path in ret) {
            // Ensure absolute path for path.
            if(![_hidejb isPathRestricted:[path stringByAppendingPathComponent:ret_path] manager:self]) {
                [filtered_ret addObject:ret_path];
            }
        }
    }

    return ret ? [filtered_ret copy] : ret;
}

- (NSArray<NSString *> *)subpathsAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return nil;
    }

    // Filter array.
    NSMutableArray *filtered_ret = nil;
    NSArray *ret = %orig;

    if(ret) {
        filtered_ret = [NSMutableArray new];

        for(NSString *ret_path in ret) {
            // Ensure absolute path for path.
            if(![_hidejb isPathRestricted:[path stringByAppendingPathComponent:ret_path] manager:self]) {
                [filtered_ret addObject:ret_path];
            }
        }
    }

    return ret ? [filtered_ret copy] : ret;
}

- (BOOL)copyItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:srcURL manager:self] || [_hidejb isURLRestricted:dstURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:srcPath manager:self] || [_hidejb isPathRestricted:dstPath manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)moveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:srcURL manager:self] || [_hidejb isURLRestricted:dstURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:srcPath manager:self] || [_hidejb isPathRestricted:dstPath manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (NSArray<NSString *> *)componentsToDisplayForPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return nil;
    }

    return %orig;
}

- (NSString *)displayNameAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return path;
    }

    return %orig;
}

- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

- (NSDictionary<NSFileAttributeKey, id> *)attributesOfFileSystemForPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

- (BOOL)setAttributes:(NSDictionary<NSFileAttributeKey, id> *)attributes ofItemAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (NSData *)contentsAtPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return nil;
    }

    return %orig;
}

- (BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
    if([_hidejb isPathRestricted:path1] || [_hidejb isPathRestricted:path2]) {
        return NO;
    }

    return %orig;
}

- (BOOL)getRelationship:(NSURLRelationship *)outRelationship ofDirectoryAtURL:(NSURL *)directoryURL toItemAtURL:(NSURL *)otherURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:directoryURL manager:self] || [_hidejb isURLRestricted:otherURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)getRelationship:(NSURLRelationship *)outRelationship ofDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domainMask toItemAtURL:(NSURL *)otherURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:otherURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)changeCurrentDirectoryPath:(NSString *)path {
    if([_hidejb isPathRestricted:path manager:self]) {
        return NO;
    }

    return %orig;
}

- (BOOL)createSymbolicLinkAtURL:(NSURL *)url withDestinationURL:(NSURL *)destURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url manager:self] || [_hidejb isURLRestricted:destURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    BOOL ret = %orig;

    if(ret) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:[url path] toPath:[destURL path]];
    }

    return ret;
}

- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)destPath error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path] || [_hidejb isPathRestricted:destPath]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    BOOL ret = %orig;

    if(ret) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:path toPath:destPath];
    }

    return ret;
}

- (BOOL)linkItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:srcURL manager:self] || [_hidejb isURLRestricted:dstURL manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    BOOL ret = %orig;

    if(ret) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:[srcURL path] toPath:[dstURL path]];
    }

    return ret;
}

- (BOOL)linkItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:srcPath manager:self] || [_hidejb isPathRestricted:dstPath manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    BOOL ret = %orig;

    if(ret) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:srcPath toPath:dstPath];
    }

    return ret;
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path manager:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    NSString *ret = %orig;

    if(ret) {
        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:path toPath:ret];
    }

    return ret;
}
%end
%end

%group hook_NSEnumerator
%hook NSDirectoryEnumerator
- (id)nextObject {
    id ret = nil;

    while((ret = %orig)) {
        if([ret isKindOfClass:[NSURL class]]) {
            if([_hidejb isURLRestricted:ret]) {
                continue;
            }
        }

        if([ret isKindOfClass:[NSString class]]) {
            // TODO: convert to absolute path
        }

        break;
    }

    return ret;
}
%end
%end

%group hook_NSURL
// #include "Hooks/Stable/NSURL.xm"
%hook NSURL
- (BOOL)checkResourceIsReachableAndReturnError:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:self]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}
%end
%end

%group hook_UIApplication
// #include "Hooks/Stable/UIApplication.xm"
%hook UIApplication
- (BOOL)canOpenURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url]) {
        return NO;
    }

    return %orig;
}
%end
%end

%group hook_NSBundle
// #include "Hooks/Testing/NSBundle.xm"
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if([key isEqualToString:@"SignerIdentity"]) {
        return nil;
    }

    return %orig;
}
%end
%end

%group hook_CoreFoundation
%hookf(CFArrayRef, CFBundleGetAllBundles) {
    CFArrayRef cfbundles = %orig;
    CFIndex cfcount = CFArrayGetCount(cfbundles);

    NSMutableArray *filter = [NSMutableArray new];
    NSMutableArray *bundles = [NSMutableArray arrayWithArray:(__bridge NSArray *) cfbundles];

    // Filter return value.
    int i;
    for(i = 0; i < cfcount; i++) {
        CFBundleRef cfbundle = (CFBundleRef) CFArrayGetValueAtIndex(cfbundles, i);
        CFURLRef cfbundle_cfurl = CFBundleCopyExecutableURL(cfbundle);

        if(cfbundle_cfurl) {
            NSURL *bundle_url = (__bridge NSURL *) cfbundle_cfurl;

            if([_hidejb isURLRestricted:bundle_url]) {
                continue;
            }
        }

        [filter addObject:bundles[i]];
    }

    return (__bridge CFArrayRef) [filter copy];
}

/*
%hookf(CFReadStreamRef, CFReadStreamCreateWithFile, CFAllocatorRef alloc, CFURLRef fileURL) {
    NSURL *nsurl = (__bridge NSURL *)fileURL;

    if([nsurl isFileURL] && [_hidejb isPathRestricted:[nsurl path] partial:NO]) {
        return NULL;
    }

    return %orig;
}

%hookf(CFWriteStreamRef, CFWriteStreamCreateWithFile, CFAllocatorRef alloc, CFURLRef fileURL) {
    NSURL *nsurl = (__bridge NSURL *)fileURL;

    if([nsurl isFileURL] && [_hidejb isPathRestricted:[nsurl path] partial:NO]) {
        return NULL;
    }

    return %orig;
}

%hookf(CFURLRef, CFURLCreateFilePathURL, CFAllocatorRef allocator, CFURLRef url, CFErrorRef *error) {
    NSURL *nsurl = (__bridge NSURL *)url;

    if([nsurl isFileURL] && [_hidejb isPathRestricted:[nsurl path] partial:NO]) {
        if(error) {
            *error = (__bridge CFErrorRef) [HideJB generateFileNotFoundError];
        }
        
        return NULL;
    }

    return %orig;
}

%hookf(CFURLRef, CFURLCreateFileReferenceURL, CFAllocatorRef allocator, CFURLRef url, CFErrorRef *error) {
    NSURL *nsurl = (__bridge NSURL *)url;

    if([nsurl isFileURL] && [_hidejb isPathRestricted:[nsurl path] partial:NO]) {
        if(error) {
            *error = (__bridge CFErrorRef) [HideJB generateFileNotFoundError];
        }
        
        return NULL;
    }

    return %orig;
}
*/
%end

%group hook_NSUtilities
%hook UIImage
- (instancetype)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (UIImage *)imageWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}
%end
/*
%hook NSData
- (id)initWithContentsOfMappedFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)dataWithContentsOfMappedFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

- (instancetype)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}

- (instancetype)initWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }
        
        return nil;
    }

    return %orig;
}

+ (instancetype)dataWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (instancetype)dataWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (instancetype)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}
%end
*/

%hook NSMutableArray
- (id)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)arrayWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)arrayWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}
%end

%hook NSArray
- (id)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)arrayWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)arrayWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}
%end

%hook NSMutableDictionary
- (id)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}
%end

%hook NSDictionary
- (id)initWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

- (id)initWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}

- (id)initWithContentsOfURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (id)dictionaryWithContentsOfFile:(NSString *)path {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return nil;
    }

    return %orig;
}

+ (id)dictionaryWithContentsOfURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (id)dictionaryWithContentsOfURL:(NSURL *)url {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return nil;
    }

    return %orig;
}
%end

%hook NSString
- (instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

- (instancetype)initWithContentsOfFile:(NSString *)path usedEncoding:(NSStringEncoding *)enc error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}

+ (instancetype)stringWithContentsOfFile:(NSString *)path usedEncoding:(NSStringEncoding *)enc error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return nil;
    }

    return %orig;
}
%end
%end

// Other Hooks
%group hook_private
// #include "Hooks/ApplePrivate.xm"
#include <unistd.h>
#include "Includes/codesign.h"

%hookf(int, csops, pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int ret = %orig;

    if(ops == CS_OPS_STATUS && (ret & CS_PLATFORM_BINARY) == CS_PLATFORM_BINARY && pid == getpid()) {
        // Ensure that the platform binary flag is not set.
        ret &= ~CS_PLATFORM_BINARY;
    }

    return ret;
}
%end

%group hook_debugging
// #include "Hooks/Debugging.xm"
#include <sys/sysctl.h>
#include <unistd.h>
#include <fcntl.h>

%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if(namelen == 4
    && name[0] == CTL_KERN
    && name[1] == KERN_PROC
    && name[2] == KERN_PROC_ALL
    && name[3] == 0) {
        // Running process check.
        *oldlenp = 0;
        return 0;
    }

    int ret = %orig;

    if(ret == 0
    && name[0] == CTL_KERN
    && name[1] == KERN_PROC
    && name[2] == KERN_PROC_PID
    && name[3] == getpid()) {
        // Remove trace flag.
        if(oldp) {
            struct kinfo_proc *p = ((struct kinfo_proc *) oldp);

            if((p->kp_proc.p_flag & P_TRACED) == P_TRACED) {
                p->kp_proc.p_flag &= ~P_TRACED;
            }
        }
    }

    return ret;
}

%hookf(pid_t, getppid) {
    return 1;
}

/*
%hookf(int, "_ptrace", int request, pid_t pid, caddr_t addr, int data) {
    // PTRACE_DENY_ATTACH = 31
    if(request == 31) {
        return 0;
    }

    return %orig;
}
*/
%end

%group hook_dyld_image
// #include "Hooks/dyld.xm"
#include <mach-o/dyld.h>

%hookf(uint32_t, _dyld_image_count) {
    if(dyld_array_count > 0) {
        return dyld_array_count;
    }

    return %orig;
}

%hookf(const char *, _dyld_get_image_name, uint32_t image_index) {
    if(dyld_array_count > 0) {
        if(image_index >= dyld_array_count) {
            return NULL;
        }

        image_index = (uint32_t) [dyld_array[image_index] unsignedIntValue];
    }

    // Basic filter.
    const char *ret = %orig(image_index);

    if(ret && [_hidejb isImageRestricted:[NSString stringWithUTF8String:ret]]) {
        return %orig(0);
    }

    return ret;
}
/*
%hookf(const struct mach_header *, _dyld_get_image_header, uint32_t image_index) {
    static struct mach_header ret;

    if(dyld_array_count > 0) {
        if(image_index >= dyld_array_count) {
            return NULL;
        }

        // image_index = (uint32_t) [dyld_array[image_index] unsignedIntValue];
    }

    ret = *(%orig(image_index));

    return &ret;
}

%hookf(intptr_t, _dyld_get_image_vmaddr_slide, uint32_t image_index) {
    if(dyld_array_count > 0) {
        if(image_index >= dyld_array_count) {
            return 0;
        }

        // image_index = (uint32_t) [dyld_array[image_index] unsignedIntValue];
    }

    return %orig(image_index);
}
*/
%hookf(bool, dlopen_preflight, const char *path) {
    if(path) {
        NSString *image_name = [NSString stringWithUTF8String:path];

        if([_hidejb isImageRestricted:image_name]) {
            NSLog(@"blocked dlopen_preflight: %@", image_name);
            return false;
        }
    }

    return %orig;
}
%end

%group hook_dyld_advanced
%hookf(int32_t, NSVersionOfRunTimeLibrary, const char *libraryName) {
    if(libraryName) {
        NSString *name = [NSString stringWithUTF8String:libraryName];

        if([_hidejb isImageRestricted:name]) {
            return -1;
        }
    }
    
    return %orig;
}

%hookf(int32_t, NSVersionOfLinkTimeLibrary, const char *libraryName) {
    if(libraryName) {
        NSString *name = [NSString stringWithUTF8String:libraryName];

        if([_hidejb isImageRestricted:name]) {
            return -1;
        }
    }
    
    return %orig;
}
/*
%hookf(void, _dyld_register_func_for_add_image, void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide)) {
    %orig;
}

%hookf(void, _dyld_register_func_for_remove_image, void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide)) {
    %orig;
}
*/
%end

%group hook_dyld_dlsym
// #include "Hooks/dlsym.xm"
#include <dlfcn.h>

%hookf(void *, dlsym, void *handle, const char *symbol) {
    if(symbol) {
        NSString *sym = [NSString stringWithUTF8String:symbol];

        if([sym hasPrefix:@"MS"]
        || [sym hasPrefix:@"Sub"]
        || [sym hasPrefix:@"PS"]
        || [sym hasPrefix:@"rocketbootstrap"]
        || [sym hasPrefix:@"LM"]
        || [sym hasPrefix:@"substitute_"]
        || [sym hasPrefix:@"_logos"]) {
            NSLog(@"blocked dlsym lookup: %@", sym);
            return NULL;
        }
    }

    return %orig;
}
%end

%group hook_sandbox
// #include "Hooks/Sandbox.xm"
#include <stdio.h>
#include <unistd.h>

%hook NSArray
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return NO;
    }

    return %orig;
}
%end

%hook NSDictionary
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return NO;
    }

    return %orig;
}
%end

%hook NSData
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return NO;
    }

    return %orig;
}

- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)writeOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)useAuxiliaryFile {
    if([_hidejb isURLRestricted:url partial:NO]) {
        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url options:(NSDataWritingOptions)writeOptionsMask error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}
%end

%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}
%end

%hook NSFileManager
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes error:(NSError * _Nullable *)error {
    if([_hidejb isURLRestricted:url partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes error:(NSError * _Nullable *)error {
    if([_hidejb isPathRestricted:path partial:NO]) {
        if(error) {
            *error = [HideJB generateFileNotFoundError];
        }

        return NO;
    }

    return %orig;
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSFileAttributeKey, id> *)attr {
    if([_hidejb isPathRestricted:path partial:NO]) {
        return NO;
    }

    return %orig;
}
%end

%hookf(int, creat, const char *pathname, mode_t mode) {
    if(pathname) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:pathname]]) {
            errno = EACCES;
            return -1;
        }
    }

    return %orig;
}

%hookf(pid_t, vfork) {
    errno = ENOSYS;
    return -1;
}

%hookf(pid_t, fork) {
    errno = ENOSYS;
    return -1;
}

%hookf(FILE *, popen, const char *command, const char *type) {
    errno = ENOSYS;
    return NULL;
}

%hookf(int, setgid, gid_t gid) {
    // Block setgid for root.
    if(gid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}

%hookf(int, setuid, uid_t uid) {
    // Block setuid for root.
    if(uid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}

%hookf(int, setegid, gid_t gid) {
    // Block setegid for root.
    if(gid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}

%hookf(int, seteuid, uid_t uid) {
    // Block seteuid for root.
    if(uid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}

%hookf(uid_t, getuid) {
    // Return uid for mobile.
    return 501;
}

%hookf(gid_t, getgid) {
    // Return gid for mobile.
    return 501;
}

%hookf(uid_t, geteuid) {
    // Return uid for mobile.
    return 501;
}

%hookf(uid_t, getegid) {
    // Return gid for mobile.
    return 501;
}

%hookf(int, setreuid, uid_t ruid, uid_t euid) {
    // Block for root.
    if(ruid == 0 || euid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}

%hookf(int, setregid, gid_t rgid, gid_t egid) {
    // Block for root.
    if(rgid == 0 || egid == 0) {
        errno = EPERM;
        return -1;
    }

    return %orig;
}
%end

%group hook_libraries
%hook AppDelegate
- (void)applicationDidBecomeActive:(id)arg1 {
} 
%end

%hook CDVViewController
- (void)onAppDidBecomeActive:(id)arg1 {
} 
%end

%hook UIDevice
+ (BOOL)isJailbroken {
    return NO;
}

- (BOOL)isJailBreak {
    return NO;
}

- (BOOL)isJailBroken {
    return NO;
}
%end

// %hook SFAntiPiracy
// + (int)isJailbroken {
// 	// Probably should not hook with a hard coded value.
// 	// This value may be changed by developers using this library.
// 	// Best to defeat the checks rather than skip them.
// 	return 4783242;
// }
// %end

%hook JailbreakDetectionVC
- (BOOL)isJailbroken {
    return NO;
}
%end

%hook DTTJailbreakDetection
+ (BOOL)isJailbroken {
    return NO;
}
%end

%hook ANSMetadata
- (BOOL)computeIsJailbroken {
    return NO;
}

- (BOOL)isJailbroken {
    return NO;
}
%end

%hook AppsFlyerUtils
+ (BOOL)isJailBreakon {
    return NO;
}
%end

%hook GBDeviceInfo
- (BOOL)isJailbroken {
    return NO;
}
%end

%hook CMARAppRestrictionsDelegate
- (bool)isDeviceNonCompliant {
    return false;
}
%end

%hook ADYSecurityChecks
+ (bool)isDeviceJailbroken {
    return false;
}
%end

%hook UBReportMetadataDevice
- (void *)is_rooted {
    return NULL;
}
%end

%hook UtilitySystem
+ (bool)isJailbreak {
    return false;
}
%end

%hook GemaltoConfiguration
+ (bool)isJailbreak {
    return false;
}
%end

%hook CPWRDeviceInfo
- (bool)isJailbroken {
    return false;
}
%end

%hook CPWRSessionInfo
- (bool)isJailbroken {
    return false;
}
%end

%hook KSSystemInfo
+ (bool)isJailbroken {
    return false;
}
%end

%hook EMDSKPPConfiguration
- (bool)jailBroken {
    return false;
}
%end

%hook EnrollParameters
- (void *)jailbroken {
    return NULL;
}
%end

%hook EMDskppConfigurationBuilder
- (bool)jailbreakStatus {
    return false;
}
%end

%hook FCRSystemMetadata
- (bool)isJailbroken {
    return false;
}
%end

%hook v_VDMap
- (bool)isJailBrokenDetectedByVOS {
    return false;
}
%end

%hook SDMUtils
- (BOOL)isJailBroken {
    return NO;
}
%end

%hook OneSignalJailbreakDetection
+ (BOOL)isJailbroken {
    return NO;
}
%end
%end

void init_path_map(HideJB *hidejb) {
    // Restrict / by whitelisting
    [hidejb addPath:@"/" restricted:YES hidden:NO];
    [hidejb addPath:@"/.file" restricted:NO];
    [hidejb addPath:@"/.ba" restricted:NO];
    [hidejb addPath:@"/.mb" restricted:NO];
    [hidejb addPath:@"/.HFS" restricted:NO];
    [hidejb addPath:@"/.Trashes" restricted:NO];
    // [hidejb addPath:@"/AppleInternal" restricted:NO];
    [hidejb addPath:@"/cores" restricted:NO];
    [hidejb addPath:@"/Developer" restricted:NO];
    [hidejb addPath:@"/lib" restricted:NO];
    [hidejb addPath:@"/mnt" restricted:NO];

    // Restrict /bin by whitelisting
    [hidejb addPath:@"/bin" restricted:YES hidden:NO];
    [hidejb addPath:@"/bin/df" restricted:NO];
    [hidejb addPath:@"/bin/ps" restricted:NO];

    // Restrict /sbin by whitelisting
    [hidejb addPath:@"/sbin" restricted:YES hidden:NO];
    [hidejb addPath:@"/sbin/fsck" restricted:NO];
    [hidejb addPath:@"/sbin/launchd" restricted:NO];
    [hidejb addPath:@"/sbin/mount" restricted:NO];
    [hidejb addPath:@"/sbin/pfctl" restricted:NO];

    // Restrict /Applications by whitelisting
    [hidejb addPath:@"/Applications" restricted:YES hidden:NO];
    [hidejb addPath:@"/Applications/AXUIViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/AccountAuthenticationDialog.app" restricted:NO];
    [hidejb addPath:@"/Applications/ActivityMessagesApp.app" restricted:NO];
    [hidejb addPath:@"/Applications/AdPlatformsDiagnostics.app" restricted:NO];
    [hidejb addPath:@"/Applications/AppStore.app" restricted:NO];
    [hidejb addPath:@"/Applications/AskPermissionUI.app" restricted:NO];
    [hidejb addPath:@"/Applications/BusinessExtensionsWrapper.app" restricted:NO];
    [hidejb addPath:@"/Applications/CTCarrierSpaceAuth.app" restricted:NO];
    [hidejb addPath:@"/Applications/Camera.app" restricted:NO];
    [hidejb addPath:@"/Applications/CheckerBoard.app" restricted:NO];
    [hidejb addPath:@"/Applications/CompassCalibrationViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/ContinuityCamera.app" restricted:NO];
    [hidejb addPath:@"/Applications/CoreAuthUI.app" restricted:NO];
    [hidejb addPath:@"/Applications/DDActionsService.app" restricted:NO];
    [hidejb addPath:@"/Applications/DNDBuddy.app" restricted:NO];
    [hidejb addPath:@"/Applications/DataActivation.app" restricted:NO];
    [hidejb addPath:@"/Applications/DemoApp.app" restricted:NO];
    [hidejb addPath:@"/Applications/Diagnostics.app" restricted:NO];
    [hidejb addPath:@"/Applications/DiagnosticsService.app" restricted:NO];
    [hidejb addPath:@"/Applications/FTMInternal-4.app" restricted:NO];
    [hidejb addPath:@"/Applications/Family.app" restricted:NO];
    [hidejb addPath:@"/Applications/Feedback Assistant iOS.app" restricted:NO];
    [hidejb addPath:@"/Applications/FieldTest.app" restricted:NO];
    [hidejb addPath:@"/Applications/FindMyiPhone.app" restricted:NO];
    [hidejb addPath:@"/Applications/FunCameraShapes.app" restricted:NO];
    [hidejb addPath:@"/Applications/FunCameraText.app" restricted:NO];
    [hidejb addPath:@"/Applications/GameCenterUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/HashtagImages.app" restricted:NO];
    [hidejb addPath:@"/Applications/Health.app" restricted:NO];
    [hidejb addPath:@"/Applications/HealthPrivacyService.app" restricted:NO];
    [hidejb addPath:@"/Applications/HomeUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/InCallService.app" restricted:NO];
    [hidejb addPath:@"/Applications/Magnifier.app" restricted:NO];
    [hidejb addPath:@"/Applications/MailCompositionService.app" restricted:NO];
    [hidejb addPath:@"/Applications/MessagesViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/MobilePhone.app" restricted:NO];
    [hidejb addPath:@"/Applications/MobileSMS.app" restricted:NO];
    [hidejb addPath:@"/Applications/MobileSafari.app" restricted:NO];
    [hidejb addPath:@"/Applications/MobileSlideShow.app" restricted:NO];
    [hidejb addPath:@"/Applications/MobileTimer.app" restricted:NO];
    [hidejb addPath:@"/Applications/MusicUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/Passbook.app" restricted:NO];
    [hidejb addPath:@"/Applications/PassbookUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/PhotosViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/PreBoard.app" restricted:NO];
    [hidejb addPath:@"/Applications/Preferences.app" restricted:NO];
    [hidejb addPath:@"/Applications/Print Center.app" restricted:NO];
    [hidejb addPath:@"/Applications/SIMSetupUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/SLGoogleAuth.app" restricted:NO];
    [hidejb addPath:@"/Applications/SLYahooAuth.app" restricted:NO];
    [hidejb addPath:@"/Applications/SafariViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/ScreenSharingViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/ScreenshotServicesService.app" restricted:NO];
    [hidejb addPath:@"/Applications/Setup.app" restricted:NO];
    [hidejb addPath:@"/Applications/SharedWebCredentialViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/SharingViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/SiriViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/SoftwareUpdateUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/StoreDemoViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/StoreKitUIService.app" restricted:NO];
    [hidejb addPath:@"/Applications/TrustMe.app" restricted:NO];
    [hidejb addPath:@"/Applications/Utilities" restricted:NO];
    [hidejb addPath:@"/Applications/VideoSubscriberAccountViewService.app" restricted:NO];
    [hidejb addPath:@"/Applications/WLAccessService.app" restricted:NO];
    [hidejb addPath:@"/Applications/Web.app" restricted:NO];
    [hidejb addPath:@"/Applications/WebApp1.app" restricted:NO];
    [hidejb addPath:@"/Applications/WebContentAnalysisUI.app" restricted:NO];
    [hidejb addPath:@"/Applications/WebSheet.app" restricted:NO];
    [hidejb addPath:@"/Applications/iAdOptOut.app" restricted:NO];
    [hidejb addPath:@"/Applications/iCloud.app" restricted:NO];

    // Restrict /dev
    [hidejb addPath:@"/dev" restricted:NO];
    [hidejb addPath:@"/dev/dlci." restricted:YES];
    [hidejb addPath:@"/dev/vn0" restricted:YES];
    [hidejb addPath:@"/dev/vn1" restricted:YES];
    [hidejb addPath:@"/dev/kmem" restricted:YES];
    [hidejb addPath:@"/dev/mem" restricted:YES];

    // Restrict /private by whitelisting
    [hidejb addPath:@"/private" restricted:YES hidden:NO];
    [hidejb addPath:@"/private/etc" restricted:NO];
    [hidejb addPath:@"/private/system_data" restricted:NO];
    [hidejb addPath:@"/private/var" restricted:NO];
    [hidejb addPath:@"/private/xarts" restricted:NO];

    // Restrict /etc by whitelisting
    [hidejb addPath:@"/etc" restricted:YES hidden:NO];
    [hidejb addPath:@"/etc/asl" restricted:NO];
    [hidejb addPath:@"/etc/asl.conf" restricted:NO];
    [hidejb addPath:@"/etc/fstab" restricted:NO];
    [hidejb addPath:@"/etc/group" restricted:NO];
    [hidejb addPath:@"/etc/hosts" restricted:NO];
    [hidejb addPath:@"/etc/hosts.equiv" restricted:NO];
    [hidejb addPath:@"/etc/master.passwd" restricted:NO];
    [hidejb addPath:@"/etc/networks" restricted:NO];
    [hidejb addPath:@"/etc/notify.conf" restricted:NO];
    [hidejb addPath:@"/etc/passwd" restricted:NO];
    [hidejb addPath:@"/etc/ppp" restricted:NO];
    [hidejb addPath:@"/etc/protocols" restricted:NO];
    [hidejb addPath:@"/etc/racoon" restricted:NO];
    [hidejb addPath:@"/etc/services" restricted:NO];
    [hidejb addPath:@"/etc/ttys" restricted:NO];
    
    // Restrict /Library by whitelisting
    [hidejb addPath:@"/Library" restricted:YES hidden:NO];
    [hidejb addPath:@"/Library/Application Support" restricted:YES hidden:NO];
    [hidejb addPath:@"/Library/Application Support/AggregateDictionary" restricted:NO];
    [hidejb addPath:@"/Library/Application Support/BTServer" restricted:NO];
    [hidejb addPath:@"/Library/Audio" restricted:NO];
    [hidejb addPath:@"/Library/Caches" restricted:NO];
    [hidejb addPath:@"/Library/Caches/cy-" restricted:YES];
    [hidejb addPath:@"/Library/Filesystems" restricted:NO];
    [hidejb addPath:@"/Library/Internet Plug-Ins" restricted:NO];
    [hidejb addPath:@"/Library/Keychains" restricted:NO];
    [hidejb addPath:@"/Library/LaunchAgents" restricted:NO];
    [hidejb addPath:@"/Library/LaunchDaemons" restricted:YES hidden:NO];
    [hidejb addPath:@"/Library/Logs" restricted:NO];
    [hidejb addPath:@"/Library/Managed Preferences" restricted:NO];
    [hidejb addPath:@"/Library/MobileDevice" restricted:NO];
    [hidejb addPath:@"/Library/MusicUISupport" restricted:NO];
    [hidejb addPath:@"/Library/Preferences" restricted:NO];
    [hidejb addPath:@"/Library/Printers" restricted:NO];
    [hidejb addPath:@"/Library/Ringtones" restricted:NO];
    [hidejb addPath:@"/Library/Updates" restricted:NO];
    [hidejb addPath:@"/Library/Wallpaper" restricted:NO];
    
    // Restrict /tmp
    [hidejb addPath:@"/tmp" restricted:NO];
    [hidejb addPath:@"/tmp/substrate" restricted:YES];
    [hidejb addPath:@"/tmp/Substrate" restricted:YES];
    [hidejb addPath:@"/tmp/cydia.log" restricted:YES];
    [hidejb addPath:@"/tmp/syslog" restricted:YES];
    [hidejb addPath:@"/tmp/slide.txt" restricted:YES];
    [hidejb addPath:@"/tmp/amfidebilitate.out" restricted:YES];
    [hidejb addPath:@"/tmp/org.coolstar" restricted:YES];

    // Restrict /var by whitelisting
    [hidejb addPath:@"/var" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/.DocumentRevisions" restricted:NO];
    [hidejb addPath:@"/var/.fseventsd" restricted:NO];
    [hidejb addPath:@"/var/.overprovisioning_file" restricted:NO];
    [hidejb addPath:@"/var/audit" restricted:NO];
    [hidejb addPath:@"/var/backups" restricted:NO];
    [hidejb addPath:@"/var/buddy" restricted:NO];
    [hidejb addPath:@"/var/containers" restricted:NO];
    [hidejb addPath:@"/var/containers/Bundle" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/containers/Bundle/Application" restricted:NO];
    [hidejb addPath:@"/var/containers/Bundle/Framework" restricted:NO];
    [hidejb addPath:@"/var/containers/Bundle/PluginKitPlugin" restricted:NO];
    [hidejb addPath:@"/var/containers/Bundle/VPNPlugin" restricted:NO];
    [hidejb addPath:@"/var/cores" restricted:NO];
    [hidejb addPath:@"/var/db" restricted:NO];
    [hidejb addPath:@"/var/db/stash" restricted:YES];
    [hidejb addPath:@"/var/ea" restricted:NO];
    [hidejb addPath:@"/var/empty" restricted:NO];
    [hidejb addPath:@"/var/folders" restricted:NO];
    [hidejb addPath:@"/var/hardware" restricted:NO];
    [hidejb addPath:@"/var/installd" restricted:NO];
    [hidejb addPath:@"/var/internal" restricted:NO];
    [hidejb addPath:@"/var/keybags" restricted:NO];
    [hidejb addPath:@"/var/Keychains" restricted:NO];
    [hidejb addPath:@"/var/lib" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/local" restricted:NO];
    [hidejb addPath:@"/var/lock" restricted:NO];
    [hidejb addPath:@"/var/log" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/log/asl" restricted:NO];
    [hidejb addPath:@"/var/log/com.apple.xpc.launchd" restricted:NO];
    [hidejb addPath:@"/var/log/corecaptured.log" restricted:NO];
    [hidejb addPath:@"/var/log/ppp" restricted:NO];
    [hidejb addPath:@"/var/log/ppp.log" restricted:NO];
    [hidejb addPath:@"/var/log/racoon.log" restricted:NO];
    [hidejb addPath:@"/var/log/sa" restricted:NO];
    [hidejb addPath:@"/var/logs" restricted:NO];
    [hidejb addPath:@"/var/Managed Preferences" restricted:NO];
    [hidejb addPath:@"/var/MobileAsset" restricted:NO];
    [hidejb addPath:@"/var/MobileDevice" restricted:NO];
    [hidejb addPath:@"/var/MobileSoftwareUpdate" restricted:NO];
    [hidejb addPath:@"/var/msgs" restricted:NO];
    [hidejb addPath:@"/var/networkd" restricted:NO];
    [hidejb addPath:@"/var/preferences" restricted:NO];
    [hidejb addPath:@"/var/root" restricted:NO];
    [hidejb addPath:@"/var/run" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/run/lockdown" restricted:NO];
    [hidejb addPath:@"/var/run/lockdown.sock" restricted:NO];
    [hidejb addPath:@"/var/run/lockdown_first_run" restricted:NO];
    [hidejb addPath:@"/var/run/mDNSResponder" restricted:NO];
    [hidejb addPath:@"/var/run/printd" restricted:NO];
    [hidejb addPath:@"/var/run/syslog" restricted:NO];
    [hidejb addPath:@"/var/run/syslog.pid" restricted:NO];
    [hidejb addPath:@"/var/run/utmpx" restricted:NO];
    [hidejb addPath:@"/var/run/vpncontrol.sock" restricted:NO];
    [hidejb addPath:@"/var/run/asl_input" restricted:NO];
    [hidejb addPath:@"/var/run/configd.pid" restricted:NO];
    [hidejb addPath:@"/var/run/lockbot" restricted:NO];
    [hidejb addPath:@"/var/run/pppconfd" restricted:NO];
    [hidejb addPath:@"/var/run/fudinit" restricted:NO];
    [hidejb addPath:@"/var/spool" restricted:NO];
    [hidejb addPath:@"/var/staged_system_apps" restricted:NO];
    [hidejb addPath:@"/var/tmp" restricted:NO];
    [hidejb addPath:@"/var/vm" restricted:NO];
    [hidejb addPath:@"/var/wireless" restricted:NO];
    
    // Restrict /var/mobile by whitelisting
    [hidejb addPath:@"/var/mobile" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Applications" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/Application" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/InternalDaemon" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/PluginKitPlugin" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/TempDir" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/VPNPlugin" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Data/XPCService" restricted:NO];
    [hidejb addPath:@"/var/mobile/Containers/Shared" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Containers/Shared/AppGroup" restricted:NO];
    [hidejb addPath:@"/var/mobile/Documents" restricted:NO];
    [hidejb addPath:@"/var/mobile/Downloads" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/com.apple" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/.com.apple" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/AdMob" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/AccountMigrationInProgress" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/ACMigrationLock" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/BTAvrcp" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/cache" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/Checkpoint.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/ckkeyrolld" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/CloudKit" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/DateFormats.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/FamilyCircle" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/GameKit" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/GeoServices" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/AccountMigrationInProgress" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/MappedImageCache" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/OTACrashCopier" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/PassKit" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/rtcreportingd" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/sharedCaches" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/Snapshots" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/Snapshots/com.apple" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/TelephonyUI" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Caches/Weather" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/ControlCenter" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Cydia" restricted:YES];
    [hidejb addPath:@"/var/mobile/Library/Logs/Cydia" restricted:YES];
    [hidejb addPath:@"/var/mobile/Library/SBSettings" restricted:YES];
    [hidejb addPath:@"/var/mobile/Library/Sileo" restricted:YES];
    [hidejb addPath:@"/var/mobile/Library/Preferences" restricted:YES hidden:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/com.apple." restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/.GlobalPreferences.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/ckkeyrolld.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/nfcd.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/UITextInputContextIdentifiers.plist" restricted:NO];
    [hidejb addPath:@"/var/mobile/Library/Preferences/Wallpaper.png" restricted:NO];
    [hidejb addPath:@"/var/mobile/Media" restricted:NO];
    [hidejb addPath:@"/var/mobile/MobileSoftwareUpdate" restricted:NO];

    // Restrict /usr by whitelisting
    [hidejb addPath:@"/usr" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/bin" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/bin/DumpBasebandCrash" restricted:NO];
    [hidejb addPath:@"/usr/bin/PerfPowerServicesExtended" restricted:NO];
    [hidejb addPath:@"/usr/bin/abmlite" restricted:NO];
    [hidejb addPath:@"/usr/bin/brctl" restricted:NO];
    [hidejb addPath:@"/usr/bin/footprint" restricted:NO];
    [hidejb addPath:@"/usr/bin/hidutil" restricted:NO];
    [hidejb addPath:@"/usr/bin/hpmdiagnose" restricted:NO];
    [hidejb addPath:@"/usr/bin/kbdebug" restricted:NO];
    [hidejb addPath:@"/usr/bin/powerlogHelperd" restricted:NO];
    [hidejb addPath:@"/usr/bin/sysdiagnose" restricted:NO];
    [hidejb addPath:@"/usr/bin/tailspin" restricted:NO];
    [hidejb addPath:@"/usr/bin/taskinfo" restricted:NO];
    [hidejb addPath:@"/usr/bin/vm_stat" restricted:NO];
    [hidejb addPath:@"/usr/bin/zprint" restricted:NO];
    [hidejb addPath:@"/usr/lib" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/lib/FDRSealingMap.plist" restricted:NO];
    [hidejb addPath:@"/usr/lib/bbmasks" restricted:NO];
    [hidejb addPath:@"/usr/lib/dyld" restricted:NO];
    [hidejb addPath:@"/usr/lib/libCRFSuite" restricted:NO];
    [hidejb addPath:@"/usr/lib/libDHCPServer" restricted:NO];
    [hidejb addPath:@"/usr/lib/libMatch" restricted:NO];
    [hidejb addPath:@"/usr/lib/libSystem" restricted:NO];
    [hidejb addPath:@"/usr/lib/libarchive" restricted:NO];
    [hidejb addPath:@"/usr/lib/libbsm" restricted:NO];
    [hidejb addPath:@"/usr/lib/libbz2" restricted:NO];
    [hidejb addPath:@"/usr/lib/libc++" restricted:NO];
    [hidejb addPath:@"/usr/lib/libc" restricted:NO];
    [hidejb addPath:@"/usr/lib/libcharset" restricted:NO];
    [hidejb addPath:@"/usr/lib/libcurses" restricted:NO];
    [hidejb addPath:@"/usr/lib/libdbm" restricted:NO];
    [hidejb addPath:@"/usr/lib/libdl" restricted:NO];
    [hidejb addPath:@"/usr/lib/libeasyperf" restricted:NO];
    [hidejb addPath:@"/usr/lib/libedit" restricted:NO];
    [hidejb addPath:@"/usr/lib/libexslt" restricted:NO];
    [hidejb addPath:@"/usr/lib/libextension" restricted:NO];
    [hidejb addPath:@"/usr/lib/libform" restricted:NO];
    [hidejb addPath:@"/usr/lib/libiconv" restricted:NO];
    [hidejb addPath:@"/usr/lib/libicucore" restricted:NO];
    [hidejb addPath:@"/usr/lib/libinfo" restricted:NO];
    [hidejb addPath:@"/usr/lib/libipsec" restricted:NO];
    [hidejb addPath:@"/usr/lib/liblzma" restricted:NO];
    [hidejb addPath:@"/usr/lib/libm" restricted:NO];
    [hidejb addPath:@"/usr/lib/libmecab" restricted:NO];
    [hidejb addPath:@"/usr/lib/libncurses" restricted:NO];
    [hidejb addPath:@"/usr/lib/libobjc" restricted:NO];
    [hidejb addPath:@"/usr/lib/libpcap" restricted:NO];
    [hidejb addPath:@"/usr/lib/libpmsample" restricted:NO];
    [hidejb addPath:@"/usr/lib/libpoll" restricted:NO];
    [hidejb addPath:@"/usr/lib/libproc" restricted:NO];
    [hidejb addPath:@"/usr/lib/libpthread" restricted:NO];
    [hidejb addPath:@"/usr/lib/libresolv" restricted:NO];
    [hidejb addPath:@"/usr/lib/librpcsvc" restricted:NO];
    [hidejb addPath:@"/usr/lib/libsandbox" restricted:NO];
    [hidejb addPath:@"/usr/lib/libsqlite3" restricted:NO];
    [hidejb addPath:@"/usr/lib/libstdc++" restricted:NO];
    [hidejb addPath:@"/usr/lib/libtidy" restricted:NO];
    [hidejb addPath:@"/usr/lib/libutil" restricted:NO];
    [hidejb addPath:@"/usr/lib/libxml2" restricted:NO];
    [hidejb addPath:@"/usr/lib/libxslt" restricted:NO];
    [hidejb addPath:@"/usr/lib/libz" restricted:NO];
    [hidejb addPath:@"/usr/lib/libperfcheck" restricted:NO];
    [hidejb addPath:@"/usr/lib/libedit" restricted:NO];
    [hidejb addPath:@"/usr/lib/log" restricted:NO];
    [hidejb addPath:@"/usr/lib/system" restricted:NO];
    [hidejb addPath:@"/usr/lib/updaters" restricted:NO];
    [hidejb addPath:@"/usr/lib/xpc" restricted:NO];
    [hidejb addPath:@"/usr/libexec" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/libexec/BackupAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/BackupAgent2" restricted:NO];
    [hidejb addPath:@"/usr/libexec/CrashHousekeeping" restricted:NO];
    [hidejb addPath:@"/usr/libexec/DataDetectorsSourceAccess" restricted:NO];
    [hidejb addPath:@"/usr/libexec/FSTaskScheduler" restricted:NO];
    [hidejb addPath:@"/usr/libexec/FinishRestoreFromBackup" restricted:NO];
    [hidejb addPath:@"/usr/libexec/IOAccelMemoryInfoCollector" restricted:NO];
    [hidejb addPath:@"/usr/libexec/IOMFB_bics_daemon" restricted:NO];
    [hidejb addPath:@"/usr/libexec/Library" restricted:NO];
    [hidejb addPath:@"/usr/libexec/MobileGestaltHelper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/MobileStorageMounter" restricted:NO];
    [hidejb addPath:@"/usr/libexec/NANDTaskScheduler" restricted:NO];
    [hidejb addPath:@"/usr/libexec/OTATaskingAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/PowerUIAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/PreboardService" restricted:NO];
    [hidejb addPath:@"/usr/libexec/ProxiedCrashCopier" restricted:NO];
    [hidejb addPath:@"/usr/libexec/PurpleReverseProxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/ReportMemoryException" restricted:NO];
    [hidejb addPath:@"/usr/libexec/SafariCloudHistoryPushAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/SidecarRelay" restricted:NO];
    [hidejb addPath:@"/usr/libexec/SyncAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/UserEventAgent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/addressbooksyncd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/adid" restricted:NO];
    [hidejb addPath:@"/usr/libexec/adprivacyd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/adservicesd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/afcd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/airtunesd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/amfid" restricted:NO];
    [hidejb addPath:@"/usr/libexec/asd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/assertiond" restricted:NO];
    [hidejb addPath:@"/usr/libexec/atc" restricted:NO];
    [hidejb addPath:@"/usr/libexec/atwakeup" restricted:NO];
    [hidejb addPath:@"/usr/libexec/backboardd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/biometrickitd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/bootpd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/bulletindistributord" restricted:NO];
    [hidejb addPath:@"/usr/libexec/captiveagent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/cc_fips_test" restricted:NO];
    [hidejb addPath:@"/usr/libexec/checkpointd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/cloudpaird" restricted:NO];
    [hidejb addPath:@"/usr/libexec/com.apple.automation.defaultslockdownserviced" restricted:NO];
    [hidejb addPath:@"/usr/libexec/companion_proxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/configd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/corecaptured" restricted:NO];
    [hidejb addPath:@"/usr/libexec/coreduetd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/crash_mover" restricted:NO];
    [hidejb addPath:@"/usr/libexec/dasd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/demod" restricted:NO];
    [hidejb addPath:@"/usr/libexec/demod_helper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/dhcpd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/diagnosticd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/diagnosticextensionsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/dmd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/dprivacyd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/dtrace" restricted:NO];
    [hidejb addPath:@"/usr/libexec/duetexpertd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/eventkitsyncd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/fdrhelper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/findmydeviced" restricted:NO];
    [hidejb addPath:@"/usr/libexec/finish_demo_restore" restricted:NO];
    [hidejb addPath:@"/usr/libexec/fmfd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/fmflocatord" restricted:NO];
    [hidejb addPath:@"/usr/libexec/fseventsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/ftp-proxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/gamecontrollerd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/gamed" restricted:NO];
    [hidejb addPath:@"/usr/libexec/gpsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/hangreporter" restricted:NO];
    [hidejb addPath:@"/usr/libexec/hangtracerd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/heartbeatd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/hostapd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/idamd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/init_data_protection -> seputil" restricted:NO];
    [hidejb addPath:@"/usr/libexec/installd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/ioupsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/keybagd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/languageassetd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/locationd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/lockdownd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/logd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/lsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/lskdd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/lskdmsed" restricted:NO];
    [hidejb addPath:@"/usr/libexec/magicswitchd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mc_mobile_tunnel" restricted:NO];
    [hidejb addPath:@"/usr/libexec/microstackshot" restricted:NO];
    [hidejb addPath:@"/usr/libexec/misagent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/misd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mmaintenanced" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_assertion_agent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_diagnostics_relay" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_house_arrest" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_installation_proxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_obliterator" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobile_storage_proxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobileactivationd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobileassetd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mobilewatchdog" restricted:NO];
    [hidejb addPath:@"/usr/libexec/mtmergeprops" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nanomediaremotelinkagent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nanoregistryd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nanoregistrylaunchd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/neagent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nehelper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nesessionmanager" restricted:NO];
    [hidejb addPath:@"/usr/libexec/networkserviceproxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nfcd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nfrestore_service" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nlcd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/notification_proxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nptocompaniond" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nsurlsessiond" restricted:NO];
    [hidejb addPath:@"/usr/libexec/nsurlstoraged" restricted:NO];
    [hidejb addPath:@"/usr/libexec/online-auth-agent" restricted:NO];
    [hidejb addPath:@"/usr/libexec/oscard" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pcapd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pcsstatus" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pfd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pipelined" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pkd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/pkreporter" restricted:NO];
    [hidejb addPath:@"/usr/libexec/ptpd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/rapportd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/replayd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/resourcegrabberd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/rolld" restricted:NO];
    [hidejb addPath:@"/usr/libexec/routined" restricted:NO];
    [hidejb addPath:@"/usr/libexec/rtbuddyd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/rtcreportingd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/safarifetcherd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/screenshotsyncd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/security-sysdiagnose" restricted:NO];
    [hidejb addPath:@"/usr/libexec/securityd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/securityuploadd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/seld" restricted:NO];
    [hidejb addPath:@"/usr/libexec/seputil" restricted:NO];
    [hidejb addPath:@"/usr/libexec/sharingd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/signpost_reporter" restricted:NO];
    [hidejb addPath:@"/usr/libexec/silhouette" restricted:NO];
    [hidejb addPath:@"/usr/libexec/siriknowledged" restricted:NO];
    [hidejb addPath:@"/usr/libexec/smcDiagnose" restricted:NO];
    [hidejb addPath:@"/usr/libexec/splashboardd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/springboardservicesrelay" restricted:NO];
    [hidejb addPath:@"/usr/libexec/streaming_zip_conduit" restricted:NO];
    [hidejb addPath:@"/usr/libexec/swcd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/symptomsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/symptomsd-helper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/sysdiagnose_helper" restricted:NO];
    [hidejb addPath:@"/usr/libexec/sysstatuscheck" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tailspind" restricted:NO];
    [hidejb addPath:@"/usr/libexec/timed" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tipsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/topicsmap.db" restricted:NO];
    [hidejb addPath:@"/usr/libexec/transitd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/trustd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tursd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tzd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tzinit" restricted:NO];
    [hidejb addPath:@"/usr/libexec/tzlinkd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/videosubscriptionsd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/wapic" restricted:NO];
    [hidejb addPath:@"/usr/libexec/wcd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/webbookmarksd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/webinspectord" restricted:NO];
    [hidejb addPath:@"/usr/libexec/wifiFirmwareLoader" restricted:NO];
    [hidejb addPath:@"/usr/libexec/wifivelocityd" restricted:NO];
    [hidejb addPath:@"/usr/libexec/xpcproxy" restricted:NO];
    [hidejb addPath:@"/usr/libexec/xpcroleaccountd" restricted:NO];
    [hidejb addPath:@"/usr/local" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/local/bin" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/local/lib" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/local/standalone" restricted:NO];
    [hidejb addPath:@"/usr/sbin" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/sbin/BTAvrcp" restricted:NO];
    [hidejb addPath:@"/usr/sbin/BTLEServer" restricted:NO];
    [hidejb addPath:@"/usr/sbin/BTMap" restricted:NO];
    [hidejb addPath:@"/usr/sbin/BTPbap" restricted:NO];
    [hidejb addPath:@"/usr/sbin/BlueTool" restricted:NO];
    [hidejb addPath:@"/usr/sbin/WiFiNetworkStoreModel.momd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/WirelessRadioManagerd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/absd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/addNetworkInterface" restricted:NO];
    [hidejb addPath:@"/usr/sbin/applecamerad" restricted:NO];
    [hidejb addPath:@"/usr/sbin/aslmanager" restricted:NO];
    [hidejb addPath:@"/usr/sbin/bluetoothd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/cfprefsd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/ckksctl" restricted:NO];
    [hidejb addPath:@"/usr/sbin/distnoted" restricted:NO];
    [hidejb addPath:@"/usr/sbin/fairplayd.H2" restricted:NO];
    [hidejb addPath:@"/usr/sbin/filecoordinationd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/ioreg" restricted:NO];
    [hidejb addPath:@"/usr/sbin/ipconfig" restricted:NO];
    [hidejb addPath:@"/usr/sbin/mDNSResponder" restricted:NO];
    [hidejb addPath:@"/usr/sbin/mDNSResponderHelper" restricted:NO];
    [hidejb addPath:@"/usr/sbin/mediaserverd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/notifyd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/nvram" restricted:NO];
    [hidejb addPath:@"/usr/sbin/pppd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/racoon" restricted:NO];
    [hidejb addPath:@"/usr/sbin/rtadvd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/scutil" restricted:NO];
    [hidejb addPath:@"/usr/sbin/spindump" restricted:NO];
    [hidejb addPath:@"/usr/sbin/syslogd" restricted:NO];
    [hidejb addPath:@"/usr/sbin/wifid" restricted:NO];
    [hidejb addPath:@"/usr/sbin/wirelessproxd" restricted:NO];
    [hidejb addPath:@"/usr/share" restricted:YES hidden:NO];
    [hidejb addPath:@"/usr/share/com.apple.languageassetd" restricted:NO];
    [hidejb addPath:@"/usr/share/CSI" restricted:NO];
    [hidejb addPath:@"/usr/share/firmware" restricted:NO];
    [hidejb addPath:@"/usr/share/icu" restricted:NO];
    [hidejb addPath:@"/usr/share/langid" restricted:NO];
    [hidejb addPath:@"/usr/share/locale" restricted:NO];
    [hidejb addPath:@"/usr/share/mecabra" restricted:NO];
    [hidejb addPath:@"/usr/share/misc" restricted:NO];
    [hidejb addPath:@"/usr/share/progressui" restricted:NO];
    [hidejb addPath:@"/usr/share/tokenizer" restricted:NO];
    [hidejb addPath:@"/usr/share/zoneinfo" restricted:NO];
    [hidejb addPath:@"/usr/share/zoneinfo.default" restricted:NO];
    [hidejb addPath:@"/usr/standalone" restricted:NO];

    // Restrict /System
    [hidejb addPath:@"/System" restricted:NO];
    [hidejb addPath:@"/System/Library/PreferenceBundles/AppList.bundle" restricted:YES];
    [hidejb addPath:@"/System/Library/Caches/apticket.der" restricted:YES];
}

// Manual hooks
#include <dirent.h>

static int (*orig_open)(const char *path, int oflag, ...);
static int hook_open(const char *path, int oflag, ...) {
    int result = 0;

    if(path) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:path]]) {
            errno = ((oflag & O_CREAT) == O_CREAT) ? EACCES : ENOENT;
            return -1;
        }
    }
    
    if((oflag & O_CREAT) == O_CREAT) {
        mode_t mode;
        va_list args;
        
        va_start(args, oflag);
        mode = (mode_t) va_arg(args, int);
        va_end(args);

        result = orig_open(path, oflag, mode);
    } else {
        result = orig_open(path, oflag);
    }

    return result;
}

static int (*orig_openat)(int fd, const char *path, int oflag, ...);
static int hook_openat(int fd, const char *path, int oflag, ...) {
    int result = 0;

    if(path) {
        NSString *nspath = [NSString stringWithUTF8String:path];

        if(![nspath isAbsolutePath]) {
            // Get path of dirfd.
            char dirfdpath[PATH_MAX];
        
            if(fcntl(fd, F_GETPATH, dirfdpath) != -1) {
                NSString *dirfd_path = [NSString stringWithUTF8String:dirfdpath];
                nspath = [dirfd_path stringByAppendingPathComponent:nspath];
            }
        }
        
        if([_hidejb isPathRestricted:nspath]) {
            errno = ((oflag & O_CREAT) == O_CREAT) ? EACCES : ENOENT;
            return -1;
        }
    }
    
    if((oflag & O_CREAT) == O_CREAT) {
        mode_t mode;
        va_list args;
        
        va_start(args, oflag);
        mode = (mode_t) va_arg(args, int);
        va_end(args);

        result = orig_openat(fd, path, oflag, mode);
    } else {
        result = orig_openat(fd, path, oflag);
    }

    return result;
}

static DIR *(*orig_opendir)(const char *filename);
static DIR *hook_opendir(const char *filename) {
    if(filename) {
        if([_hidejb isPathRestricted:[NSString stringWithUTF8String:filename]]) {
            errno = ENOENT;
            return NULL;
        }
    }

    return orig_opendir(filename);
}

static struct dirent *(*orig_readdir)(DIR *dirp);
static struct dirent *hook_readdir(DIR *dirp) {
    struct dirent *ret = NULL;
    NSString *path = nil;

    // Get path of dirfd.
    NSString *dirfd_path = nil;
    int fd = dirfd(dirp);
    char dirfdpath[PATH_MAX];

    if(fcntl(fd, F_GETPATH, dirfdpath) != -1) {
        dirfd_path = [NSString stringWithUTF8String:dirfdpath];
    } else {
        return orig_readdir(dirp);
    }

    // Filter returned results, skipping over restricted paths.
    do {
        ret = orig_readdir(dirp);

        if(ret) {
            path = [dirfd_path stringByAppendingPathComponent:[NSString stringWithUTF8String:ret->d_name]];
        } else {
            break;
        }
    } while([_hidejb isPathRestricted:path]);

    return ret;
}

#include <dlfcn.h>

static int (*orig_dladdr)(const void *addr, Dl_info *info);
static int hook_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);

    if(ret) {
        NSString *path = [NSString stringWithUTF8String:info->dli_fname];

        if([_hidejb isImageRestricted:path]) {
            return 0;
        }
    }

    return ret;
}

static ssize_t (*orig_readlink)(const char *path, char *buf, size_t bufsiz);
static ssize_t hook_readlink(const char *path, char *buf, size_t bufsiz) {
    if(!path || !buf) {
        return orig_readlink(path, buf, bufsiz);
    }

    NSString *nspath = [NSString stringWithUTF8String:path];

    if([_hidejb isPathRestricted:nspath]) {
        errno = ENOENT;
        return -1;
    }

    ssize_t ret = orig_readlink(path, buf, bufsiz);

    if(ret != -1) {
        buf[ret] = '\0';

        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:nspath toPath:[NSString stringWithUTF8String:buf]];
    }

    return ret;
}

static ssize_t (*orig_readlinkat)(int fd, const char *path, char *buf, size_t bufsiz);
static ssize_t hook_readlinkat(int fd, const char *path, char *buf, size_t bufsiz) {
    if(!path || !buf) {
        return orig_readlinkat(fd, path, buf, bufsiz);
    }

    NSString *nspath = [NSString stringWithUTF8String:path];

    if(![nspath isAbsolutePath]) {
        // Get path of dirfd.
        char dirfdpath[PATH_MAX];
    
        if(fcntl(fd, F_GETPATH, dirfdpath) != -1) {
            NSString *dirfd_path = [NSString stringWithUTF8String:dirfdpath];
            nspath = [dirfd_path stringByAppendingPathComponent:nspath];
        }
    }

    if([_hidejb isPathRestricted:nspath]) {
        errno = ENOENT;
        return -1;
    }

    ssize_t ret = orig_readlinkat(fd, path, buf, bufsiz);

    if(ret != -1) {
        buf[ret] = '\0';

        // Track this symlink in HideJB
        [_hidejb addLinkFromPath:nspath toPath:[NSString stringWithUTF8String:buf]];
    }

    return ret;
}

void updateDyldArray(void) {
    dyld_array_count = 0;
    dyld_array = [_hidejb generateDyldArray];
    dyld_array_count = (uint32_t) [dyld_array count];

    NSLog(@"generated dyld array (%d items)", dyld_array_count);
}

%group hook_springboard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    if(![[NSFileManager defaultManager] fileExistsAtPath:@"/var/lib/dpkg/info/com.thuthuatjb.hidejb.md5sums"]) {
        // Tweak was not installed properly. Notify the user.
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thank for install" message:@"Có vẻ như bạn đã tải về HideJB không phải từ TTJB Repo. Các tweak được cung cấp bởi chúng tôi đã được kiểm duyệt kĩ để đảm bảo tính tương thích và không chứa phần mềm độc hại. Hãy gỡ bỏ và tải về nó từ nguồn của TTJB\n It looks like you downloaded HideJB not from TTJB Repo. The tweaks provided by us have been moderated to ensure compatibility and contain no malware. Please remove and download it from TTJB Source\nThank!" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:@"repo.thuthuatjb.com" style:UIAlertActionStyleDefault handler:nil];

        [alert addAction:action];
        [[[application keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];
    }

    HBPreferences *prefs = [HBPreferences preferencesForIdentifier:PREFS_TWEAK_ID];

    [prefs registerDefaults:@{
        @"enabled_hidejb" : @YES,
        @"mode" : @"blacklist",
        @"enabled_bypass_checks" : @YES,
        @"enabled_exclude_safe_apps" : @YES,
        @"auto_file_map_generation_enabled" : @YES
    }];

    if([prefs boolForKey:@"auto_file_map_generation_enabled"]) {
        HBPreferences *prefs = [HBPreferences preferencesForIdentifier:BLACKLIST_PATH];

        NSArray *file_map = [HideJB generateFileMap];
        NSArray *url_set = [HideJB generateSchemeArray];

        [prefs setObject:file_map forKey:@"files"];
        [prefs setObject:url_set forKey:@"schemes"];
    }
}
%end
%end

%ctor {
    NSString *processName = [[NSProcessInfo processInfo] processName];

    if([processName isEqualToString:@"SpringBoard"]) {
        %init(hook_springboard);
        return;
    }

    NSBundle *bundle = [NSBundle mainBundle];

    if(bundle != nil) {
        NSString *executablePath = [bundle executablePath];
        NSString *bundleIdentifier = [bundle bundleIdentifier];

        // User (Sandboxed) Applications
        if([executablePath hasPrefix:@"/var/containers/Bundle/Application"]) {
            NSLog(@"bundleIdentifier: %@", bundleIdentifier);

            HBPreferences *prefs_blacklist = [HBPreferences preferencesForIdentifier:BLACKLIST_PATH];
            HBPreferences *prefs_tweakcompat = [HBPreferences preferencesForIdentifier:TWEAKCOMPAT_PATH];
            HBPreferences *prefs_injectcompat = [HBPreferences preferencesForIdentifier:INJECTCOMPAT_PATH];
            HBPreferences *prefs_lockdown = [HBPreferences preferencesForIdentifier:LOCKDOWN_PATH];
            HBPreferences *prefs_dlfcn = [HBPreferences preferencesForIdentifier:DLFCN_PATH];
            HBPreferences *prefs_apps = [HBPreferences preferencesForIdentifier:APPS_PATH];
            HBPreferences *prefs = [HBPreferences preferencesForIdentifier:PREFS_TWEAK_ID];

            [prefs registerDefaults:@{
                @"enabled_hidejb" : @YES,
                @"mode" : @"blacklist",
                @"enabled_bypass_checks" : @YES,
                @"enabled_exclude_safe_apps" : @YES,
                @"auto_file_map_generation_enabled" : @YES
            }];
            
            // Check if HideJB is enabled
            if(![prefs boolForKey:@"enabled"]) {
                // HideJB disabled in preferences
                return;
            }

            // Check if safe bundleIdentifier
            if([prefs boolForKey:@"enabled_exclude_safe_apps"]) {
                // Disable HideJB for Apple and jailbreak apps
                NSArray *excluded_bundleids = @[
                    @"com.apple", // Apple apps
                    @"is.workflow.my.app", // Shortcuts
                    @"science.xnu.undecimus", // unc0ver
                    @"com.electrateam.chimera", // Chimera
                    @"org.coolstar.electra", // Electra
                    @"us.diatr.undecimus" // unc0ver dark				
                ];

                for(NSString *bundle_id in excluded_bundleids) {
                    if([bundleIdentifier hasPrefix:bundle_id]) {
                        return;
                    }
                }
            }

            // Check if excluded bundleIdentifier
            NSString *mode = [prefs objectForKey:@"mode"];

            if([mode isEqualToString:@"whitelist"]) {
                // Whitelist - disable HideJB if not enabled for this bundleIdentifier
                if(![prefs_apps boolForKey:bundleIdentifier]) {
                    return;
                }
            } else {
                // Blacklist - disable HideJB if enabled for this bundleIdentifier
                if([prefs_apps boolForKey:bundleIdentifier]) {
                    return;
                }
            }

            // Initialize HideJB
            _hidejb = [HideJB new];

            if(!_hidejb) {
                NSLog(@"failed to initialize HideJB");
                return;
            }

            // Initialize restricted path map
            init_path_map(_hidejb);
            NSLog(@"initialized internal path map");

            // Initialize file map
            NSArray *file_map = [prefs_blacklist objectForKey:@"files"];
            NSArray *url_set = [prefs_blacklist objectForKey:@"schemes"];

            if(file_map) {
                [_hidejb addPathsFromFileMap:file_map];

                NSLog(@"initialized file map (%lu items)", (unsigned long) [file_map count]);
            }

            if(url_set) {
                [_hidejb addSchemesFromURLSet:url_set];

                NSLog(@"initialized url set (%lu items)", (unsigned long) [url_set count]);
            }

            // Compatibility mode
            [_hidejb setUseTweakCompatibilityMode:[prefs_tweakcompat boolForKey:bundleIdentifier] ? NO : YES];
            [_hidejb setUseInjectCompatibilityMode:[prefs_injectcompat boolForKey:bundleIdentifier] ? NO : YES];

            // Disable inject compatibility if we are using Substitute.
            BOOL isSubstitute = [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/libsubstitute.dylib"];

            if(isSubstitute) {
                [_hidejb setUseInjectCompatibilityMode:NO];
            }

            // Lockdown mode
            if([prefs_lockdown boolForKey:bundleIdentifier]) {
                %init(hook_libc_inject);
                %init(hook_dlopen_inject);

                MSHookFunction((void *) open, (void *) hook_open, (void **) &orig_open);
                MSHookFunction((void *) openat, (void *) hook_openat, (void **) &orig_openat);

                [_hidejb setUseInjectCompatibilityMode:NO];
                [_hidejb setUseTweakCompatibilityMode:NO];

                NSLog(@"enabled lockdown mode");
            }

            if([_hidejb useInjectCompatibilityMode]) {
                NSLog(@"using injection compatibility mode");
            } else {
                // Substitute doesn't like hooking opendir :(
                if(!isSubstitute) {
                    MSHookFunction((void *) opendir, (void *) hook_opendir, (void **) &orig_opendir);
                }

                MSHookFunction((void *) readdir, (void *) hook_readdir, (void **) &orig_readdir);
            }

            if([_hidejb useTweakCompatibilityMode]) {
                NSLog(@"using tweak compatibility mode");
            }

            // Initialize stable hooks
            %init(hook_private);
            %init(hook_libc);
            %init(hook_debugging);

            %init(hook_NSFileHandle);
            %init(hook_NSFileManager);
            %init(hook_NSURL);
            %init(hook_UIApplication);
            %init(hook_NSBundle);
            %init(hook_NSUtilities);
            %init(hook_NSEnumerator);

            MSHookFunction((void *) readlink, (void *) hook_readlink, (void **) &orig_readlink);
            MSHookFunction((void *) readlinkat, (void *) hook_readlinkat, (void **) &orig_readlinkat);

            NSLog(@"hooked bypass methods");

            // Initialize other hooks
            if([prefs boolForKey:@"enabled_bypass_checks"]) {
                %init(hook_libraries);

                NSLog(@"hooked detection libraries");
            }

            if([prefs boolForKey:@"enabled_dyld_hooks"] || [prefs_lockdown boolForKey:bundleIdentifier]) {
                %init(hook_dyld_image);

                NSLog(@"filtering dynamic libraries");
            }

            if([prefs boolForKey:@"enabled_lock_sandbox"] || [prefs_lockdown boolForKey:bundleIdentifier]) {
                %init(hook_sandbox);

                NSLog(@"hooked sandbox methods");
            }

            // Generate filtered dyld array
            if([prefs boolForKey:@"enabled_dyld_filter"] || [prefs_lockdown boolForKey:bundleIdentifier]) {
                updateDyldArray();

                %init(hook_dyld_advanced);
                %init(hook_CoreFoundation);
                MSHookFunction((void *) dladdr, (void *) hook_dladdr, (void **) &orig_dladdr);

                NSLog(@"enabled advanced dynamic library filtering");
            }

            if([prefs_dlfcn boolForKey:bundleIdentifier]) {
                %init(hook_dyld_dlsym);

                NSLog(@"hooked dynamic linker methods");
            }

            NSLog(@"ready");
        }
    }
}
