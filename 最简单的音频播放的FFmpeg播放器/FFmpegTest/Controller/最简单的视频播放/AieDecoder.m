//
//  AieDecoder.m
//  FFmpegTest
//
//  Created by fenglixin on 2017/7/11.
//  Copyright © 2017年 times. All rights reserved.
//

#import "AieDecoder.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#import "AieAudioManager.h"
#import <Accelerate/Accelerate.h>

@interface AieFrame ()

@end
@implementation AieFrame

@end

@interface AieAudioFrame ()

@end
@implementation AieAudioFrame

@end


static void FFLog(void* context, int level, const char* format, va_list args);
@interface AieDecoder ()
{
    AVFormatContext * _formatCtx;
    AVCodecContext * _videoCodecCtx;


    CGFloat _position;
    
    
    void * _swrBuffer;
    NSUInteger _swrBufferSize;
    
    
    
    NSInteger _audioStream;
    NSArray * _audioStreams;
    AVCodecContext * _audioCodecCtx;
    SwrContext * _swrContext;
    AVFrame * _audioFrame;
    CGFloat _audioTimeBase;
}

@end
@implementation AieDecoder

static void FFLog(void* context, int level, const char* format, va_list args) {
    @autoreleasepool {
        
        
    }
}

+ (void)initialize
{
    av_log_set_callback(FFLog);
    av_register_all();
}

#pragma mark - Public

// 打开文件
- (BOOL)openFile:(NSString *)path error:(NSError **)perror
{
    _path = path;
    
    if (![self openInput:path])
    {
        return NO;
    }
    
    if (![self findAudioStream]) {
        return NO;
    }
    
    return YES;
}

- (NSArray *)decodeFrames:(CGFloat)minDuration
{
    if (_audioStream == -1) {
        return nil;
    }
    
    NSMutableArray * result = [NSMutableArray array];
    AVPacket packet;
    CGFloat decodedDuration = 0;
    BOOL finished = NO;
    
    while (!finished) {
        if (av_read_frame(_formatCtx, &packet) < 0) {
            NSLog(@"读取Frame失败");
            break;
        }
        
        if (packet.stream_index == _audioStream) {
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    break;
                }
                
                if (gotframe) {
                    
                    AieAudioFrame * frame = [self handleAudioFrame];
                    
                    frame.type = AieFrameTypeAudio;
                    if (frame) {

                        [result addObject:frame];

                        _position = frame.position;
                        decodedDuration += frame.duration;
                        NSLog(@"---当前时间：%f, 持续时间: %f , 总时间：%f", _position, frame.duration, decodedDuration);
                        if (decodedDuration > minDuration)
                            finished = YES;
                    }
                }
                
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
        }
        
        av_free_packet(&packet);
    }
    
    return result;
}

#pragma mark - private

- (BOOL)openInput:(NSString *)path
{
    AVFormatContext * formatCtx = NULL;
    
    formatCtx = avformat_alloc_context();
    if (!formatCtx)
    {
        NSLog(@"打开文件失败");
        return NO;
    }
    
    if (avformat_open_input(&formatCtx, [path cStringUsingEncoding:NSUTF8StringEncoding], NULL, NULL) < 0)
    {
        if (formatCtx)
        {
            avformat_free_context(formatCtx);
        }
        NSLog(@"打开文件失败");
        return NO;
    }
    
    if (avformat_find_stream_info(formatCtx, NULL) < 0)
    {
        avformat_close_input(&formatCtx);
        NSLog(@"无法获取流信息");
        return NO;
    }
    
    av_dump_format(formatCtx, 0, [path.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], false);
    
    _formatCtx = formatCtx;
    
    return YES;
}


// 打开音频流
- (BOOL)findAudioStream {
    _audioStream = -1;
    for (NSInteger i = 0; i < _formatCtx->nb_streams; i++) {
        if (AVMEDIA_TYPE_AUDIO == _formatCtx->streams[i]->codec->codec_type) {
            if ([self openAudioStream: i])
                break;
        }
    }
    return true;
}


