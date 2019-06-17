#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CepheiPrefs/HBRootListController.h>
#import <CepheiPrefs/HBAppearanceSettings.h>
#import <Cephei/HBPreferences.h>
#import <Cephei/HBRespringController.h>
#import "../Includes/HideJB.h"

@interface HideJBPrefsListController : HBRootListController
- (void)generate_map:(id)sender;
- (void)respring:(id)sender;
- (void)reset:(id)sender;
@end
