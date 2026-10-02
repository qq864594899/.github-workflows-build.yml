#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static UIView *panelView = nil;
static UILabel *resultLabel = nil;
static UIButton *toggleButton = nil;
static NSTimer *scanTimer = nil;
static BOOL isScanning = NO;

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

// ---- 截图 ----
static UIImage *captureScreen(void) {
    UIView *rootView = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    UIGraphicsBeginImageContextWithOptions(rootView.bounds.size, NO, 0);
    [rootView drawViewHierarchyInRect:rootView.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// ---- 识别并更新 UI ----
static void scanBoard(void) {
    UIImage *image = captureScreen();
    if (!image.CGImage) return;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
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
            CGFloat normX = cx;
            CGFloat normY = 1.0 - cy;
            [pieces addObject:@{@"text": text, @"x": @(normX), @"y": @(normY)}];
        }
        
        NSMutableString *detail = [NSMutableString stringWithFormat:@"识别到 %lu 个棋子\n", (unsigned long)pieces.count];
        for (NSDictionary *p in pieces) {
            [detail appendFormat:@"%@(%.2f,%.2f) ", p[@"text"], [p[@"x"] doubleValue], [p[@"y"] doubleValue]];
        }
        
        // 更新悬浮窗文字
        dispatch_async(dispatch_get_main_queue(), ^{
            resultLabel.text = detail;
        });
        
        // 写日志（每次扫描都写）
        writeLog(detail);
    }];
    
    request.recognitionLanguages = @[@"zh-Hans"];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    
    NSError *err = nil;
    [handler performRequests:@[request] error:&err];
}

// ---- 开关按钮 ----
static void toggleScan(void) {
    if (isScanning) {
        [scanTimer invalidate];
        scanTimer = nil;
        isScanning = NO;
        [toggleButton setTitle:@"开始扫描" forState:UIControlStateNormal];
    } else {
        isScanning = YES;
        [toggleButton setTitle:@"停止扫描" forState:UIControlStateNormal];
        scanTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            scanBoard();
        }];
        scanBoard();
    }
}

// ---- 创建悬浮窗 ----
static void createPanel(void) {
    if (panelView) return;
    
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    CGFloat w = 320, h = 220;
    CGFloat x = (window.bounds.size.width - w) / 2;
    CGFloat y = 80;
    
    panelView = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    panelView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    panelView.layer.cornerRadius = 10;
    panelView.userInteractionEnabled = YES;
    
    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, w - 20, 25)];
    title.text = @"XiangqiAssist";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:16];
    [panelView addSubview:title];
    
    // 开关按钮
    toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleButton.frame = CGRectMake(10, 40, 120, 36);
    [toggleButton setTitle:@"开始扫描" forState:UIControlStateNormal];
    [toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    toggleButton.backgroundColor = [UIColor systemBlueColor];
    toggleButton.layer.cornerRadius = 6;
    [toggleButton addTarget:toggleButton action:@selector(toggleScan) forControlEvents:UIControlEventTouchUpInside];
    [toggleButton addTarget:nil action:@selector(toggleScan) forControlEvents:UIControlEventTouchUpInside];
    [panelView addSubview:toggleButton];
    
    // 结果文字
    resultLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 85, w - 20, h - 95)];
    resultLabel.text = @"等待扫描...";
    resultLabel.textColor = [UIColor whiteColor];
    resultLabel.font = [UIFont systemFontOfSize:11];
    resultLabel.numberOfLines = 0;
    [panelView addSubview:resultLabel];
    
    [window addSubview:panelView];
    
    // 拖动手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:panelView action:nil];
    [panelView addGestureRecognizer:pan];
    [pan addTarget:panelView action:@selector(handlePan:)];
}

// ---- 给 UIView 加拖动（用 category 方式避免 hook 冲突）----
@interface UIView (PanelDrag)
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIView (PanelDrag)
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}
@end

// ---- 入口：hook UIViewController 首次显示时创建悬浮窗 ----
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    static BOOL created = NO;
    if (created) return;
    created = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createPanel();
    });
}

%end
