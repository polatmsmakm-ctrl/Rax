// RaXAds: reduces clearly-separate ad/promo units in X (Twitter) 12.8. Written from scratch by
// reading the app's own class layout (igdHook), not copied from any existing tweak.
//
// Honest scope: X mixes some promoted tweets directly into the normal timeline on the server side,
// and that path isn't something a static, from-scratch hook can reliably catch (it would need
// intercepting and re-parsing the server's timeline response, which is a much bigger and more
// fragile project). What IS reliably hookable are the separate ad *units* the app renders as their
// own view classes:
//   - Google native ad cells (the boxed ads that sometimes show in Search/Explore)
//   - the in-stream video ad "skip" control (auto-skips once it can)
//   - the "Promote this post" upsell banner that appears on your own tweets
//   - the "Promoted" label itself (cosmetic — hides the badge; the switch says so)
#import "igd_common.h"
#define BUILD @"a1"

// ---- Google native ad cell (collapse to nothing) ---------------------------------------------
static void collapseIfAdCell(UIView *v) {
    if (!raOn(@"x.ads.google")) return;
    v.hidden = YES;
    if ([v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UICollectionViewCell class]]) {
        v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y, v.frame.size.width, 0);
    }
}
static void hookGoogleAdCell(void) {
    const char *C = "_TtC14T1TwitterSwift18GoogleNativeAdCell";
    igdHook(C, "layoutSubviews", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 0) return nil;
        return ^(UIView *self) { ((void (*)(id, SEL))orig)(self, s); collapseIfAdCell(self); };
    });
}

// ---- in-stream video ad: auto-skip once the skip control is available ------------------------
static void hookAdSkip(void) {
    const char *C = "T1ControlBarAdSkipControl";
    SEL skip = sel_registerName("_t1_didTapSkipAdButton");
    igdHook(C, "player:didUpdatePlaybackState:", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 2) return nil;
        return ^(id self, id player, id state) {
            ((void (*)(id, SEL, id, id))orig)(self, s, player, state);
            if (!raOn(@"x.ads.skip")) return;
            if ([self respondsToSelector:skip]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    ((void (*)(id, SEL))objc_msgSend)(self, skip);
                });
            }
        };
    });
}

// ---- "Promote this post" upsell banner on your own tweets -----------------------------------
static void hookPromotePivot(void) {
    const char *C = "_TtC14T1TwitterSwift21QuickPromotePivotView";
    igdHook(C, "layoutSubviews", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'v' || nargs != 0) return nil;
        return ^(UIView *self) {
            ((void (*)(id, SEL))orig)(self, s);
            if (!raOn(@"x.ads.promote")) return;
            self.hidden = YES;
            self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, self.frame.size.width, 0);
        };
    });
}

// ---- "Promoted" label (cosmetic only — does not remove the tweet itself) ----------------------
static void hookPromotedLabel(void) {
    const char *C = "T1StandardStatusPromotedLabelViewAdapter";
    igdHook(C, "shouldBeVisibleForViewModel:", ^id(IMP orig, SEL s, char ret, unsigned nargs) {
        if (ret != 'B' && ret != 'c') return nil;
        if (nargs != 1) return nil;
        return ^BOOL(id self, id vm) {
            if (!raOn(@"x.ads.label")) return ((BOOL (*)(id, SEL, id))orig)(self, s, vm);
            return NO;
        };
    });
}

__attribute__((constructor)) static void init(void) {
    raRegister(@"الإعلانات", @"x.ads.google", @"إخفاء إعلانات Google المضمّنة", @"في نتائج البحث والاستكشاف فقط");
    raRegister(@"الإعلانات", @"x.ads.skip", @"تخطي إعلانات الفيديو تلقائياً", @"فور ظهور زر Skip على إعلان فيديو داخل البث");
    raRegister(@"الإعلانات", @"x.ads.promote", @"إخفاء بانر «روّج لهذا المنشور»", @"اللي يطلع على تغريداتك الخاصة");
    raRegisterD(@"الإعلانات", @"x.ads.label", @"إخفاء شارة «Promoted»", @"تجميلية فقط — لا تحذف التغريدة المموّلة من القائمة، لأن X يدمجها من السيرفر مباشرة ومافي طريقة موثوقة توقفها من جهة التطبيق", NO);
    igdRun(@"RaXAds", BUILD, ^{
        hookGoogleAdCell();
        hookAdSkip();
        hookPromotePivot();
        hookPromotedLabel();
    });
}
