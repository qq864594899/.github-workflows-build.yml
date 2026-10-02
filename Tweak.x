#import <UIKit/UIKit.h>

static BOOL hasShownAlert = NO;

static void writeLog(NSString *msg) {
    NSString *path = @"/var/mobile/Documents/xiangqi_log.txt";
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

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    if (!hasShownAlert) {
        hasShownAlert = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            writeLog(@"=== 开始打印视图层级 ===");
            [self dumpView:self.view level:0];
        });
    }
}

- (void)dumpView:(UIView *)view level:(NSInteger)level {
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < level; i++) [indent appendString:@"  "];
    NSString *line = [NSString stringWithFormat:@"%@%@ frame=%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame)];
    writeLog(line);
    for (UIView *sub in view.subviews) {
        [self dumpView:sub level:level + 1];
    }
}

%end
