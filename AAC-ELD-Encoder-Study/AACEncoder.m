//
//
//  LearnVideoToolBox
//
//  Created by 林偉池 on 16/9/1.
//  Copyright © 2016年 林偉池. All rights reserved.
//
//  AAC-ELD Modified by Splenden Wang on 18/5/22
//

#import "AACEncoder.h"
@import TPCircularBuffer;
@interface AACEncoder()
@property (nonatomic) dispatch_queue_t _Nonnull encoderQueue;
@property (nonatomic) dispatch_queue_t _Nonnull callbackQueue;

@property (nonatomic) AudioConverterRef audioConverter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) UInt32 aacPacketSize;
@property (nonatomic) UInt32 aacPredictBufferSize;

@property (nonatomic) TPCircularBuffer pcmBuffer;

@property (nonatomic) dispatch_source_t timer;
@end
@interface AACEncoder(tool)
+ (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer;
+ (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength;
@end
@implementation AACEncoder
- (void)clean {
    if(_timer) dispatch_cancel(_timer);
    if(_audioConverter) AudioConverterDispose(_audioConverter);
    TPCircularBufferCleanup(&_pcmBuffer);
}
- (void) dealloc {
    [self clean];
}

- (id) init {
    if (self = [super init]) {
        _encoderQueue = dispatch_queue_create("aac-encoder.encode.queue", DISPATCH_QUEUE_SERIAL);
        _callbackQueue = dispatch_queue_create("aac-encoder.callback.queue", DISPATCH_QUEUE_SERIAL);
        _audioConverter = NULL;
        
        TPCircularBufferInit(&_pcmBuffer, 512*4*2); //predict sampleBuffer input 2048Bytes each time. Which means 512 frame, 4bytes per frame and we allow 2 times input as buffer.
        
        //隨便設個預設值
        _aacPacketSize = 1024;
        _aacPredictBufferSize = 2048;
        
        _timer = NULL;
    }
    return self;
}

/**
 *  設置編碼參數
 *
 *  @param sampleBuffer 音頻
 */
- (void) setupEncoderFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0}; // 初始化輸出流的結構體描述為0. 很重要。
    outAudioStreamBasicDescription.mSampleRate = inAudioStreamBasicDescription.mSampleRate; // 音頻流，在正常播放情況下的幀率。如果是壓縮的格式，這個屬性表示解壓縮後的幀率。幀率不能為0。
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC_ELD; // 設置編碼格式
    outAudioStreamBasicDescription.mFormatFlags = 0; // 無損編碼 ，0表示沒有
    outAudioStreamBasicDescription.mBytesPerPacket = 0; // 每一個packet的音頻數據大小。如果的動態大小，設置為0。動態大小的格式，需要用AudioStreamPacketDescription 來確定每個packet的大小。
    outAudioStreamBasicDescription.mFramesPerPacket = 480; // 每個packet的幀數。如果是未壓縮的音頻數據，值是1。動態碼率格式，這個值是一個較大的固定數位，比如說AAC的1024。如果是動態大小幀數（比如Ogg格式）設置為0。
    outAudioStreamBasicDescription.mBytesPerFrame = 0; //  每幀的大小。每一幀的起始點到下一幀的起始點。如果是壓縮格式，設置為0 。
    outAudioStreamBasicDescription.mChannelsPerFrame = 2; // 聲道數
    outAudioStreamBasicDescription.mBitsPerChannel = 0; // 壓縮格式設置為0
    outAudioStreamBasicDescription.mReserved = 0; // 8字節對齊，填0.
    
    //    AudioClassDescription *description = [self
    //                                          getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
    //                                          fromManufacturer:'appl']; //軟編
    
    //    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &_audioConverter); // 創建轉換器
    OSStatus status = AudioConverterNew(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, &_audioConverter);
    if (status != 0) {
        NSLog(@"SETUP CONVERTER: %d", (int)status);
    }
    
    /* Get the maximum output size of output buffer */
    UInt32 maxOutputSizePerPacket = 0;
    UInt32 dataSize = sizeof ( maxOutputSizePerPacket );
    status = AudioConverterGetProperty (_audioConverter,
                                        kAudioConverterPropertyMaximumOutputPacketSize,
                                        &dataSize,
                                        &maxOutputSizePerPacket );
    if (status != 0) {
        NSLog(@"GET PACKETSIZE ERROR: %d", (int)status);
    }
    if(maxOutputSizePerPacket > 0) {
        self.aacPacketSize = maxOutputSizePerPacket;
        self.aacPredictBufferSize = maxOutputSizePerPacket; //should be 1 packet per buffer
    }
    
    /* Get the maximum output size of output buffer, UNAVAIBLE when AAC */
    //    status = AudioConverterGetProperty ( _audioConverter,
    //                                        kAudioConverterPropertyCalculateOutputBufferSize,
    //                                        &dataSize,
    //                                        &_aacPredictBufferSize );
    //    if (status != 0) {
    //        NSLog(@"GET OUTPUT BUFFER SIZE ERROR: %d", (int)status);
    //    }
    //    _aacBuffer = malloc(_aacPredictBufferSize * sizeof(uint8_t));
    
    /* Bitrate */
    UInt32 outputBitRate = 64000;
    UInt32 propSize = sizeof(outputBitRate);
    if (outAudioStreamBasicDescription.mSampleRate >= 44100) {
        outputBitRate = 102000;
    } else if (outAudioStreamBasicDescription.mSampleRate < 22000) {
        outputBitRate = 32000;
    }
    status = AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
    if (status != 0) {
        NSLog(@"SET BITRATE ERROR: %d", (int)status);
    }
    
}

