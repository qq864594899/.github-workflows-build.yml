#import <UIKit/UIKit.h>

static NSInteger snapCounter = 0;

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

static UIWindow *getAnyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            NSArray *wins = ((UIWindowScene *)scene).windows;
            for (UIWindow *w in wins) if (w.isKeyWindow) return w;
            if (wins.count > 0) return wins.lastObject;
        }
    }
    return nil;
}

static UIImage *captureScreen(void) {
    UIWindow *window = getAnyWindow();
    if (!window) return nil;
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// ============ 切格子：9 列 × 10 行 ============
static void sliceBoard(void) {
    UIImage *image = captureScreen();
    if (!image || !image.CGImage) { writeLog(@"截图失败"); return; }
    
    // 保存原始截图，便于核对
    NSString *rawPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/raw_board.png"];
    [UIImagePNGRepresentation(image) writeToFile:rawPath atomically:YES];
    
    CGFloat scale = image.scale;
    CGFloat imgW = image.size.width * scale;
    CGFloat imgH = image.size.height * scale;
    writeLog([NSString stringWithFormat:@"截图尺寸: %.0f x %.0f", imgW, imgH]);
    
    // 棋盘区域（以第一颗棋子中心 48,48，最后一颗 660,715 为基准）
    // 但注意：这个 48/48 是在 711×758 的坐标系里，需要按实际截图尺寸缩放
    CGFloat baseX = 48.0 * (imgW / 711.0);
    CGFloat baseY = 48.0 * (imgH / 758.0);
    CGFloat stepX = 76.5 * (imgW / 711.0);
    CGFloat stepY = 74.1 * (imgH / 758.0);
    CGFloat cellSize = 80.0 * (imgW / 711.0);  // 每格裁 80 像素
    
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/cells"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    
    for (int r = 0; r < 10; r++) {
        for (int c = 0; c < 9; c++) {
            CGFloat cx = baseX + c * stepX;
            CGFloat cy = baseY + r * stepY;
            
            CGRect cellRect = CGRectMake(cx - cellSize/2, cy - cellSize/2, cellSize, cellSize);
            CGImageRef cellImg = CGImageCreateWithImageInRect(image.CGImage, cellRect);
            if (!cellImg) continue;
            
            // 放大 2 倍保存
            CGFloat nw = cellSize * 2;
            CGFloat nh = cellSize * 2;
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(nw, nh), NO, 1.0);
            [[UIImage imageWithCGImage:cellImg] drawInRect:CGRectMake(0, 0, nw, nh)];
            UIImage *big = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            CGImageRelease(cellImg);
            
            NSString *name = [NSString stringWithFormat:@"r%02d_c%02d.png", r, c];
            NSString *path = [dir stringByAppendingPathComponent:name];
            [UIImagePNGRepresentation(big) writeToFile:path atomically:YES];
        }
    }
    
    snapCounter++;
    writeLog([NSString stringWithFormat:@"切格子完成 #%ld，目录: Documents/cells/", (long)snapCounter]);
}
// ============================================

// ---- 悬浮窗 + 按钮 ----
static UIView *panel = nil;
static UILabel *infoLabel = nil;
static UIButton *sliceBtn = nil;

@interface SliceController : NSObject
- (void)onSlice:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation SliceController
- (void)onSlice:(UIButton *)sender {
    [sender setTitle:@"切格子中..." forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sliceBoard();
        [sender setTitle:@"✅ 切格子完成" forState:UIControlStateNormal];
        infoLabel.text = @"已存到 Documents/cells/";
    });
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint t = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + t.x, gesture.view.center.y + t.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}
@end

static SliceController *sliceCtl = nil;

static void createPanel(void) {
    if (panel) return;
    if (!sliceCtl) sliceCtl = [[SliceController alloc] init];
    
    UIWindow *window = getAnyWindow();
    if (!window) return;
    
    CGFloat w = 280, h = 140;
    CGFloat x = window.bounds.size.width - w - 10;
    CGFloat y = 120;
    
    panel = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    panel.layer.cornerRadius = 12;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, w - 20, 22)];
    title.text = @"XiangqiAssist - 切格子";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:title];
    
    sliceBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    sliceBtn.frame = CGRectMake(10, 36, w - 20, 40);
    [sliceBtn setTitle:@"切格子" forState:UIControlStateNormal];
    [sliceBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    sliceBtn.backgroundColor = [UIColor systemBlueColor];
    sliceBtn.layer.cornerRadius = 8;
    [sliceBtn addTarget:sliceCtl action:@selector(onSlice:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:sliceBtn];
    
    infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 84, w - 20, 40)];
    infoLabel.text = @"先切到 2D 视角再点按钮";
    infoLabel.textColor = [UIColor whiteColor];
    infoLabel.font = [UIFont systemFontOfSize:11];
    infoLabel.numberOfLines = 0;
    [panel addSubview:infoLabel];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:sliceCtl action:@selector(handlePan:)];
    [panel addGestureRecognizer:pan];
    
    [window addSubview:panel];
}

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
