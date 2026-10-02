#import <UIKit/UIKit.h>

static BOOL hasShownAlert = NO;

// ---- 日志工具：写到 App 自己的沙盒目录，不需要任何特殊权限 ----
static void writeLog(NSString *msg) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/xiangqi_log.txt"];
    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// ---- 递归打印视图层级 ----
static void dumpView(UIView *view, NSInteger level) {
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < level; i++) [indent appendString:@"  "];
    NSString *line = [NSString stringWithFormat:@"%@%@ frame=%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame)];
    writeLog(line);
    for (UIView *sub in view.subviews) {
        dumpView(sub, level + 1);
    }
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    if (!hasShownAlert) {
        hasShownAlert = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 1. 写日志
            writeLog(@"=== 开始打印视图层级 ===");
            dumpView(self.view, 0);
            writeLog(@"=== 打印结束 ===");
            
            // 2. 弹窗确认注入
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"XiangqiAssist"
                                                                           message:@"注入成功"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }
}

%end
