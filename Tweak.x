#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static BOOL started = NO;
static NSTimer *scanTimer = nil;

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

static UIWindow *getKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return nil;
}

static UIImage *captureScreen(void) {
    UIWindow *window = getKeyWindow();
    if (!window) return nil;
    UIView *rootView = window.rootViewController.view;
    UIGraphicsBeginImageContextWithOptions(rootView.bounds.size, NO, 0);
    [rootView drawViewHierarchyInRect:rootView.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static void scanBoard(void) {
    UIImage *image = captureScreen();
    if (!image || !image.CGImage) {
        writeLog(@"截图失败");
        return;
    }
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *req, NSError *error) {
        if (error) { writeLog(@"OCR 错误"); return; }
        
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
        
        NSMutableString *detail = [NSMutableString stringWithFormat:@"识别到 %lu 个棋子: ", (unsigned long)pieces.count];
        for (NSDictionary *p in pieces) {
            [detail appendFormat:@"%@(%.2f,%.2f) ", p[@"text"], [p[@"x"] doubleValue], [p[@"y"] doubleValue]];
        }
        writeLog(detail);
    }];
    
    request.recognitionLanguages = @[@"zh-Hans"];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    
    NSError *err = nil;
    [handler performRequests:@[request] error:&err];
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    if (started) return;
    started = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        writeLog(@"=== 开始自动扫描 ===");
        scanTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            scanBoard();
        }];
    });
}

%end
