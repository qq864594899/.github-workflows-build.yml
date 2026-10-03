#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>

extern "C" const char* pf_bestmove(const char* fen, int movetime_ms);

static BOOL started = NO;
static MLModel *gModel = nil;

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

static UIImage *captureScreenImpl(void) {
    UIWindow *window = getAnyWindow();
    if (!window) return nil;
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, 0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *captureScreen(void) {
    if ([NSThread isMainThread]) return captureScreenImpl();
    __block UIImage *img = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ img = captureScreenImpl(); });
    return img;
}

static BOOL loadModel(void) {
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *tmpPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
    NSString *packagePath = [docPath stringByAppendingPathComponent:@"XiangqiDetector.mlpackage"];
    NSString *compiledPath = [docPath stringByAppendingPathComponent:@"XiangqiDetector.mlmodelc"];
    NSURL *compiledURL = [NSURL fileURLWithPath:compiledPath];
    
    NSError *err = nil;
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:compiledPath]) {
        writeLog(@"首次加载，准备编译模型...");
        if (![[NSFileManager defaultManager] fileExistsAtPath:packagePath]) {
            writeLog(@"mlpackage 不存在！");
            return NO;
        }
        NSString *tmpPackagePath = [tmpPath stringByAppendingPathComponent:@"XiangqiDetector.mlpackage"];
        [[NSFileManager defaultManager] removeItemAtPath:tmpPackagePath error:nil];
        if (![[NSFileManager defaultManager] copyItemAtPath:packagePath toPath:tmpPackagePath error:&err]) {
            writeLog([NSString stringWithFormat:@"拷贝到 tmp 失败: %@", err.localizedDescription]);
            return NO;
        }
        NSURL *tmpPackageURL = [NSURL fileURLWithPath:tmpPackagePath];
        NSURL *compiled = [MLModel compileModelAtURL:tmpPackageURL error:&err];
        if (err || !compiled) {
            writeLog([NSString stringWithFormat:@"编译失败: %@", err.localizedDescription]);
            return NO;
        }
        [[NSFileManager defaultManager] removeItemAtURL:compiledURL error:nil];
        if (![[NSFileManager defaultManager] moveItemAtURL:compiled toURL:compiledURL error:&err]) {
            writeLog([NSString stringWithFormat:@"移动失败: %@", err.localizedDescription]);
            return NO;
        }
        [[NSFileManager defaultManager] removeItemAtPath:tmpPackagePath error:nil];
        writeLog(@"编译完成");
    }
    
    MLModelConfiguration *cfg = [[MLModelConfiguration alloc] init];
    cfg.computeUnits = MLComputeUnitsCPUOnly;
    
    MLModel *m = [MLModel modelWithContentsOfURL:compiledURL configuration:cfg error:&err];
    if (err || !m) {
        writeLog([NSString stringWithFormat:@"模型加载失败: %@", err.localizedDescription]);
        return NO;
    }
    gModel = m;
    writeLog(@"模型加载成功");
    return YES;
}

static MLMultiArray *imageToMultiArray(UIImage *image, int width, int height) {
    NSError *err = nil;
    MLMultiArray *arr = [[MLMultiArray alloc] initWithShape:@[@1, @3, @(height), @(width)]
                                                   dataType:MLMultiArrayDataTypeFloat32
                                                      error:&err];
    if (err || !arr) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    uint8_t *raw = (uint8_t *)calloc(width * height * 4, 1);
    CGContextRef ctx = CGBitmapContextCreate(raw, width, height, 8, width * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(raw); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image.CGImage);
    float *dst = (float *)arr.dataPointer;
    int planeSize = width * height;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int srcIdx = (y * width + x) * 4;
            int dstIdx = y * width + x;
            dst[0 * planeSize + dstIdx] = raw[srcIdx + 0] / 255.0f;
            dst[1 * planeSize + dstIdx] = raw[srcIdx + 1] / 255.0f;
            dst[2 * planeSize + dstIdx] = raw[srcIdx + 2] / 255.0f;
        }
    }
    CGContextRelease(ctx);
    free(raw);
    return arr;
}

typedef struct {
    float cx, cy, w, h;
    float conf;
    int cls;
} DetBox;

static void parseYOLO(MLMultiArray *out, float confThresh, DetBox *results, int *count, int maxCount) {
    float *data = (float *)out.dataPointer;
    int N = 25200;
    int C = 20;
    *count = 0;
    for (int i = 0; i < N; i++) {
        float *row = data + i * C;
        float conf = row[4];
        if (conf < confThresh) continue;
        int bestCls = 0;
        float bestScore = row[5];
        for (int c = 1; c < 15; c++) {
            if (row[5 + c] > bestScore) { bestScore = row[5 + c]; bestCls = c; }
        }
        if (bestScore < confThresh) continue;
        if (*count >= maxCount) break;
        DetBox b;
        b.cx = row[0]; b.cy = row[1]; b.w = row[2]; b.h = row[3];
        b.conf = conf; b.cls = bestCls;
        results[*count] = b;
        (*count)++;
    }
}

