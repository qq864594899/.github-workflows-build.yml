#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static NSTimer *scanTimer = nil;
static BOOL isScanning = NO;
static NSInteger snapshotCounter = 0;
static UIView *panel = nil;
static UILabel *resultLabel = nil;
static UIButton *toggleBtn = nil;

// ---- 写日志 ----
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

// ---- 获取窗口 ----
static UIWindow *getAnyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            NSArray *wins = ((UIWindowScene *)scene).windows;
            for (UIWindow *w in wins) {
                if (w.isKeyWindow) return w;
            }
            if (wins.count > 0) return wins.lastObject;
        }
    }
    return nil;
}

// ---- 截图 ----
static UIImage *captureScreen(void) {
    UIWindow *window = getAnyWindow();
    if (!window) return nil;
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// ---- 扫描 ----
static void scanBoard(void) {
    UIImage *image = captureScreen();
    if (!image || !image.CGImage) {
        writeLog(@"截图失败");
        return;
    }
    
    snapshotCounter++;
    NSString *snapName = [NSString stringWithFormat:@"snap_%03ld.png", (long)snapshotCounter];
    NSString *snapPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@", snapName]];
    [UIImagePNGRepresentation(image) writeToFile:snapPath atomically:YES];
    
    CGFloat imgW = image.size.width;
    CGFloat imgH = image.size.height;
    CGFloat scale = image.scale;
    
    CGRect cropRect = CGRectMake(imgW * 0.03, imgH * 0.27, imgW * 0.94, imgH * 0.47);
    CGRect pixelRect = CGRectMake(cropRect.origin.x * scale, cropRect.origin.y * scale,
                                  cropRect.size.width * scale, cropRect.size.height * scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
    if (!cropped) return;
    
    CGFloat newW = cropRect.size.width * 3;
    CGFloat newH = cropRect.size.height * 3;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(newW, newH), NO, 1.0);
    [[UIImage imageWithCGImage:cropped] drawInRect:CGRectMake(0, 0, newW, newH)];
    UIImage *enlarged = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(cropped);
    if (!enlarged.CGImage) return;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:enlarged.CGImage options:@{}];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *req, NSError *error) {
        if (error) return;
        NSSet *pieceSet = [NSSet setWithArray:@[@"帅",@"将",@"仕",@"士",@"相",@"象",@"车",@"馬",@"马",@"炮",@"兵",@"卒"]];
        NSMutableArray *pieces = [NSMutableArray array];
        for (VNRecognizedTextObservation *obs in req.results) {
            VNRecognizedText *top = [[obs topCandidates:1] firstObject];
            if (!top) continue;
            NSString *text = top.string;
            if (text.length != 1) continue;
            if (![pieceSet containsObject:text]) continue;
            CGRect box = obs.boundingBox;
            CGFloat cx = box.origin.x + box.size.width / 2;
            CGFloat cy = box.origin.y + box.size.height / 2;
            [pieces addObject:@{@"text": text, @"x": @(cx), @"y": @(1.0 - cy)}];
        }
        
        NSMutableString *detail = [NSMutableString stringWithFormat:@"%lu 子: ", (unsigned long)pieces.count];
        for (NSDictionary *p in pieces) {
            [detail appendFormat:@"%@(%.2f,%.2f) ", p[@"text"], [p[@"x"] doubleValue], [p[@"y"] doubleValue]];
        }
        writeLog(detail);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            resultLabel.text = detail;
        });
    }];
    request.recognitionLanguages = @[@"zh-Hans"];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    [handler performRequests:@[request] error:nil];
}

// ---- 按钮点击：开始/停止 ----
@interface PanelController : NSObject
- (void)toggleScan:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation PanelController

- (void)toggleScan:(UIButton *)sender {
    if (isScanning) {
        [scanTimer invalidate];
        scanTimer = nil;
        isScanning = NO;
        [sender setTitle:@"▶ 开始扫描" forState:UIControlStateNormal];
    } else {
        isScanning = YES;
        [sender setTitle:@"⏸ 停止扫描" forState:UIControlStateNormal];
        scanTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            scanBoard();
        }];
        scanBoard();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + translation.x,
                                      gesture.view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}

@end

static PanelController *controller = nil;

// ---- 创建悬浮窗 ----
static void createPanel(void) {
    if (panel) return;
    if (!controller) controller = [[PanelController alloc] init];
    
    UIWindow *window = getAnyWindow();
    if (!window) return;
    
    CGFloat w = 300, h = 180;
    CGFloat x = window.bounds.size.width - w - 10;
    CGFloat y = 100;
    
    panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    panel.layer.cornerRadius = 12;
    panel.layer.borderColor = [UIColor whiteColor].CGColor;
    panel.layer.borderWidth = 1;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, w - 20, 22)];
    title.text = @"XiangqiAssist";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    [panel addSubview:title];
    
    toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(10, 36, w - 20, 36);
    [toggleBtn setTitle:@"▶ 开始扫描" forState:UIControlStateNormal];
    [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    toggleBtn.backgroundColor = [UIColor systemBlueColor];
    toggleBtn.layer.cornerRadius = 8;
    [toggleBtn addTarget:controller action:@selector(toggleScan:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:toggleBtn];
    
    resultLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 80, w - 20, h - 90)];
    resultLabel.text = @"等待...";
    resultLabel.textColor = [UIColor whiteColor];
    resultLabel.font = [UIFont systemFontOfSize:10];
    resultLabel.numberOfLines = 0;
    [panel addSubview:resultLabel];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:controller action:@selector(handlePan:)];
    [panel addGestureRecognizer:pan];
    
    [window addSubview:panel];
}

// ---- 入口 ----
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static BOOL created = NO;
    if (created) return;
    created = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createPanel();
    });
}

%end
