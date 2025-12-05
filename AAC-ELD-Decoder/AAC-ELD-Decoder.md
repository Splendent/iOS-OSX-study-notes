# AAC-ELD 解碼完整技術文件

## 目錄

1. [概述](#概述)
2. [技術背景](#技術背景)
3. [Apple AudioConverter API 詳解](#apple-audioconverter-api-詳解)
4. [完整實作範例](#完整實作範例)
5. [AudioSpecificConfig (ASC) 說明](#audiospecificconfig-asc-說明)
6. [Frame 結構與資料處理](#frame-結構與資料處理)
7. [實測環境](#實測環境)
8. [參考來源](#參考來源)

## 概述

AAC-ELD（Enhanced Low Delay）是一種低延遲的音訊壓縮格式，常用於即時串流應用（如 AirPlay）。本文件說明如何在 Apple 體系下使用 `AudioConverter` API 解碼 AAC-ELD 音訊資料。

**關鍵要點**：
- 使用 `AudioToolbox` 框架的 `AudioConverter` API
- 輸入格式：`kAudioFormatMPEG4AAC_ELD`
- 輸出格式：`kAudioFormatLinearPCM`
- **實測環境中，不設置 AudioSpecificConfig (ASC) 也可以正常運作**

## 技術背景

### AAC-ELD 規格

- **標準 frame 長度**：480 或 512 samples
- **常見取樣率**：44100 Hz 或 48000 Hz
- **聲道配置**：1（單聲道）或 2（立體聲）

### Apple AudioConverter

`AudioConverter` 是 Apple 提供的音訊格式轉換 API，支援多種壓縮格式的解碼，包括 AAC-ELD。它使用 `AudioStreamBasicDescription` (ASBD) 來描述輸入和輸出的音訊格式。

## Apple AudioConverter API 詳解

### 1. 建立 AudioConverter

使用 `AudioConverterNew` 建立轉換器：

```swift
var converter: AudioConverterRef?
let status = AudioConverterNew(&inDesc, &outDesc, &converter)

guard status == noErr, let createdConverter = converter else {
    throw DecoderError.cannotCreateConverter(status)
}
```

### 2. 設定輸入格式（AAC-ELD）

```swift
var inDesc = AudioStreamBasicDescription()
inDesc.mSampleRate       = 44100        // 取樣率（Hz）
inDesc.mFormatID         = kAudioFormatMPEG4AAC_ELD  // AAC-ELD 格式識別碼
inDesc.mFormatFlags      = 0            // AAC-ELD 不使用 format flags
inDesc.mBytesPerPacket   = 0            // 壓縮格式，變動長度，設為 0
inDesc.mFramesPerPacket  = 480          // AAC-ELD 標準：每 packet 480 frames
inDesc.mBytesPerFrame    = 0            // 壓縮格式不使用此欄位
inDesc.mChannelsPerFrame = 2            // 聲道數（1=單聲道, 2=立體聲）
inDesc.mBitsPerChannel   = 0            // 壓縮格式不使用此欄位
inDesc.mReserved         = 0            // 保留欄位，必須為 0
```

**參數說明**：
- `mFramesPerPacket = 480`：這是 AAC-ELD 的標準 frame 長度。也有可能是512。
- `mBytesPerPacket = 0`：因為 AAC-ELD 是壓縮格式，每個 packet 的 byte 數是變動的，無法預先知道

### 3. 設定輸出格式（PCM）

```swift
var outDesc = AudioStreamBasicDescription()
outDesc.mSampleRate       = 44100       // 輸出取樣率（通常與輸入相同）
outDesc.mFormatID         = kAudioFormatLinearPCM  // 線性 PCM 格式
outDesc.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                           // 有號整數、打包格式（交錯排列）
outDesc.mChannelsPerFrame = 2           // 輸出聲道數
outDesc.mBitsPerChannel   = 16          // 每個樣本 16 bits
outDesc.mFramesPerPacket  = 1           // PCM 每個 packet 就是 1 frame
outDesc.mBytesPerFrame    = 4           // 2 channels * 16 bits / 8 = 4 bytes
outDesc.mBytesPerPacket   = 4           // 等於 mBytesPerFrame * mFramesPerPacket
outDesc.mReserved         = 0
```

**計算說明**：
- `mBytesPerFrame = 4`：2 聲道 × 16 bits ÷ 8 = 4 bytes
- `mBytesPerPacket = 4`：因為 `mFramesPerPacket = 1`，所以等於 `mBytesPerFrame`

### 4. 解碼資料

使用 `AudioConverterFillComplexBuffer` 進行解碼：

```swift
var outBufferList = AudioBufferList()
outBufferList.mNumberBuffers = 1
outBufferList.mBuffers.mNumberChannels = channels
outBufferList.mBuffers.mDataByteSize = UInt32(outputByteCount)
outBufferList.mBuffers.mData = outBaseAddress

var ioOutputDataPackets: UInt32 = maxOutputFrames

let decodeStatus = AudioConverterFillComplexBuffer(
    converter,
    AACELDInputDataProc,      // 輸入資料回調函數
    &packetContext,           // 使用者資料（包含 AAC frame 資料）
    &ioOutputDataPackets,     // 輸入/輸出：請求的 packet 數，輸出實際產生的 packet 數
    &outBufferList,           // 輸出緩衝區
    nil                       // packet description（可選）
)
```

**緩衝區大小計算**：
```swift
// 預期最大輸出：480 frames × 4 bytes/frame = 1920 bytes
let maxOutputFrames = 480  // 來自 inputFormat.inputFramesPerPacket
let bytesPerFrame = 4      // 2 channels * 16 bits / 8
let outputByteCount = maxOutputFrames * bytesPerFrame  // 1920 bytes
```

### 5. 輸入資料回調函數

`AudioConverterFillComplexBuffer` 需要一個回調函數來提供輸入資料：

```swift
func AACELDInputDataProc(
    _ inAudioConverter: AudioConverterRef,
    _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
    _ ioData: UnsafeMutablePointer<AudioBufferList>,
    _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    
    guard let userData = inUserData else {
        ioNumberDataPackets.pointee = 0
        return noErr
    }
    
    let context = userData.assumingMemoryBound(to: PacketContext.self)
    
    // 設定輸出緩衝區資訊
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mNumberChannels = context.pointee.channelCount
    ioData.pointee.mBuffers.mDataByteSize = context.pointee.size
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: context.pointee.data)
    ioNumberDataPackets.pointee = 1  // 提供 1 個 packet
    
    // 設定 packet description（如果 AudioConverter 需要）
    if let outDesc = outDataPacketDescription {
        outDesc.pointee = context.pointee.packetDescPtr
    }
    
    return noErr
}
```

**Packet Description 說明**：

`AudioStreamPacketDescription` 用於描述壓縮格式的 packet 資訊，包含：
- `mStartOffset`：packet 在資料緩衝區中的起始位置（通常為 0）
- `mVariableFramesInPacket`：變動長度 packet 的 frame 數（AAC-ELD 固定為 0，因為 frame 數已定義在 ASBD 中）
- `mDataByteSize`：packet 的 byte 大小

在 `decode` 函數中建立 packet description：

```swift
var packetDesc = AudioStreamPacketDescription(
    mStartOffset: 0,                    // 從緩衝區開頭開始
    mVariableFramesInPacket: 0,         // 固定 frame 數，不使用此欄位
    mDataByteSize: UInt32(aacFrame.count)  // AAC frame 的實際大小
)

withUnsafeMutablePointer(to: &packetDesc) { packetDescPtr in
    var packetInfo = PacketContext(
        data: inBaseAddress,
        size: UInt32(aacFrame.count),
        channelCount: channels,
        packetDescPtr: packetDescPtr  // 傳入 packet description 指標
    )
    // ...
}
```

參考實作：`AACELDDecoder.swift` 第 198-210 行（建立 packet description）、第 416-418 行（在回調函數中設定）

## 完整實作範例

### 基本使用

```swift
import AudioToolbox

class AACELDDecoder {
    private var converter: AudioConverterRef?
    
    func configureDecoder() throws {
        // 設定輸入格式
        var inDesc = AudioStreamBasicDescription()
        inDesc.mSampleRate = 44100
        inDesc.mFormatID = kAudioFormatMPEG4AAC_ELD
        inDesc.mFormatFlags = 0
        inDesc.mBytesPerPacket = 0
        inDesc.mFramesPerPacket = 480
        inDesc.mBytesPerFrame = 0
        inDesc.mChannelsPerFrame = 2
        inDesc.mBitsPerChannel = 0
        inDesc.mReserved = 0
        
        // 設定輸出格式
        var outDesc = AudioStreamBasicDescription()
        outDesc.mSampleRate = 44100
        outDesc.mFormatID = kAudioFormatLinearPCM
        outDesc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        outDesc.mChannelsPerFrame = 2
        outDesc.mBitsPerChannel = 16
        outDesc.mFramesPerPacket = 1
        outDesc.mBytesPerFrame = 4
        outDesc.mBytesPerPacket = 4
        outDesc.mReserved = 0
        
        // 建立轉換器
        var newConverter: AudioConverterRef?
        let status = AudioConverterNew(&inDesc, &outDesc, &newConverter)
        
        guard status == noErr, let createdConverter = newConverter else {
            throw DecoderError.cannotCreateConverter(status)
        }
        
        converter = createdConverter
        
        // 注意：不設置 magic cookie 也可以運作
    }
    
    func decode(_ aacFrame: Data) throws -> Data? {
        guard let converter = converter else {
            throw DecoderError.converterNotConfigured
        }
        
        let maxOutputFrames: UInt32 = 480
        let bytesPerFrame = 4
        let outputByteCount = Int(maxOutputFrames) * bytesPerFrame
        var pcmData = Data(count: outputByteCount)
        
        var decodeStatus: OSStatus = noErr
        var outPackets: UInt32 = 0
        
        aacFrame.withUnsafeBytes { inRawBuffer in
            guard let inBaseAddress = inRawBuffer.baseAddress else { return }
            
            // 建立 packet description
            var packetDesc = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(aacFrame.count)
            )
            
            withUnsafeMutablePointer(to: &packetDesc) { packetDescPtr in
                var packetInfo = PacketContext(
                    data: inBaseAddress,
                    size: UInt32(aacFrame.count),
                    channelCount: 2,
                    packetDescPtr: packetDescPtr
                )
                
                pcmData.withUnsafeMutableBytes { outRawBuffer in
                    guard let outBaseAddress = outRawBuffer.baseAddress else { return }
                    
                    var outBufferList = AudioBufferList()
                    outBufferList.mNumberBuffers = 1
                    outBufferList.mBuffers.mNumberChannels = 2
                    outBufferList.mBuffers.mDataByteSize = UInt32(outputByteCount)
                    outBufferList.mBuffers.mData = outBaseAddress
                    
                    var ioOutputDataPackets: UInt32 = maxOutputFrames
                    
                    decodeStatus = AudioConverterFillComplexBuffer(
                        converter,
                        AACELDInputDataProc,
                        &packetInfo,
                        &ioOutputDataPackets,
                        &outBufferList,
                        nil
                    )
                    
                    outPackets = ioOutputDataPackets
                }
            }
        }
        
        guard decodeStatus == noErr, outPackets > 0 else {
            throw DecoderError.decodeFailed(decodeStatus)
        }
        
        let bytesProduced = Int(outPackets) * bytesPerFrame
        return pcmData.prefix(bytesProduced)
    }
    
    deinit {
        if let converter = converter {
            AudioConverterDispose(converter)
        }
    }
}
```

完整實作請參考：`AACELDDecoder.swift`

## AudioSpecificConfig (ASC) 說明

### 什麼是 AudioSpecificConfig？

AudioSpecificConfig（ASC）是描述 AAC 編碼參數的二進位資料，也稱為 "magic cookie"。它包含：
- AOT (Audio Object Type)
- 取樣率
- 聲道配置
- Frame 長度等資訊

### Apple 體系下的實測結果

**不設置 ASC 也可以正常運作**

在實測環境中，即使不設置 `kAudioConverterDecompressionMagicCookie`，`AudioConverter` 仍然可以正常解碼 AAC-ELD 資料。推測因為輸入的 `AudioStreamBasicDescription` 已經提供了足夠的格式資訊

**實作參考**：
```swift
try self.decoder.configureDecoder(
    aacConfig: nil,  // 不設置 ASC
    aaceldInputFormat: AACELDDecoder.AACELDInputFormat.default
)
```

### 為什麼 fdk-aac 的 ASC 會出錯？

Android 上的 fdk-aac lib，其 ASC 格式為 `[0xF8, 0xE8, 0x50, 0x00]`（參考：`AndroidAacEldDecoder.java` 第 23 行）：

```java
byte[] bytes = new byte[]{(byte) 0xF8, (byte) 0xE8, 0x50, 0x00};
```

但這個格式在 Apple 的 `AudioConverter` 中可能會導致錯誤，推測原因：

1. **格式差異**：fdk-aac 和 Apple 的 AudioConverter 可能使用不同的 ASC 編碼格式
2. **自動解析**：Apple 的實作可能更傾向於從 frame header 自動解析，而不是依賴外部提供的 ASC

**建議做法**：
- 在 Apple 體系下，**不設置 ASC**（傳入 `nil`）
- 讓 `AudioConverter` 自動從 frame 資料中解析配置

### 如何產生 ASC（僅供參考）

雖然實測中不需要，但 `AACELDDecoder.swift` 提供了產生 ASC 的方法（第 441-486 行）：

```swift
func makeAsc(sampleRate: Int, channels: Int, frameDuration: Int) throws -> Data {
    var asc = [UInt8](repeating: 0, count: 4)
    
    // AOT 39 (AAC-ELD) 編碼
    asc[0] |= 0xF8  // 11111000
    
    // 取樣率與 AOT 延伸
    switch sampleRate {
    case 48000:
        asc[1] |= 0x06
    case 44100:
        asc[1] |= 0x08
    default:
        throw AscError.unsupportedSampleRate
    }
    
    // 聲道配置
    switch channels {
    case 1:
        asc[2] |= 0x20
    case 2:
        asc[2] |= 0x40
    default:
        throw AscError.unsupportedChannelCount
    }
    
    // Frame 長度
    switch frameDuration {
    case 512:
        asc[2] |= 0x00
    case 480:
        asc[2] |= 0x10
    default:
        throw AscError.unsupportedFrameDuration
    }
    
    return Data(asc)
}
```

**注意**：此方法產生的 ASC 格式可能與 Apple `AudioConverter` 期望的格式不同。

## Frame 結構與資料處理

### Frame 結構特點

**關鍵特性**：
- **每次收到的 audio data 即為一個完整的 frame**
- **AAC-ELD 是壓縮格式，無法直接根據規格反推 1 frame 是多少 bytes**

這與 PCM 格式不同：
- PCM：可以根據取樣率、聲道數、位元深度計算每個 frame 的 byte 數
- AAC-ELD：每個 frame 的 byte 數是變動的，取決於壓縮率

### 資料接收與處理

在本次範例中預期每次從網路接收到的資料就是一個完整的 AAC-ELD frame：

```swift
// 每次接收到的資料就是一個 frame
public func play(_ aacData: Data) {
    // aacData 就是一個完整的 AAC-ELD frame
    let (pcmData, _, _) = try decoder.decode(aacData)
    // ...
}
```

參考實作：`AACELDRenderer.swift` 第 64-84 行

### 使用自定義分隔符標記 Packets

由於無法直接計算 frame 的 byte 數，在 dump 或儲存 raw stream 時，需要使用自定義分隔符來標記每個 packet：

**分隔符定義**：
```swift
// AACELDDumper.swift 第 13 行
private static let audioPacketMarker = Data([0xFF, 0xAA, 0xCC, 0xDD])
```

**寫入時加入分隔符**：
```swift
recordedData.append(Self.audioPacketMarker)  // 先寫入分隔符
recordedData.append(data)                     // 再寫入 frame 資料
```

**讀取時解析分隔符**：
```swift
static func parsePackets(from data: Data) -> [Data] {
    var packets: [Data] = []
    let marker = Data([0xFF, 0xAA, 0xCC, 0xDD])
    
    // 尋找分隔符來分割 packets
    // ...
}
```

完整實作請參考：`AACELDDumper.swift` 第 126-162 行

## 實測環境

### Converter 屬性查詢結果

在實測環境中，查詢 converter 屬性可能得到以下結果：

```
=== Converter Input ASBD ===
mFormatID:         1633772389  (kAudioFormatMPEG4AAC_ELD)
mFormatFlags:      0x0
mChannelsPerFrame: 2
isNonInterleaved:  false

=== Converter Output ASBD ===
mSampleRate:       44100.000000
mFormatID:         1819304813  (kAudioFormatLinearPCM)
mFormatFlags:      0xc
mChannelsPerFrame: 2
mBytesPerFrame:    4
mBytesPerPacket:   4
isNonInterleaved:  false

=== Converter Prime Info ===
leadingFrames:     0
trailingFrames:    0

AudioConverterGetPropertyInfo (decompression magic cookie) failed: 1886547824
```

**觀察**：
- Magic cookie 查詢失敗（錯誤碼 1886547824），但這不影響解碼功能
- Prime info 顯示 leading/trailing frames 為 0，表示不需要額外的 priming frames
- 輸出格式正確：44.1kHz, 2 聲道, 16-bit PCM

## 參考來源
### fdk-aac 相關

1. **fdk-aac-master**
   - [Fraunhofer FDK AAC 編解碼庫](https://github.com/mstorsjo/fdk-aac)
   - 注意：Apple 體系下的 ASC 格式可能與此不同

### Apple 官方文件

- **AudioToolbox Framework**
  - [`AudioConverter` API 文件](https://developer.apple.com/documentation/audiotoolbox/audio-converter-services)
  - [`AudioStreamBasicDescription` 結構說明](https://developer.apple.com/documentation/CoreAudioTypes/AudioStreamBasicDescription)
  - [AudioConverterFillComplexBuffer](https://developer.apple.com/documentation/audiotoolbox/audioconverterfillcomplexbufferwithpacketdependencies(_:_:_:_:_:_:_:))
  - [Encoding and decoding audio Sample Code](https://developer.apple.com/documentation/audiotoolbox/encoding-and-decoding-audio)