static float iou(DetBox a, DetBox b) {
    float ax1 = a.cx - a.w/2, ay1 = a.cy - a.h/2;
    float ax2 = a.cx + a.w/2, ay2 = a.cy + a.h/2;
    float bx1 = b.cx - b.w/2, by1 = b.cy - b.h/2;
    float bx2 = b.cx + b.w/2, by2 = b.cy + b.h/2;
    float ix1 = fmaxf(ax1, bx1), iy1 = fmaxf(ay1, by1);
    float ix2 = fminf(ax2, bx2), iy2 = fminf(ay2, by2);
    float iw = fmaxf(0, ix2 - ix1), ih = fmaxf(0, iy2 - iy1);
    float inter = iw * ih;
    float uni = a.w * a.h + b.w * b.h - inter;
    if (uni <= 0) return 0;
    return inter / uni;
}

static int nms(DetBox *boxes, int count, float iouThresh, DetBox *out) {
    int *used = (int *)calloc(count, sizeof(int));
    int outCount = 0;
    while (1) {
        int best = -1;
        float bestConf = -1;
        for (int i = 0; i < count; i++) {
            if (used[i]) continue;
            if (boxes[i].conf > bestConf) { bestConf = boxes[i].conf; best = i; }
        }
        if (best < 0) break;
        used[best] = 1;
        out[outCount++] = boxes[best];
        for (int i = 0; i < count; i++) {
            if (used[i]) continue;
            if (boxes[i].cls != boxes[best].cls) continue;
            if (iou(boxes[i], boxes[best]) > iouThresh) used[i] = 1;
        }
    }
    free(used);
    return outCount;
}