/**
 *  A callback function that supplies audio data to convert. This callback is invoked repeatedly as the converter is ready for new input data.
 */
OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AACEncoder *encoder = (__bridge AACEncoder *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets;
    
    // Pull audio from playthrough buffer
    uint32_t availableBytes;
    void *bufferTail = TPCircularBufferTail(&(encoder->_pcmBuffer), &availableBytes);
    
    UInt32 requestedDataSize = MIN(requestedPackets*4, availableBytes);//1 packet 4 bytes (PCM), cannot be larger than available bytes.
    
    void *buffer = malloc(requestedDataSize);
    memcpy(buffer, bufferTail, requestedDataSize);
    
    ioData->mBuffers[0].mData = buffer;
    ioData->mBuffers[0].mDataByteSize = requestedDataSize;//encoder.audioBufferList.mBuffers[0].mDataByteSize;
    ioData->mBuffers[0].mNumberChannels = 2;
    
    TPCircularBufferConsume(&encoder->_pcmBuffer,requestedDataSize);
    free(buffer);
    
    //AAC ELD dont need out description for each packet. audio spec is fixed. @see: https://wiki.multimedia.cx/index.php/MPEG-4_Audio#Audio_Specific_Config
    if (outDataPacketDescription) {
        *outDataPacketDescription = NULL;
    }
    
    return noErr;
}

/**
 *  Discussion :
 *  預期Mac每次輸出PCM Sample buffer 為2048 bytes -> 依據 pcm規格 16 bits per channel, 2 channel per frame, 1 frame per packet -> 4 bytes per packet -> 輸入為 512 packets
 *  但 AAC Encoder需求為 480 Frames per packet, 以 `pcmBuffer` property儲存, 每次取出 480 frame, 但發現輸出之AAC有clip sound.
 *  又推測 encoder 每秒執行應執行44100(PCM Sample rate)/480(AAC Encoder需求480frame per packet, PCM 1frame per packet) = 99.x 次
 *  於是以Timer polling 方式去處理, 無Clip sound
 */
