#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CepheiPrefs/HBRootListController.h>
#import <CepheiPrefs/HBAppearanceSettings.h>
#import <Cephei/HBPreferences.h>
#import <Cephei/HBRespringController.h>
#import "../Includes/HideJB.h"

#include <spawn.h>

@interface HideJBPrefsListController : HBRootListController
- (void)scan_map:(id)sender;
- (void)reset:(id)sender;
@end
