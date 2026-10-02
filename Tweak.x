#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static BOOL started = NO;
static NSTimer *scanTimer = nil;

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

// ---- 获取当前窗口（兼容 iOS 13+ Scene 写法）----
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

// ---- 截图 ----
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

// ---- 扫描棋盘：裁剪 + 放大 + OCR ----
static void scanBoard(void) {
    UIImage *image = captureScreen();
    if (!image || !image.CGImage) {
        writeLog(@"截图失败");
        return;
    }
    
    CGFloat imgW = image.size.width;
    CGFloat imgH = image.size.height;
    CGFloat scale = image.scale;
    
    // 棋盘区域：x=3%, y=27%, 宽=94%, 高=47%
    CGRect cropRect = CGRectMake(imgW * 0.03,
                                 imgH * 0.27,
                                 imgW * 0.94,
                                 imgH * 0.47);
    
    // 换算成像素坐标，裁剪
    CGRect pixelRect = CGRectMake(cropRect.origin.x * scale,
                                  cropRect.origin.y * scale,
                                  cropRect.size.width * scale,
                                  cropRect.size.height * scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixelRect);
    if (!cropped) {
        writeLog(@"裁剪失败");
        return;
    }
    
    // 放大 3 倍
    CGFloat newW = cropRect.size.width * 3;
    CGFloat newH = cropRect.size.height * 3;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(newW, newH), NO, 1.0);
    UIImage *croppedImage = [UIImage imageWithCGImage:cropped];
    [croppedImage drawInRect:CGRectMake(0, 0, newW, newH)];
    UIImage *enlarged = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(cropped);
    
    if (!enlarged.CGImage) {
        writeLog(@"放大失败");
        return;
    }
    
    // OCR
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:enlarged.CGImage options:@{}];
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
    request.usesLanguageCorrection = NO;
    
    NSError *err = nil;
    [handler performRequests:@[request] error:&err];
}

// ---- 入口：进入 App 后 5 秒开始自动扫描，每 2 秒一次 ----
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