- (void) runEncodeLoop {
    // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
    // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
    
    //        NSLog(@"COMPRESS!");
    if(self.timer) {
        dispatch_cancel(self.timer);
        self.timer = NULL;
    }
    
    dispatch_queue_t queue = _encoderQueue;
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(self.timer,DISPATCH_TIME_NOW,0.001*NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(self.timer, ^{
        //        NSLog(@"PCM BUFFER LENGTH:%d",_pcmBuffer.length);
        uint32_t buffLength = 0;
        TPCircularBufferTail(&self->_pcmBuffer, &buffLength);
        if(buffLength < 480 * 4) {
            //            usleep(100);
            return;
        }
        NSError *error = nil;
        OSStatus status = noErr;
        AudioBufferList outAudioBufferList = {0};
        self->_aacBuffer = malloc(self->_aacPredictBufferSize * sizeof(uint8_t));
        memset(self->_aacBuffer, 0, self->_aacPredictBufferSize);
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 2;
        outAudioBufferList.mBuffers[0].mDataByteSize = self->_aacPredictBufferSize;
        outAudioBufferList.mBuffers[0].mData = self->_aacBuffer;
        
        AudioStreamPacketDescription *outPacketDescription = NULL;
        UInt32 ioOutputDataPacketSize = self->_aacPredictBufferSize/self->_aacPacketSize; //On input, the size of the output buffer (in the outOutputData parameter), expressed in number packets in the audio converter’s output format.
        
        NSMutableData *rawAAC = [NSMutableData new];
        status = AudioConverterFillComplexBuffer(self->_audioConverter, inInputDataProc, (__bridge void *)(self), &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
        if (status == 0) {
            [rawAAC appendBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
        } else {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        if (self.encodeResultBlock) {
            //            NSLog(@"OUTPUT! AAC SIZE:%d",rawAAC.length);
            dispatch_async(self->_callbackQueue, ^{
                self.encodeResultBlock(rawAAC, error);
            });
        }
        if(self->_aacBuffer) free(self->_aacBuffer);
    });
    dispatch_resume(self.timer);
}

- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self encodeSampleBuffer:sampleBuffer completionBlock:nil];
}

- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer completionBlock:(void (^)(NSData * encodedData, NSError* error))completionBlock {
    if(sampleBuffer == NULL) return;
    CFRetain(sampleBuffer);
    __weak AACEncoder * weakSelf = self;
    dispatch_async(_encoderQueue, ^{
        if (!self->_audioConverter) {
            [weakSelf setupEncoderFromSampleBuffer:sampleBuffer];
            [weakSelf runEncodeLoop];
        }
        OSStatus status = noErr;
        AudioBufferList audioBufferList = {0};
        CMBlockBufferRef blockBuffer;
        size_t bufferListSizeNeededOut = 0;
        
        // put the data pointer into the buffer list
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &bufferListSizeNeededOut, &audioBufferList, sizeof(AudioBufferList), NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
        
        TPCircularBufferProduceBytes(&self->_pcmBuffer,audioBufferList.mBuffers[0].mData,audioBufferList.mBuffers[0].mDataByteSize);
        
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr) {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        
        if(completionBlock) {
            weakSelf.encodeResultBlock = completionBlock;
        }
        
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    });
}


@end
@implementation AACEncoder(tool)
/**
 *  獲取編解碼器
 *
 *  @param type         編碼格式
 *  @param manufacturer 軟/硬編
 *
 編解碼器（codec）指的是一個能夠對一個信號或者一個數據流進行變換的設備或者程序。這裡指的變換既包括將 信號或者數據流進行編碼（通常是為了傳輸、存儲或者加密）或者提取得到一個編碼流的操作，也包括為了觀察或者處理從這個編碼流中恢復適合觀察或操作的形式的操作。編解碼器經常用在視頻會議和流媒體等應用中。
 *  @return 指定編碼器
 */
+ (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}
/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
+ (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //44.1KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}
@end
