#import <UIKit/UIKit.h>

static BOOL hasShownAlert = NO;
static NSInteger screenshotCounter = 0;

// ---- 截图并保存 ----
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
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"XiangqiAssist"
                                                                           message:@"点按钮开始截图"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"开始截图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                screenshotCounter++;
                NSString *name = [NSString stringWithFormat:@"screen_%ld", (long)screenshotCounter];
                saveScreenshot(self.view, name);
                
                // 再弹一个确认
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已截图"
                                                                              message:[NSString stringWithFormat:@"保存为 %@.png", name]
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:done animated:YES completion:nil];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            
            [self presentViewController:alert animated:YES completion:nil];
        });
    }
}

%end