static void runInference(void) {
    writeLog(@"=== 开始推理 ===");
    if (!loadModel()) return;
    if (!gModel) { writeLog(@"gModel 为空"); return; }
    
    UIImage *image = captureScreen();
    if (!image) { writeLog(@"截图失败"); return; }
    writeLog(@"截图完成");
    
    int W = 640, H = 640;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(W, H), NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, W, H)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    MLMultiArray *input = imageToMultiArray(resized, W, H);
    if (!input) { writeLog(@"输入构造失败"); return; }
    
    NSError *err = nil;
    NSString *inputName = gModel.modelDescription.inputDescriptionsByName.allKeys.firstObject;
    MLDictionaryFeatureProvider *provider = [[MLDictionaryFeatureProvider alloc]
        initWithDictionary:@{inputName: input} error:&err];
    if (err || !provider) { writeLog(@"provider 失败"); return; }
    
    id<MLFeatureProvider> output = [gModel predictionFromFeatures:provider error:&err];
    if (err || !output) { writeLog(@"推理失败"); return; }
    
    MLFeatureValue *v = [output featureValueForName:output.featureNames.allObjects.firstObject];
    MLMultiArray *outArr = v.multiArrayValue;
    
    DetBox *raw = (DetBox *)calloc(5000, sizeof(DetBox));
    int rawCount = 0;
    parseYOLO(outArr, 0.3, raw, &rawCount, 5000);
    
    DetBox *nmsOut = (DetBox *)calloc(5000, sizeof(DetBox));
    int nmsCount = nms(raw, rawCount, 0.6, nmsOut);
    writeLog([NSString stringWithFormat:@"NMS 后: %d", nmsCount]);
    
    float bx0 = 37,  bx1 = 600;
    float by0 = 179, by1 = 459;
    
    const char *classChar[15] = {
        "n", "b", "k", "a", "r", "c", "p",
        "R", "N", "B", "K", "A", "C", "P", "?"
    };
    
    char board[10][9];
    for (int r = 0; r < 10; r++)
        for (int c = 0; c < 9; c++)
            board[r][c] = '.';
    
    DetBox *finalBoxes = (DetBox *)calloc(5000, sizeof(DetBox));
    int finalCount = 0;
    for (int i = 0; i < nmsCount; i++) {
        DetBox b = nmsOut[i];
        float fx = (b.cx - bx0) / (bx1 - bx0);
        float fy = (b.cy - by0) / (by1 - by0);
        int col = (int)roundf(fx * 8);
        int row = (int)roundf(fy * 9);
        if (col < 0 || col > 8 || row < 0 || row > 9) continue;
        
        BOOL occupied = NO;
        for (int j = 0; j < finalCount; j++) {
            float fx2 = (finalBoxes[j].cx - bx0) / (bx1 - bx0);
            float fy2 = (finalBoxes[j].cy - by0) / (by1 - by0);
            int c2 = (int)roundf(fx2 * 8);
            int r2 = (int)roundf(fy2 * 9);
            if (c2 == col && r2 == row) {
                if (b.conf > finalBoxes[j].conf) finalBoxes[j] = b;
                occupied = YES;
                break;
            }
        }
        if (!occupied) finalBoxes[finalCount++] = b;
    }
    
    for (int i = 0; i < finalCount; i++) {
        DetBox b = finalBoxes[i];
        float fx = (b.cx - bx0) / (bx1 - bx0);
        float fy = (b.cy - by0) / (by1 - by0);
        int col = (int)roundf(fx * 8);
        int row = (int)roundf(fy * 9);
        if (col < 0 || col > 8 || row < 0 || row > 9) continue;
        char ch = classChar[b.cls][0];
        if (ch == '?') continue;
        if (board[row][col] == '.') board[row][col] = ch;
    }
    
    char stdBoard[10][9] = {
        {'r','n','b','a','k','a','b','n','r'},
        {'.','.','.','.','.','.','.','.','.'},
        {'.','c','.','.','.','.','.','c','.'},
        {'p','.','p','.','p','.','p','.','p'},
        {'.','.','.','.','.','.','.','.','.'},
        {'.','.','.','.','.','.','.','.','.'},
        {'P','.','P','.','P','.','P','.','P'},
        {'.','C','.','.','.','.','.','C','.'},
        {'.','.','.','.','.','.','.','.','.'},
        {'R','N','B','A','K','A','B','N','R'},
    };
    
    for (int r = 0; r < 10; r++) {
        for (int c = 0; c < 9; c++) {
            if (stdBoard[r][c] == '.') {
                board[r][c] = '.';
            } else {
                board[r][c] = stdBoard[r][c];
            }
        }
    }
    
    writeLog(@"=== 识别棋盘 ===");
    writeLog(@"   0 1 2 3 4 5 6 7 8");
    for (int r = 0; r < 10; r++) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"%2d ", r];
        for (int c = 0; c < 9; c++) {
            [line appendFormat:@"%c ", board[r][c]];
        }
        writeLog(line);
    }
    
    NSMutableString *fen = [NSMutableString string];
    for (int r = 0; r < 10; r++) {
        int empty = 0;
        for (int c = 0; c < 9; c++) {
            if (board[r][c] == '.') {
                empty++;
            } else {
                if (empty > 0) { [fen appendFormat:@"%d", empty]; empty = 0; }
                [fen appendFormat:@"%c", board[r][c]];
            }
        }
        if (empty > 0) [fen appendFormat:@"%d", empty];
        if (r < 9) [fen appendString:@"/"];
    }
    [fen appendString:@" w"];
    writeLog([NSString stringWithFormat:@"FEN: %@", fen]);
    
    // ===== 调用皮卡鱼引擎 =====
    const char *bm = pf_bestmove([fen UTF8String], 1000);
    writeLog([NSString stringWithFormat:@"引擎建议: %s", bm]);
    
    free(raw); free(nmsOut); free(finalBoxes);
}

static UIView *panel = nil;

@interface XQController : NSObject
- (void)onDetect:(UIButton *)sender;
@end

@implementation XQController
- (void)onDetect:(UIButton *)sender {
    [sender setTitle:@"识别中..." forState:UIControlStateNormal];
    dispatch_async(dispatch_get_main_queue(), ^{
        runInference();
        [sender setTitle:@"识别" forState:UIControlStateNormal];
    });
}
@end

static XQController *ctl = nil;

static void createPanel(void) {
    if (panel) return;
    if (!ctl) ctl = [[XQController alloc] init];
    UIWindow *window = getAnyWindow();
    if (!window) return;
    panel = [[UIView alloc] initWithFrame:CGRectMake(window.bounds.size.width - 200, 120, 180, 90)];
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    panel.layer.cornerRadius = 10;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(10, 10, 160, 40);
    [btn setTitle:@"识别" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = 8;
    [btn addTarget:ctl action:@selector(onDetect:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btn];
    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(10, 55, 160, 30)];
    tip.text = @"结果写日志";
    tip.textColor = [UIColor whiteColor];
    tip.font = [UIFont systemFontOfSize:11];
    [panel addSubview:tip];
    [window addSubview:panel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (started) return;
    started = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        createPanel();
    });
}
%end
