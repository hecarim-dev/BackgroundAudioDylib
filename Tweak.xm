#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static void logMsg(NSString *s) {
    @autoreleasepool {
        NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/bg_tweak.log"];
        NSString *t = [NSString stringWithFormat:@"%@: %@\n", [NSDate date], s];
        if (![[NSFileManager defaultManager] fileExistsAtPath:p]) {
            [t writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
            if (h) {
                [h seekToEndOfFile];
                [h writeData:[t dataUsingEncoding:NSUTF8StringEncoding]];
                [h closeFile];
            }
        }
    }
}

@interface BGState : NSObject
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, assign) BOOL recorderActive;
@end
@implementation BGState @end
static BGState *gState = nil;

#pragma mark - Safe helpers

static BOOL safePerformSetMode(AVAudioSession *session, NSString *mode) {
    @autoreleasepool {
        if (![session respondsToSelector:@selector(setMode:error:)]) {
            logMsg(@"setMode: selector missing");
            return NO;
        }
        NSError *err = nil;
        BOOL ok = [session setMode:mode error:&err];
        if (!ok || err) {
            logMsg([NSString stringWithFormat:@"setMode %@ err: %@", mode, err]);
            return NO;
        }
        logMsg([NSString stringWithFormat:@"setMode %@ OK", mode]);
        return YES;
    }
}

static BOOL safeSetCategory(AVAudioSession *session, NSString *category, AVAudioSessionCategoryOptions opts) {
    @autoreleasepool {
        if ([session respondsToSelector:@selector(setCategory:withOptions:error:)]) {
            NSError *err = nil;
            BOOL ok = [session setCategory:category withOptions:opts error:&err];
            if (!ok || err) {
                logMsg([NSString stringWithFormat:@"setCategory %@ opts:%llu err:%@", category, (unsigned long long)opts, err]);
                return NO;
            }
            logMsg(@"setCategory OK");
            return YES;
        } else if ([session respondsToSelector:@selector(setCategory:error:)]) {
            NSError *err = nil;
            BOOL ok = [session setCategory:category error:&err];
            if (!ok || err) {
                logMsg([NSString stringWithFormat:@"setCategory (fallback) %@ err:%@", category, err]);
                return NO;
            }
            logMsg(@"setCategory fallback OK");
            return YES;
        } else {
            logMsg(@"No setCategory selector available");
            return NO;
        }
    }
}

static BOOL safeSetActive(AVAudioSession *session, BOOL active) {
    @autoreleasepool {
        NSError *err = nil;
        BOOL ok = [session setActive:active error:&err];
        if (!ok || err) {
            logMsg([NSString stringWithFormat:@"setActive %@ err:%@", active?@"YES":@"NO", err]);
            return NO;
        }
        logMsg([NSString stringWithFormat:@"setActive %@", active?@"YES":@"NO"]);
        return YES;
    }
}

#pragma mark - Core config + recorder

__attribute__((visibility("hidden")))
static void ensureAudioSessionConfigured(void) {
    @autoreleasepool {
        AVAudioSession *session = [AVAudioSession sharedInstance];

        // 1) mode: VoiceChat if available
        safePerformSetMode(session, AVAudioSessionModeVoiceChat);

        // 2) category: PlayAndRecord with MixWithOthers + AllowBluetooth (no Duck here)
        AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth;
        safeSetCategory(session, AVAudioSessionCategoryPlayAndRecord, opts);

        // 3) activate
        safeSetActive(session, YES);

        // 4) try override to speaker (best-effort)
        if ([session respondsToSelector:@selector(overrideOutputAudioPort:error:)]) {
            NSError *err = nil;
            BOOL ok = [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&err];
            if (ok) logMsg(@"overrideSpeaker OK");
            else if (err) logMsg([NSString stringWithFormat:@"overrideSpeaker err: %@", err]);
        }
    }
}

