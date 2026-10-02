#import <UIKit/UIKit.h>

static BOOL hasShownAlert = NO;

static void saveScreenshot(UIView *view, NSString *name) {
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, 0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@.png", name]];
    [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    if (!hasShownAlert) {
        hasShownAlert = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 延迟 3 秒，等画面完全渲染
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                saveScreenshot(self.view, @"xiangqi_screen");
            });
        });
    }
}

%end
