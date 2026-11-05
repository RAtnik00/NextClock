#import "../Shared/NCModernContext.h"
static void Check(BOOL ok) { if (!ok) exit(1); }
int main(void) { @autoreleasepool {
    for (int enabled=0;enabled<2;enabled++)
        for (int attached=0;attached<2;attached++)
            for (int editing=0;editing<2;editing++)
                Check(NCModernShouldRender(enabled,attached,editing)==(enabled && attached && !editing));
    for (NSString *name in @[@"PRPosterSwitcherViewController",@"WallpaperPickerViewController",@"CSProminentSnapshotView",@"posterpreviewcontroller"])
        Check(NCModernIsPreviewContainer(name));
    for (NSString *name in @[@"PRPosterEditorView",@"PRPosterEditingViewController",@"CSProminentDisplayView",@"CSCoverSheetViewController",@"CSWallpaperView",@"UIView",@""])
        Check(!NCModernIsPreviewContainer(name));
    Check(NCModernVisibleAlpha(0)==0 && NCModernVisibleAlpha(1)==1);
    Check(NCModernVisibleAlpha(.35)==.35);
    Check(NCModernVisibleAlpha(-1)==0 && NCModernVisibleAlpha(2)==1);
    Check(NCModernVisibleAlpha(NAN)==0 && NCModernVisibleAlpha(INFINITY)==0);
    puts("PASS: disabled/detached/preview boundaries; live and editor containers eligible; exact intermediate system fades and invalid alpha bounds.");
} }