- (BOOL) openAudioStream: (NSInteger) audioStream
{
    AVCodecContext *codecCtx = _formatCtx->streams[audioStream]->codec;
    SwrContext *swrContext = NULL;
    
    AVCodec *codec = avcodec_find_decoder(codecCtx->codec_id);
    if(!codec)
        return false;
    
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        return false;
    
    if (!audioCodecIsSupported(codecCtx)) {
        
        AieAudioManager * audioManager = [AieAudioManager audioManager];
        swrContext = swr_alloc_set_opts(NULL,
                                        av_get_default_channel_layout(audioManager.numOutputChannels),
                                        AV_SAMPLE_FMT_S16,
                                        audioManager.samplingRate,
                                        av_get_default_channel_layout(codecCtx->channels),
                                        codecCtx->sample_fmt,
                                        codecCtx->sample_rate,
                                        0,
                                        NULL);
        
        if (!swrContext ||
            swr_init(swrContext)) {
            
            if (swrContext)
                swr_free(&swrContext);
            avcodec_close(codecCtx);
            
            return false;
        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContext)
            swr_free(&swrContext);
        avcodec_close(codecCtx);
        return false;
    }
    
    _audioStream = audioStream;
    _audioCodecCtx = codecCtx;
    _swrContext = swrContext;
    
    AVStream *st = _formatCtx->streams[_audioStream];
    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    
    NSLog(@"audio codec smr: %.d fmt: %d chn: %d tb: %f %@",
                _audioCodecCtx->sample_rate,
                _audioCodecCtx->sample_fmt,
                _audioCodecCtx->channels,
                _audioTimeBase,
                _swrContext ? @"resample" : @"");
    
    return true;
}

- (AieAudioFrame *) handleAudioFrame
{
    if (!_audioFrame->data[0])
        return nil;

    AieAudioManager * audioManager = [AieAudioManager audioManager];

    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSInteger numFrames;

    void * audioData;

    if (_swrContext) {
        const NSUInteger ratio = MAX(1, audioManager.samplingRate / _audioCodecCtx->sample_rate) *
        MAX(1, audioManager.numOutputChannels / _audioCodecCtx->channels) * 2;

        const int bufSize = av_samples_get_buffer_size(NULL,
                                                       audioManager.numOutputChannels,
                                                       _audioFrame->nb_samples * ratio,
                                                       AV_SAMPLE_FMT_S16,
                                                       1);

        if (!_swrBuffer || _swrBufferSize < bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }

        Byte *outbuf[2] = { _swrBuffer, 0 };

        numFrames = swr_convert(_swrContext,
                                outbuf,
                                _audioFrame->nb_samples * ratio,
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        if (numFrames < 0) {
            return nil;
        }
        audioData = _swrBuffer;
    } else {
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSAssert(false, @"bucheck, audio format is invalid");
            return nil;
        }
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }

    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];

    float scale = 1.0 / (float)INT16_MAX ;
    vDSP_vflt16((SInt16 *)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);

    AieAudioFrame *frame = [[AieAudioFrame alloc] init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.samples = data;

    return frame;
}

static BOOL audioCodecIsSupported(AVCodecContext *audio)
{
    if (audio->sample_fmt == AV_SAMPLE_FMT_S16) {
        
        AieAudioManager * audioManager = [AieAudioManager audioManager];
        return  (int)audioManager.samplingRate == audio->sample_rate &&
        audioManager.numOutputChannels == audio->channels;
    }
    return NO;
}

static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase)
{
    CGFloat fps, timebase;
    
    // ffmpeg提供了一个把AVRatioal结构转换成double的函数
    // 默认0.04 意思就是25帧
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    else
        timebase = defaultTimeBase;
    
    if (st->codec->ticks_per_frame != 1)
    {
        
    }
    
    // 平均帧率
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}


static NSArray * collectStreams(AVFormatContext * formatCtx, enum AVMediaType codecType)
{
    NSMutableArray * ma = [NSMutableArray array];
    for (NSInteger i = 0; i < formatCtx->nb_streams; i++)
    {
        if (codecType == formatCtx->streams[i]->codec->codec_type)
        {
            [ma addObject:[NSNumber numberWithInteger:i]];
        }
    }
    return [ma copy];
}



@end
