#include "Preferences.h"

@implementation HideJBPrefsListController
- (instancetype)init {
    self = [super init];
    
    if (self) {
        HBAppearanceSettings *appearanceSettings = [[HBAppearanceSettings alloc] init];
        appearanceSettings.tintColor = [UIColor colorWithRed:0.1f green:0.1f blue:0.1f alpha:1];
        appearanceSettings.tableViewCellSeparatorColor = [UIColor colorWithWhite:0 alpha:0];
        self.hb_appearanceSettings = appearanceSettings;
    }
    
    return self;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Prefs" target:self] retain];
    }

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    CGRect frame = self.table.bounds;
    frame.origin.y = -frame.size.height;
    
    [self.navigationController.navigationController.navigationBar setShadowImage: [UIImage new]];
    self.navigationController.navigationController.navigationBar.translucent = YES;
}

- (void)scan_map:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scaning - Đang quét" message:@"Please wait...Xin chờ..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        NSArray *file_map = [HideJB generateFileMap];
        NSArray *url_set = [HideJB generateSchemeArray];

        HBPreferences *prefs = [HBPreferences preferencesForIdentifier:BLACKLIST_PATH];

        [prefs setObject:file_map forKey:@"files"];
        [prefs setObject:url_set forKey:@"schemes"];
        
        [alert dismissViewControllerAnimated:YES completion:nil];
    }];
}

- (void)respring:(id)sender {
    [HBRespringController respring];
}

- (void)reset:(id)sender {
    HBPreferences *prefs = [HBPreferences preferencesForIdentifier:PREFS_TWEAK_ID];
    HBPreferences *prefs_apps = [HBPreferences preferencesForIdentifier:APPS_PATH];
    HBPreferences *prefs_blacklist = [HBPreferences preferencesForIdentifier:BLACKLIST_PATH];

    [prefs removeAllObjects];
    [prefs_apps removeAllObjects];
    [prefs_blacklist removeAllObjects];
    
    [self respring:sender];
}
@end
