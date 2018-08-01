//
//  AieAudioManager.h
//  FFmpegTest
//
//  Created by fenglixin on 2018/5/22.
//  Copyright © 2018年 times. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^AieAudioManagerOutputBlock)(float * data, UInt32 numFrames, UInt32 numChannels);

@interface AieAudioManager : NSObject

@property (nonatomic, assign, readonly) Float32 outputVolume;
@property (nonatomic, assign) UInt32 numOutputChannels;
@property (nonatomic, assign) UInt32 numBytesPerSample;
@property (nonatomic, assign) Float64 samplingRate;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, copy) AieAudioManagerOutputBlock outputBlock;

+ (instancetype)audioManager;
- (BOOL)activateAudioSession;
- (BOOL)play;

@end
