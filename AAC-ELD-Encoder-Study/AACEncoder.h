//
//
//  
//  LearnVideoToolBox
//
//  Created by 林伟池 on 16/9/1.
//  Copyright © 2016年 林伟池. All rights reserved.
//
//  AAC-ELD Modified by Splenden Wang on 18/5/22
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AACEncoder : NSObject

@property (NS_NONATOMIC_IOSONLY, copy, nonnull) void (^encodeResultBlock)(NSData * _Nullable aacData, NSError * _Nullable error);

- (void) encodeSampleBuffer:(CMSampleBufferRef _Nullable)sampleBuffer;
- (void) encodeSampleBuffer:(CMSampleBufferRef _Nullable)sampleBuffer completionBlock:(void (^_Nullable)(NSData * _Nullable encodedData, NSError* _Nullable error))completionBlock;
- (void) clean;
@end
