#import <Foundation/Foundation.h>

// Keep in sync with control and NextClockPrefs/Resources/Info.plist.
#ifdef NC_PRO_BUILD
#define NC_VERSION @"0.1.0~alpha1"
#elif defined(NC_LEGACY_BUILD)
#define NC_VERSION @"1.1.1~legacy1"
#else
#define NC_VERSION @"1.2.0~beta7"
#endif
