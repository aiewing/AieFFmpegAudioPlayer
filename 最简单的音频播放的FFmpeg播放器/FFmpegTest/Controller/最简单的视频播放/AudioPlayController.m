//
//  AudioPlayController.m
//  FFmpegTest
//
//  Created by fenglixin on 2018/5/21.
//  Copyright © 2018年 times. All rights reserved.
//

#import "AudioPlayController.h"
#import "AieDecoder.h"
#import "AieAudioManager.h"

#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4

@interface AudioPlayController ()
{
    AieDecoder * _decoder;
    dispatch_queue_t _dispatchQueue;

    NSMutableArray * _audioFrames;
    
    NSData * _currentAudioFrame;
    NSUInteger _currentAudioFramePos;
    
    CGFloat _bufferedDuration;
    CGFloat _minBufferedDuration;
    CGFloat _maxBufferedDuration;
    CGFloat _moviePosition;
}

@property (nonatomic, copy) NSString * path;

@end

@implementation AudioPlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    UIButton * aButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [aButton setTitle:@"start" forState:UIControlStateNormal];
    [aButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    aButton.frame = CGRectMake(100, 100, 50, 50);
    [aButton addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:aButton];
    
    AieAudioManager * audioManager = [AieAudioManager audioManager];
    [audioManager activateAudioSession];
    
    [self start];
}

- (void)start
{
    _path = [[NSBundle mainBundle] pathForResource:@"薛之谦 - 摩天大楼" ofType:@"m4a"];
    
    __weak AudioPlayController * weakSelf = self;
    
    AieDecoder * decoder = [[AieDecoder alloc] init];
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError * error = nil;
        [decoder openFile:_path error:&error];
        
        __strong AudioPlayController * strongSelf = weakSelf;
        if (strongSelf)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf setMovieDecoder:decoder];
            });
        }
        
    });
}

- (void)setMovieDecoder:(AieDecoder *)decoder
{
    if (decoder)
    {
        _decoder = decoder;
        _dispatchQueue = dispatch_queue_create("AieMovie", DISPATCH_QUEUE_SERIAL);
        _audioFrames = [NSMutableArray array];
    }
    
    _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
    _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
}

- (void)play
{
    // 解码音频 并把音频存储到_audioFrames
    [self asyncDecodeFrames];
    
    // 打开音频
    [self enableAudio:YES];
}

- (void)enableAudio: (BOOL) on
{
    AieAudioManager * audioManager = [AieAudioManager audioManager];
    
    if (on) {
        
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
    }
}

- (void)asyncDecodeFrames
{
    __weak AudioPlayController * weakSelf = self;
    __weak AieDecoder * weakDecoder = _decoder;
    
    dispatch_async(_dispatchQueue, ^{
        
        // 当已经解码的视频总时间大于_maxBufferedDuration 停止解码
        BOOL good = YES;
        while (good) {
            good = NO;
            
            @autoreleasepool {
                __strong AieDecoder * strongDecoder = weakDecoder;
                
                if (strongDecoder) {
                    NSArray * frames = [strongDecoder decodeFrames:0.1];
                    
                    if (frames.count) {
                        __strong AudioPlayController * strongSelf = weakSelf;
                        
                        if (strongSelf) {
                            good = [strongSelf addFrames:frames];
                        }
                    }
                }
            }
        }
    });
}

- (BOOL) addFrames:(NSArray *)frames
{
    @synchronized (_audioFrames)
    {
        for (AieFrame * frame in frames)
        {
            if (frame.type == AieFrameTypeAudio)
            {
                [_audioFrames addObject:frame];
                
                _bufferedDuration += frame.duration;
            }
        }
    }
    return _bufferedDuration < _maxBufferedDuration;
}

- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    
    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        AieAudioFrame *frame = _audioFrames[0];
                        
                        [_audioFrames removeObjectAtIndex:0];
                        _moviePosition = frame.position;
                        _bufferedDuration -= frame.duration;
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                    
                    if (!count || !(_bufferedDuration > _minBufferedDuration)) {
                        [self asyncDecodeFrames];
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
                break;
            }
        }
    }
}

@end
