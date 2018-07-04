# AAC-ELD-Encoder-Study
在Mac/iOS上將PCM內容的CMSampleBuffer輸出成AAC-ELD格式
#### 目的
將iDevice上的音訊送出去到其他接收端；為了low latency，採用AAC-ELD格式。

# 流程
- iDevice收到音訊
- AVCaptureSesseion輸出CMSampleBuffer
- AACEncoder根據buffer format description設置encoder
- AACEncoder encode buffer
  - 將Sample buffer搬入PCMBuffer property
  - 觸發 AudioFillComplexBuffer
- 輸出.完成
(註：此處僅提供AAC Encoder部分)

# 詳細流程

規格前提：

	PCM: 44100 sample rate, 2 channel per frame, 16 bit per channel, 1 frame per packet, 4Bytes - fixed packetSize
	AAC: 44100 sample rate, 2 channel per frame, variable bitrate, 480frames per packet, variable packetSize(with a maximum value)

有需要可以用Apple的Sample code直接去看Format description，Console output應該會如下

	Source File format:
	Sample Rate:              44100
	Format ID:                 lpcm
	Format Flags:                 C
	Bytes per Packet:             4
	Frames per Packet:            1
	Bytes per Frame:              4
	Channels per Frame:           2
	Bits per Channel:            16

	Destination File format:
	Sample Rate:              44100
	Format ID:                 aace
	Format Flags:                 0
	Bytes per Packet:             0
	Frames per Packet:          512
	Bytes per Frame:              0
	Channels per Frame:           2
	Bits per Channel:             0

( Ref: https://developer.apple.com/library/content/samplecode/iPhoneACFileConvertTest/Introduction/Intro.html#//apple_ref/doc/uid/DTS40010581-Intro-DontLinkElementID_2 )
#### AACEncoder根據buffer format description設置encoder
`- (void) setupEncoderFromSampleBuffer:(CMSampleBufferRef)sampleBuffer`

- 以`CMAudioFormatDescriptionGetStreamBasicDescription`跟`CMSampleBufferGetFormatDescription`從CMSampleBuffer取得source foramt

		AudioStreamBasicDescription inAudioStreamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));

- 設置 output format 

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

- 以sourceFormat跟outputFormat，建立Converter

	基本的建立方式

		OSStatus status = AudioConverterNew(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, &_audioConverter);

	指定編碼格式
	
    	AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:'appl']; //軟編
		status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &_audioConverter);
    
	在Stackoverflow的討論(ref: https://stackoverflow.com/questions/16487722/real-time-converting-the-pcm-buffer-to-aac-data-for-ios-using-remote-io-and-audi )上，有人說指定以軟編的方式可以解決聲音斷斷續續的問題

		I can hear the audio for 2 second and it is stuck for the next 2 seconds and the pattern continues..
		I finally found the issue! I was losing my mind over this one. The converter was using kAppleHardwareAudioCodecManufacturer by default. Changing it to kAppleSoftwareAudioCodecManufacturer fixed it. – Mihai Ghete Jan 14 '16 at 2:17

	但提問者的平台僅限制在iOS上，Mac上沒有`kAppleHardwareAudioCodecManufacturer `參數；且後來以Timer polling去在正確時間點觸發FillComplexBuffer就解決了pop sound的問題。
    
	或許在iOS上採取軟體編碼Converter可以無視frame數限制。


- 取得Converter packetSize 以供`AudioFillComplexBuffer`使用

		AudioConverterGetProperty (_audioConverter,
                                        kAudioConverterPropertyMaximumOutputPacketSize,
                                        &dataSize,
                                        &maxOutputSizePerPacket );
                                        
		self.aacPacketSize = maxOutputSizePerPacket;
        self.aacPredictBufferSize = maxOutputSizePerPacket; //should be 1 packet per buffer

	AAC-ELD根據規範，沒有ADTS Header；推測應該跟pcm一樣是直接data buffer的格式；又因為AAC為壓縮格式，無法跟PCM一樣由Sample rate, bitrate, channel, buffer size來推論該buffer該作為多少packet播放多久時間；因此每個buffer應當都直接當做一個packet做播放。

- 設定Converter bitarte

		AudioConverterSetProperty(_audioConverter, kAudioConverterEncodeBitRate, propSize, &outputBitRate);


#### 將Sample buffer搬入PCMBuffer property
    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &bufferListSizeNeededOut, &audioBufferList, sizeof(AudioBufferList), NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
        
    TPCircularBufferProduceBytes(&self->_pcmBuffer,audioBufferList.mBuffers[0].mData,audioBufferList.mBuffers[0].mDataByteSize);
    
原本使用`[NSMutableData dataWithBytes:length]`，為了記憶體效率，用CircularBuffer代替

#### 觸發 AudioFillComplexBuffer
`- (void) runEncodeLoop`

原本採用當SampleBuffer輸入後再Encode，但發生聲音斷斷續續的問題，經trace後推測應該是時間點錯誤。

預期Mac每次輸出PCM Sample buffer 為2048 bytes -> 依據 pcm規格 16 bits per channel, 2 channel per frame, 1 frame per packet -> 4 bytes per packet -> 輸入為 512 packets（512frames）

又推測 encoder 每秒執行應執行44100(PCM Sample rate, means 44100frames)/480(AAC Encoder需求480frame per packet) = 99.x 次

於是以Timer polling 方式去處理

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
# 關於Decoder
- Decoder部分使用fdk，VLC的FAAC不支援AAC-ELD( ref: https://wiki.videolan.org/Advanced+Audio+Coding )
- 由於AAC-ELD 為壓縮格式，bitrate不固定，Decoder除非傳輸的時候有定protocol，否則在收到多個packet的情況下會一律當做一個packet去解碼

# Reference

### 官方文件

#### Apple API - AudioConverter
https://developer.apple.com/documentation/audiotoolbox/audio_converter_services?language=objc
https://developer.apple.com/documentation/audiotoolbox/audioconvertercomplexinputdataproc?language=objc
#### Apple Sample Code - AudioConverter
https://developer.apple.com/library/content/samplecode/iPhoneACFileConvertTest/Introduction/Intro.html#//apple_ref/doc/uid/DTS40010581-Intro-DontLinkElementID_2

#### IIS - AAC-ELD （含Spec,sample code）
https://www.iis.fraunhofer.de/en/ff/amm/dl/whitepapers.html

### 討論

#### AudioConverter 使用問題 - Apple Q&A - 如果Streaming data無法滿足Converter input需求
https://developer.apple.com/library/content/qa/qa1317/_index.html
https://lists.apple.com/archives/coreaudio-api/2004/Apr/msg00088.html

#### AudioConverter 使用問題 - Pop sound
https://stackoverflow.com/questions/16487722/real-time-converting-the-pcm-buffer-to-aac-data-for-ios-using-remote-io-and-audi
https://stackoverflow.com/questions/30271186/how-do-i-use-coreaudios-audioconverter-to-encode-aac-in-real-time/30271187#30271187

#### 其他 - 使用FAAC？
https://maxwellqi.github.io/ios-audio-pcm-aac/

#### 其他 - 使用AudioToolbox編碼AAC
https://www.jianshu.com/p/a671f5b17fc1
https://github.com/loyinglin/LearnVideoToolBox/tree/master/Tutorial03-EncodeAAC.AAC
