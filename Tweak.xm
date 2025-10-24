#import <AVFoundation/AVFoundation.h>

%hook AVAudioSession

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (active) {
        @try {
            AVAudioSession *session = [AVAudioSession sharedInstance];
            [session setCategory:AVAudioSessionCategoryPlayAndRecord
                     withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                 AVAudioSessionCategoryOptionAllowBluetooth |
                                 AVAudioSessionCategoryOptionDefaultToSpeaker
                           error:nil];
            [session setMode:AVAudioSessionModeVoiceChat error:nil];
            [session setActive:YES error:nil];
            NSLog(@"[BackgroundAudio] ✅ Audio session active with mix and mic");
        } @catch (NSException *ex) {
            NSLog(@"[BackgroundAudio] ❌ Exception: %@", ex);
        }
    }
    return %orig(active, outError);
}

%end
