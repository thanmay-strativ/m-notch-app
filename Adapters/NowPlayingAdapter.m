// Streams what macOS is playing (the Control Center "Now Playing" source: Music, Spotify, YouTube in a browser, ...)
// as one JSON line per change, and takes "toggle", "next", "previous" and "seek <seconds>" on stdin.
//
// Since macOS 15.4, MediaRemote only answers Apple's own processes, so m_notch loads this library into the system
// /usr/bin/perl (see NowPlayingWatcher.swift). When stdin closes, m_notch quit or turned the feature off, and it exits.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetIsPlayingFunction)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFunction)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientBundleIdentifierFunction)(id);
typedef void (*RegisterFunction)(dispatch_queue_t);
typedef Boolean (*SendCommandFunction)(int, NSDictionary *);
typedef void (*SetElapsedTimeFunction)(double);

enum { CommandTogglePlayPause = 2, CommandNextTrack = 4, CommandPreviousTrack = 5 };

static GetInfoFunction getInfo;
static GetIsPlayingFunction getIsPlaying;
static GetClientFunction getClient;
static ClientBundleIdentifierFunction clientBundleIdentifier;
static SendCommandFunction sendCommand;
static SetElapsedTimeFunction setElapsedTime;
static dispatch_queue_t emitQueue;
static NSData *lastArtwork;
static BOOL emitScheduled;

static id stringOrEmpty(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }

static id numberOrNull(id value) { return [value isKindOfClass:[NSNumber class]] ? value : [NSNull null]; }

static void writeLine(NSDictionary *line) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:line options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emit(void) {
    getInfo(emitQueue, ^(NSDictionary *info) {
        getIsPlaying(emitQueue, ^(Boolean isPlaying) {
            getClient(emitQueue, ^(id client) {
                NSMutableDictionary *line = [NSMutableDictionary dictionary];
                line[@"title"] = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
                line[@"artist"] = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                line[@"album"] = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                line[@"duration"] = numberOrNull(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                line[@"elapsed"] = numberOrNull(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                line[@"elapsedAt"] = @(([timestamp isKindOfClass:[NSDate class]] ? timestamp : [NSDate date]).timeIntervalSince1970);
                line[@"rate"] = numberOrNull(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                line[@"playing"] = @(isPlaying);
                line[@"app"] = client ? stringOrEmpty((__bridge NSString *)clientBundleIdentifier(client)) : @"";
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if (![artwork isKindOfClass:[NSData class]]) artwork = nil;
                if (!(artwork == lastArtwork || [artwork isEqualToData:lastArtwork])) {
                    line[@"artwork"] = artwork ? [artwork base64EncodedStringWithOptions:0] : @"";
                    lastArtwork = artwork;
                }
                writeLine(line);
            });
        });
    });
}

/// Notifications come in bursts (track, then artwork, then rate): one line 150 ms after the first is enough.
static void scheduleEmit(void) {
    dispatch_async(emitQueue, ^{
        if (emitScheduled) return;
        emitScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), emitQueue, ^{
            emitScheduled = NO;
            emit();
        });
    });
}

static void observe(void *handle, const char *symbolName) {
    CFStringRef *exported = (CFStringRef *)dlsym(handle, symbolName);
    NSString *name = exported ? (__bridge NSString *)*exported : [NSString stringWithUTF8String:symbolName];
    [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                  usingBlock:^(NSNotification *notification) { scheduleEmit(); }];
}

static void readCommands(void) {
    [NSThread detachNewThreadWithBlock:^{
        char buffer[64];
        while (fgets(buffer, sizeof buffer, stdin)) {
            NSString *command = [[NSString stringWithUTF8String:buffer]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([command isEqualToString:@"toggle"]) sendCommand(CommandTogglePlayPause, nil);
            else if ([command isEqualToString:@"next"]) sendCommand(CommandNextTrack, nil);
            else if ([command isEqualToString:@"previous"]) sendCommand(CommandPreviousTrack, nil);
            else if ([command isEqualToString:@"refresh"]) scheduleEmit();
            else if ([command hasPrefix:@"seek "] && setElapsedTime) {
                setElapsedTime(MAX(0, [[command substringFromIndex:5] doubleValue]));
                scheduleEmit();
            }
            else fprintf(stderr, "Unknown now playing command \"%s\"\n", command.UTF8String);
        }
        exit(0);
    }];
}

void m_notch_now_playing_stream(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "Could not open MediaRemote: %s\n", dlerror());
        exit(2);
    }
    getInfo = (GetInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (GetIsPlayingFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = (GetClientFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingClient");
    clientBundleIdentifier = (ClientBundleIdentifierFunction)dlsym(handle, "MRNowPlayingClientGetBundleIdentifier");
    sendCommand = (SendCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand");
    setElapsedTime = (SetElapsedTimeFunction)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    RegisterFunction registerForNotifications = (RegisterFunction)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !getClient || !clientBundleIdentifier || !sendCommand || !registerForNotifications) {
        fprintf(stderr, "MediaRemote is missing a function: info=%d playing=%d client=%d bundle=%d command=%d register=%d\n",
                getInfo != NULL, getIsPlaying != NULL, getClient != NULL, clientBundleIdentifier != NULL,
                sendCommand != NULL, registerForNotifications != NULL);
        exit(3);
    }
    emitQueue = dispatch_queue_create("local.mnotch.now-playing", DISPATCH_QUEUE_SERIAL);
    registerForNotifications(emitQueue);
    observe(handle, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    observe(handle, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    observe(handle, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
    readCommands();
    scheduleEmit();
    CFRunLoopRun();
}
