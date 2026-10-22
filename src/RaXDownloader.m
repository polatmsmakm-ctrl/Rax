// RaXDownloader: save the photo or video of any tweet to Photos with a long press, written from
// scratch. X's own media view (T1MediaAttachmentView) already holds what we need once it's on
// screen: the rendered image for photos, and the resolved playable URL for videos (passed to
// -_setPlayerWithMediaURL: right before playback starts) — so this reads what's already loaded
// rather than re-deriving media URLs from any private API.
//
// Honest limits: GIFs/live photos aren't handled (different rendering path), and a video that
// never autoplayed on screen has no captured URL yet — tap it once to start playback, then hold.
#import "igd_common.h"
#import <Photos/Photos.h>
#define BUILD @"dl1"

static const void *kURLKey = &kURLKey;
static const void *kHeldKey = &kHeldKey;

static void saveImage(UIImage *img) {
    if (!img) { igdToast(@"ما لقيت صورة محفوظة — جرّب تضغط وهي ظاهرة كاملة"); return; }
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        [PHAssetCreationRequest creationRequestForAssetFromImage:img];
    } completionHandler:^(BOOL ok, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ igdToast(ok ? @"تم حفظ الصورة بالصور" : @"فشل الحفظ"); });
    }];
}

static void saveVideoURL(NSURL *url) {
    if (!url) { igdToast(@"ما لقيت رابط الفيديو — شغّله مرة ثم اضغط مطوّل"); return; }
    igdToast(@"جاري تحميل الفيديو…");
    NSURLSessionDownloadTask *t = [NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
        if (!tmp) { dispatch_async(dispatch_get_main_queue(), ^{ igdToast(@"فشل تحميل الفيديو"); }); return; }
        NSString *dst = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"rax_%.0f.mp4", NSDate.date.timeIntervalSince1970 * 1000]];
        NSURL *dstURL = [NSURL fileURLWithPath:dst];
        [NSFileManager.defaultManager removeItemAtURL:dstURL error:nil];
        if (![NSFileManager.defaultManager moveItemAtURL:tmp toURL:dstURL error:nil]) {
            dispatch_async(dispatch_get_main_queue(), ^{ igdToast(@"فشل حفظ الملف المؤقت"); });
            return;
        }
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:dstURL];
        } completionHandler:^(BOOL ok, NSError *e2) {
            [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ igdToast(ok ? @"تم حفظ الفيديو بالصور" : @"فشل الحفظ"); });
        }];
    }];
    [t resume];
}

@interface RaXDLHold : NSObject
+ (void)hold:(UILongPressGestureRecognizer *)g;
@end
@implementation RaXDLHold
+ (void)hold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *v = g.view;
    if (objc_getAssociatedObject(v, kHeldKey)) return;       // debounce: one save per long-press
    objc_setAssociatedObject(v, kHeldKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(v, kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
    [[UIImpactFeedbackGenerator new] impactOccurred];
    NSURL *vurl = objc_getAssociatedObject(v, kURLKey);
    if (vurl) { saveVideoURL(vurl); return; }
    SEL imgViewSel = sel_registerName("imageView");
    UIView *imgView = [v respondsToSelector:imgViewSel] ? ((id (*)(id, SEL))objc_msgSend)(v, imgViewSel) : nil;
    UIImage *img = [imgView respondsToSelector:@selector(image)] ? ((UIImage * (*)(id, SEL))objc_msgSend)(imgView, @selector(image)) : nil;
    saveImage(img);
}
@end

static void addHold(UIView *v) {
    if (!raOn(@"x.dl.press")) return;
    for (UIGestureRecognizer *g in v.gestureRecognizers) if ([g.name isEqualToString:@"rax.dl"]) return;
    v.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[RaXDLHold class] action:@selector(hold:)];
    lp.name = @"rax.dl";
    lp.minimumPressDuration = 0.45;
    lp.cancelsTouchesInView = NO;
    [v addGestureRecognizer:lp];
}

static void hookMediaAttachmentView(void) {
    const char *C = "T1MediaAttachmentView";
    igdHook(C, "layoutSubviews", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 0) return nil;
        return ^(UIView *self) { ((void (*)(id, SEL))orig)(self, s); addHold(self); };
    });
    igdHook(C, "_setPlayerWithMediaURL:", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 1) return nil;
        return ^(id self, NSURL *url) {
            ((void (*)(id, SEL, id))orig)(self, s, url);
            objc_setAssociatedObject(self, kURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        };
    });
    // cell/view gets reused for a different tweet — drop any stale captured URL
    igdHook(C, "setAttachment:", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 1) return nil;
        return ^(id self, id att) {
            objc_setAssociatedObject(self, kURLKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((void (*)(id, SEL, id))orig)(self, s, att);
        };
    });
}

__attribute__((constructor)) static void init(void) {
    raRegister(@"التنزيل", @"x.dl.press", @"تحميل الصور والفيديو بالضغط المطوّل",
               @"اضغط مطوّل نص ثانية على أي صورة أو فيديو بالتايملاين لحفظه بالصور. الفيديو يحتاج يشتغل لحظة وحدة قبل أول مرة");
    igdRun(@"RaXDownloader", BUILD, ^{ hookMediaAttachmentView(); });
}