__attribute__((visibility("hidden")))
static void startRecorderIfNeeded(void) {
    @autoreleasepool {
        if (!gState) gState = [BGState new];
        if (gState.recorderActive) { logMsg(@"recorder already active"); return; }

        // request permission async
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            @autoreleasepool {
                logMsg([NSString stringWithFormat:@"recordPermission granted=%d", granted]);
                if (!granted) return;

                dispatch_async(dispatch_get_main_queue(), ^{
                    AVAudioSession *session = [AVAudioSession sharedInstance];

                    // set category with DuckOthers available for recorder start (so we can duck others while recording)
                    AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionDuckOthers;
                    safeSetCategory(session, AVAudioSessionCategoryPlayAndRecord, opts);
                    safeSetActive(session, YES);

                    // prepare tiny recorder to trigger mic indicator
                    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"bg_rec.caf"];
                    NSURL *fileURL = [NSURL fileURLWithPath:tmp];
                    NSDictionary *settings = @{
                        AVFormatIDKey: @(kAudioFormatAppleIMA4),
                        AVSampleRateKey: @8000,
                        AVNumberOfChannelsKey: @1,
                        AVEncoderBitRateKey: @32000
                    };
                    NSError *recErr = nil;
                    AVAudioRecorder *rec = [[AVAudioRecorder alloc] initWithURL:fileURL settings:settings error:&recErr];
                    if (!rec || recErr) {
                        logMsg([NSString stringWithFormat:@"recorder init err: %@", recErr]);
                        return;
                    }
                    rec.meteringEnabled = NO;
                    BOOL ok = [rec prepareToRecord];
                    if (!ok) logMsg(@"recorder prepareToRecord failed");
                    ok = [rec record];
                    if (ok) {
                        gState.recorder = rec;
                        gState.recorderActive = YES;
                        logMsg(@"recorder started OK (mic indicator expected)");
                    } else {
                        logMsg(@"recorder start failed");
                    }
                });
            }
        }];
    }
}

__attribute__((visibility("hidden")))
static void stopRecorderIfNeeded(void) {
    @autoreleasepool {
        if (!gState || !gState.recorderActive) { logMsg(@"recorder not active"); return; }
        @try {
            [gState.recorder stop];
        } @catch (NSException *ex) {
            logMsg([NSString stringWithFormat:@"rec stop exception: %@", ex]);
        }
        gState.recorder = nil;
        gState.recorderActive = NO;
        logMsg(@"recorder stopped");

        // restore category (no Duck)
        AVAudioSession *session = [AVAudioSession sharedInstance];
        AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth;
        safeSetCategory(session, AVAudioSessionCategoryPlayAndRecord, opts);
        safeSetActive(session, YES);
    }
}

#pragma mark - Notifications (safe)

__attribute__((visibility("hidden")))
static void handleSecondaryAudioHint(NSNotification *note) {
    @autoreleasepool {
        NSDictionary *u = note.userInfo;
        NSNumber *n = u[AVAudioSessionSilenceSecondaryAudioHintTypeKey];
        if (!n) { logMsg(@"secondaryHint: no info"); return; }
        NSInteger t = [n integerValue];
        logMsg([NSString stringWithFormat:@"secondaryHint type=%ld", (long)t]);

        AVAudioSession *s = [AVAudioSession sharedInstance];
        if (t == AVAudioSessionSilenceSecondaryAudioHintTypeBegin) {
            // duck others
            AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionDuckOthers;
            safeSetCategory(s, AVAudioSessionCategoryPlayAndRecord, opts);
            safeSetActive(s, YES);
            logMsg(@"secondary duck set");
        } else {
            // restore
            AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth;
            safeSetCategory(s, AVAudioSessionCategoryPlayAndRecord, opts);
            safeSetActive(s, YES);
            logMsg(@"secondary restore set");
        }
    }
}

__attribute__((visibility("hidden")))
static void handleInterrupt(NSNotification *note) {
    @autoreleasepool {
        NSDictionary *u = note.userInfo;
        NSNumber *type = u[AVAudioSessionInterruptionTypeKey];
        if (!type) { logMsg(@"interruption: no type"); return; }
        NSInteger itype = [type integerValue];
        logMsg([NSString stringWithFormat:@"interruption type=%ld", (long)itype]);

        if (itype == AVAudioSessionInterruptionTypeBegan) {
            stopRecorderIfNeeded();
        } else {
            ensureAudioSessionConfigured();
            startRecorderIfNeeded();
        }
    }
}

#pragma mark - constructor

__attribute__((constructor))
static void init_background_audio() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            logMsg(@"BG tweak starting");
            gState = [BGState new];

            dispatch_async(dispatch_get_main_queue(), ^{
                NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

                [nc addObserverForName:AVAudioSessionSilenceSecondaryAudioHintNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
                    @try { handleSecondaryAudioHint(n); } @catch (NSException *ex) { logMsg([NSString stringWithFormat:@"secondary handler ex: %@", ex]); }
                }];

                [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
                    @try { handleInterrupt(n); } @catch (NSException *ex) { logMsg([NSString stringWithFormat:@"interrupt handler ex: %@", ex]); }
                }];

                // configure & start recorder (permission will prompt once)
                @try {
                    ensureAudioSessionConfigured();
                    startRecorderIfNeeded();
                } @catch (NSException *ex) {
                    logMsg([NSString stringWithFormat:@"init exception: %@", ex]);
                }
                logMsg(@"BG tweak init done");
            });
        }
    });
}
