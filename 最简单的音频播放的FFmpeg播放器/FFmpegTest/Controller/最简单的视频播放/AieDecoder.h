//
//  AieDecoder.h
//  FFmpegTest
//
//  Created by fenglixin on 2017/7/11.
//  Copyright © 2017年 times. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef enum {
   AieFrameTypeAudio,
    AieFrameTypeVideo,
}AieFrameType;


@interface AieFrame : NSObject
@property (nonatomic, assign) AieFrameType type;
@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;
@end

@interface AieAudioFrame : AieFrame
@property (nonatomic, strong) NSData * samples;
@end



@protocol AieDecoderDelegate

- (void)getYUV420Data:(void *)pData width:(int)width height:(int)height;

@end

@interface AieDecoder : NSObject

@property (nonatomic, weak) __weak id<AieDecoderDelegate> delegate;

@property (nonatomic, strong, readonly) NSString * path;
@property (nonatomic, assign) CGFloat fps;


- (BOOL)openFile:(NSString *)path error:(NSError **)perror;
- (NSArray *)decodeFrames:(CGFloat)minDuration;
@end


