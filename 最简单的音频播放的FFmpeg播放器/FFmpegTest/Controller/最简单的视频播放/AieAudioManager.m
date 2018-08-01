//
//  AieAudioManager.m
//  FFmpegTest
//
//  Created by fenglixin on 2018/5/22.
//  Copyright © 2018年 times. All rights reserved.
//

#import "AieAudioManager.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>

#define MAX_FRAME_SIZE 4096
#define MAX_CHAN       2

@interface AieAudioManager () {
    BOOL _activated;
    float * _outData;
    AudioUnit _audioUnit;
    AudioStreamBasicDescription _outputFormat;
}

@end

@implementation AieAudioManager

static id _instance;

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[super allocWithZone:zone] init];
    });
    return _instance;
}

+ (instancetype)audioManager
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _outData = (float *)calloc(MAX_FRAME_SIZE * MAX_CHAN, sizeof(float));
        _outputVolume = 0.5;
    }
    return self;
}

- (void)dealloc
{
    if (_outData) {
        free(_outData);
        _outData = NULL;
    }
}

#pragma mark - Public
- (BOOL)activateAudioSession
{
    if (!_activated) {
        if ([self setupAudio]) {
            _activated = true;
        }
    }
    return _activated;
}

- (BOOL)play
{
    if (!_playing) {
        if (_activated) {
            // 启动音频输出单元
            OSStatus status = AudioOutputUnitStart(_audioUnit);
            if (status == noErr) {
                _playing = true;
            } else {
                _playing = false;
            }
        }
    }
    return _playing;
}

#pragma mark - Private
- (BOOL)setupAudio
{
    UInt32 size;;
    OSStatus status;
    
    //
    AudioComponentDescription description = {0};
    description.componentType = kAudioUnitType_Output;
    description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    description.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // 创建音频输出单元
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    status = AudioComponentInstanceNew(component, &_audioUnit);
    if (status != noErr) {
        NSLog(@"无法创建音频输出单元");
        return false;
    }
    
    // 获取硬件的输出信息
    size = sizeof(AudioStreamBasicDescription);
    status = AudioUnitGetProperty(_audioUnit,
                                           kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Input,
                                           0,
                                           &_outputFormat,
                                           &size);
    if (status != noErr) {
        NSLog(@"无法获取硬件的输出流格式");
        return false;
    }
    
    _numBytesPerSample = _outputFormat.mBitsPerChannel / 8;
    _numOutputChannels = _outputFormat.mChannelsPerFrame;
    
    // 设置回调
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    if (status != noErr) {
        NSLog(@"无法设置音频输出单元的回调");
        return false;
    }
    
    // 初始化音频输出单元
    status = AudioUnitInitialize(_audioUnit);
    if (status != noErr) {
        NSLog(@"无法初始化音频输出单元");
        return false;
    }
    
    return true;
}

- (BOOL)renderFrames:(UInt32)numFrames ioData:(AudioBufferList *)ioData
{
    for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; iBuffer++) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    
    if (_playing && _outputBlock) {
        _outputBlock(_outData, numFrames, _numOutputChannels);
        
        if (_numBytesPerSample == 2) {
            float scale = (float)INT16_MAX;
            vDSP_vsmul(_outData,
                       1,
                       &scale,
                       _outData,
                       1,
                       numFrames * _numOutputChannels);
            for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                for (int iChannel = 0; iChannel < thisNumChannels; ++iChannel) {
                    vDSP_vfix16(_outData+iChannel,
                                _numOutputChannels,
                                (SInt16 *)ioData->mBuffers[iBuffer].mData+iChannel,
                                thisNumChannels, numFrames);
                }
            }
        }
    }
    
    return noErr;
}

#pragma mark - CallBack
static OSStatus renderCallback (void                        *inRefCon,
                                AudioUnitRenderActionFlags    * ioActionFlags,
                                const AudioTimeStamp         * inTimeStamp,
                                UInt32                        inOutputBusNumber,
                                UInt32                        inNumberFrames,
                                AudioBufferList                * ioData)
{
    AieAudioManager * aam = (__bridge AieAudioManager *)inRefCon;
    return [aam renderFrames:inNumberFrames ioData:ioData];
}

@end
