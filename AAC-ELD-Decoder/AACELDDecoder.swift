//
//  AACELDPlayer.swift
//  SwiftScreenCore
//
//  Created by Splenden on 2025/12/1.
//


import Foundation
import AVFoundation
import AudioToolbox
import OSLog

struct PacketContext {
    let data: UnsafeRawPointer
    let size: UInt32
    let channelCount: UInt32
    let packetDescPtr: UnsafeMutablePointer<AudioStreamPacketDescription>
}

/// Simple AAC-ELD decoder + local playback using AVAudioEngine
class AACELDDecoder {
    
    /// AAC-ELD input format configuration
    struct AACELDInputFormat {
        let inputSampleRate: Double
        let inputChannels: UInt32
        let inputFramesPerPacket: UInt32
        
        static let `default` = AACELDInputFormat(
            inputSampleRate: 44100,
            inputChannels: 2,
            inputFramesPerPacket: 480  // AAC-ELD standard frames per packet
        )
    }
    
    /// PCM output format configuration
    struct PCMOutputFormat {
        let outputSampleRate: Double
        let outputChannels: UInt32
        let outputBitsPerChannel: UInt32
        
        static let `default` = PCMOutputFormat(
            outputSampleRate: 44100,
            outputChannels: 2,
            outputBitsPerChannel: 16
        )
    }
    
    /// Errors specific to AACELDPlayer
    enum DecoderError: Error {
        case converterNotConfigured
        case cannotCreateConverter(OSStatus)
        case cannotSetMagicCookie(OSStatus)
        case decodeFailed(OSStatus)
    }
    
    // MARK: - Audio converter & formats
    
    private var converter: AudioConverterRef?
    private var inputFormat: AACELDInputFormat?
    private var outputFormat: PCMOutputFormat?
    
    /// Logger for debugging
    private static let subsystemId = Bundle.main.bundleIdentifier! + ".AACELDDecoder"
    private let logger = Logger(subsystem: subsystemId, category: "Main")
    
    // MARK: - Lifecycle
    
    deinit {
        if let converter = converter {
            AudioConverterDispose(converter)
        }
    }
    
    var isReady: Bool { self.converter != nil }
    
    // MARK: - 
    
    /// Configure AAC-ELD decoder.
    /// - Parameters:
    ///   - aacConfig: AudioSpecificConfig (magic cookie) data for AAC-ELD.
    ///   - aaceldInputFormat: AAC-ELD input format configuration.
    ///   - pcmOutputFormat: PCM output format configuration. Default is 44.1kHz, 2 channels, 16-bit.
    func configureDecoder(aacConfig: Data?,
                          aaceldInputFormat: AACELDInputFormat = .default,
                          pcmOutputFormat: PCMOutputFormat = .default) throws {
        
        // Describe input AAC-ELD compressed format.
        // AACELDInputFormat.default = 44.1 kHz, 2 channels, 480 frames/packet.
        var inDesc = AudioStreamBasicDescription()
        // Sampling rate of the encoded AAC-ELD stream in Hz (default: 44100).
        inDesc.mSampleRate       = aaceldInputFormat.inputSampleRate
        // Audio format identifier for AAC-ELD elementary stream.
        inDesc.mFormatID         = kAudioFormatMPEG4AAC_ELD
        // Format flags for AAC-ELD (none used, always 0).
        inDesc.mFormatFlags      = 0
        // Compressed packet size field in bytes (0 = variable).
        inDesc.mBytesPerPacket   = 0
        // Frames per AAC-ELD access unit (default: 480).
        inDesc.mFramesPerPacket  = aaceldInputFormat.inputFramesPerPacket
        // Bytes per frame for compressed data (not used, kept 0).
        inDesc.mBytesPerFrame    = 0
        // Channel count in the encoded AAC-ELD stream (default: 2).
        inDesc.mChannelsPerFrame = aaceldInputFormat.inputChannels
        // Bits per channel for compressed AAC-ELD data (not used, kept 0).
        inDesc.mBitsPerChannel   = 0
        // Reserved field in AudioStreamBasicDescription, must be 0.
        inDesc.mReserved         = 0
        
        // Describe decoded PCM output format.
        // PCMOutputFormat.default = 44.1 kHz, 2‑channel, 16‑bit signed PCM.
        var outDesc = AudioStreamBasicDescription()
        // Sampling rate of the decoded PCM stream in Hz (default: 44100).
        outDesc.mSampleRate       = pcmOutputFormat.outputSampleRate
        // Audio format identifier for linear PCM.
        outDesc.mFormatID         = kAudioFormatLinearPCM
        // Signed-integer, packed (interleaved) PCM samples.
        outDesc.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        // Number of interleaved channels in each PCM frame (default: 2).
        outDesc.mChannelsPerFrame = pcmOutputFormat.outputChannels
        // Bit depth per channel for each PCM sample (default: 16).
        outDesc.mBitsPerChannel   = pcmOutputFormat.outputBitsPerChannel
        // One PCM frame per packet.
        outDesc.mFramesPerPacket  = 1
        // Total bytes in one interleaved PCM frame across all channels
        // (default: 4 bytes = 2 channels * 16 bits / 8).
        outDesc.mBytesPerFrame    = UInt32(outDesc.mChannelsPerFrame) * UInt32(outDesc.mBitsPerChannel / 8)
        // Total bytes in one PCM packet (equal to one frame here, default: 4).
        outDesc.mBytesPerPacket   = outDesc.mBytesPerFrame * outDesc.mFramesPerPacket
        // Reserved field in AudioStreamBasicDescription, must be 0.
        outDesc.mReserved         = 0
        
        // Dispose existing converter if needed
        if let existing = converter {
            AudioConverterDispose(existing)
            converter = nil
        }
        
        // Create converter
        var newConverter: AudioConverterRef?
        let status = AudioConverterNew(
            &inDesc,
            &outDesc,
            &newConverter
        )
        
        guard status == noErr, let createdConverter = newConverter else {
            throw DecoderError.cannotCreateConverter(status)
        }
        
        converter = createdConverter
        dumpConverterInfo(createdConverter)
        inputFormat = aaceldInputFormat
        outputFormat = pcmOutputFormat
        
        // Set magic cookie (AudioSpecificConfig)
        if let aacConfig = aacConfig, !aacConfig.isEmpty {
            try aacConfig.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                let cookieSize = UInt32(aacConfig.count)
                let statusCookie = AudioConverterSetProperty(
                    createdConverter,
                    kAudioConverterDecompressionMagicCookie,
                    cookieSize,
                    baseAddress
                )
                if statusCookie != noErr {
                    throw DecoderError.cannotSetMagicCookie(statusCookie)
                }
            }
        }
    }
    
    func decode(_ aacFrame: Data, play: Bool = false) throws -> (Data?, OSStatus, UInt32) {
        guard let converter = converter, let inputFormat = inputFormat, let outputFormat = outputFormat else {
            throw DecoderError.converterNotConfigured
        }
        
        // Number of channels in decoded PCM (default: 2).
        let channels = outputFormat.outputChannels
        // Bytes per PCM frame across all channels: channels * bitsPerChannel / 8
        // (default: 4 bytes = 2 channels * 16 bits / 8).
        let bytesPerFrame = Int(outputFormat.outputChannels * outputFormat.outputBitsPerChannel / 8)
        // Maximum PCM frames produced for one AAC-ELD packet (default: 480).
        let maxOutputFrames = inputFormat.inputFramesPerPacket
        // Total buffer size in bytes for one decode call
        // (default: 1920 bytes = 480 frames * 4 bytes/frame).
        let outputByteCount = Int(maxOutputFrames) * bytesPerFrame
        
        var decodeStatus: OSStatus = noErr
        var outPackets: UInt32 = 0
        var pcmData = Data(count: outputByteCount)
        
        aacFrame.withUnsafeBytes { inRawBuffer in
            guard let inBaseAddress = inRawBuffer.baseAddress else { return }
            
            var packetDesc = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(aacFrame.count)
            )
            
            withUnsafeMutablePointer(to: &packetDesc) { packetDescPtr in
                var packetInfo = PacketContext(
                    data: inBaseAddress,
                    size: UInt32(aacFrame.count),
                    channelCount: channels,
                    packetDescPtr: packetDescPtr
                )
                
                pcmData.withUnsafeMutableBytes { outRawBuffer in
                    guard let outBaseAddress = outRawBuffer.baseAddress else { return }
                    
                    var outBufferList = AudioBufferList()
                    outBufferList.mNumberBuffers = 1
                    outBufferList.mBuffers.mNumberChannels = channels
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
        // Data.prefix won't create/copy new Data
        return (pcmData.prefix(bytesProduced), decodeStatus, outPackets)
    }
    
    func dumpConverterInfo(_ converter: AudioConverterRef) {
        // Input ASBD
        var iasbd = AudioStreamBasicDescription()
        var isize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        let istatus = AudioConverterGetProperty(
            converter,
            kAudioConverterCurrentInputStreamDescription,
            &isize,
            &iasbd
        )
        
        if istatus == noErr {
            logger.info("=== Converter Input ASBD ===")
            logger.info("mFormatID:         \(iasbd.mFormatID)")
            logger.info("mFormatFlags:      0x\(String(iasbd.mFormatFlags, radix: 16))")
            logger.info("mChannelsPerFrame: \(iasbd.mChannelsPerFrame)")
            let isNonInterleaved = (iasbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            logger.info("isNonInterleaved:  \(isNonInterleaved)")
        } else {
            logger.error("AudioConverterGetProperty (input) failed: \(istatus)")
        }
        
        // Output ASBD
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        let status = AudioConverterGetProperty(
            converter,
            kAudioConverterCurrentOutputStreamDescription,
            &size,
            &asbd
        )
        
        if status == noErr {
            logger.info("=== Converter Output ASBD ===")
            logger.info("mSampleRate:       \(asbd.mSampleRate)")
            logger.info("mFormatID:         \(asbd.mFormatID)")
            logger.info("mFormatFlags:      0x\(String(asbd.mFormatFlags, radix: 16))")
            logger.info("mChannelsPerFrame: \(asbd.mChannelsPerFrame)")
            logger.info("mBytesPerFrame:    \(asbd.mBytesPerFrame)")
            logger.info("mBytesPerPacket:   \(asbd.mBytesPerPacket)")
            
            let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            logger.info("isNonInterleaved:  \(isNonInterleaved)")
        } else {
            logger.error("AudioConverterGetProperty (output) failed: \(status)")
        }
        
        // Prime info
        var primeInfo = AudioConverterPrimeInfo()
        var propSize = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
        let primeStatus = AudioConverterGetProperty(
            converter,
            kAudioConverterPrimeInfo,
            &propSize,
            &primeInfo
        )
        
        if primeStatus == noErr {
            logger.info("=== Converter Prime Info ===")
            logger.info("leadingFrames:     \(primeInfo.leadingFrames)")
            logger.info("trailingFrames:    \(primeInfo.trailingFrames)")
        } else {
            logger.error("AudioConverterGetProperty (primeInfo) failed: \(primeStatus)")
        }
        
        // Decompression magic cookie (only log size to avoid dumping raw bytes)
        var cookieSize: UInt32 = 0
        let cookieInfoStatus = AudioConverterGetPropertyInfo(
            converter,
            kAudioConverterDecompressionMagicCookie,
            &cookieSize,
            nil
        )
        
        if cookieInfoStatus == noErr {
            if cookieSize > 0 {
                logger.info("Decompression magic cookie size: \(cookieSize) bytes")
            } else {
                logger.info("Decompression magic cookie not present (size = 0)")
            }
        } else {
            logger.error("AudioConverterGetPropertyInfo (decompression magic cookie) failed: \(cookieInfoStatus)")
        }
        
        // Minimum / maximum buffer and packet sizes
        var minInputBufferSize: UInt32 = 0
        propSize = UInt32(MemoryLayout.size(ofValue: minInputBufferSize))
        let minInStatus = AudioConverterGetProperty(
            converter,
            kAudioConverterPropertyMinimumInputBufferSize,
            &propSize,
            &minInputBufferSize
        )
        if minInStatus == noErr {
            logger.info("Minimum input buffer size: \(minInputBufferSize) bytes")
        } else {
            logger.error("AudioConverterGetProperty (min input buffer size) failed: \(minInStatus)")
        }
        
        var minOutputBufferSize: UInt32 = 0
        propSize = UInt32(MemoryLayout.size(ofValue: minOutputBufferSize))
        let minOutStatus = AudioConverterGetProperty(
            converter,
            kAudioConverterPropertyMinimumOutputBufferSize,
            &propSize,
            &minOutputBufferSize
        )
        if minOutStatus == noErr {
            logger.info("Minimum output buffer size: \(minOutputBufferSize) bytes")
        } else {
            logger.error("AudioConverterGetProperty (min output buffer size) failed: \(minOutStatus)")
        }
        
        var maxInputPacketSize: UInt32 = 0
        propSize = UInt32(MemoryLayout.size(ofValue: maxInputPacketSize))
        let maxInPacketStatus = AudioConverterGetProperty(
            converter,
            kAudioConverterPropertyMaximumInputPacketSize,
            &propSize,
            &maxInputPacketSize
        )
        if maxInPacketStatus == noErr {
            logger.info("Maximum input packet size: \(maxInputPacketSize) bytes")
        } else {
            logger.error("AudioConverterGetProperty (max input packet size) failed: \(maxInPacketStatus)")
        }
        
        var maxOutputPacketSize: UInt32 = 0
        propSize = UInt32(MemoryLayout.size(ofValue: maxOutputPacketSize))
        let maxOutPacketStatus = AudioConverterGetProperty(
            converter,
            kAudioConverterPropertyMaximumOutputPacketSize,
            &propSize,
            &maxOutputPacketSize
        )
        if maxOutPacketStatus == noErr {
            logger.info("Maximum output packet size: \(maxOutputPacketSize) bytes")
        } else {
            logger.error("AudioConverterGetProperty (max output packet size) failed: \(maxOutPacketStatus)")
        }
    }
}

// MARK: - AudioConverter callback

/// AudioConverter input data callback.
/// Provides compressed AAC-ELD data to the converter.
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
    guard ioNumberDataPackets.pointee != 0 else { return noErr }
    let context = userData.assumingMemoryBound(to: PacketContext.self)
    
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mNumberChannels = context.pointee.channelCount
    ioData.pointee.mBuffers.mDataByteSize = context.pointee.size
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: context.pointee.data)
    ioNumberDataPackets.pointee = 1
    
    if let outDesc = outDataPacketDescription {
        outDesc.pointee = context.pointee.packetDescPtr
    }
    
    return noErr
}


extension AACELDDecoder {
    enum AscError: Error {
        case unsupportedSampleRate
        case unsupportedChannelCount
        case unsupportedFrameDuration
    }
    
    /// Build 4-byte ASC for AAC-ELD with limited configuration:
    /// - AOT: 39 (AAC-ELD)
    /// - Sample rate: 48000 or 44100
    /// - Channels: 1 or 2
    /// - Frame duration: 512 or 480 samples
    /// Example: F8 E8 50 00
    /// 0xF8    // 11111000 - AOT = 39 (ELD)
    /// 0xE8    // 11101000 - AOT  + 44.1kHz
    /// 0x50    // 01010000 - stereo + 480 samples
    /// 0x00    // 00000000
    func makeAsc(sampleRate: Int,
                    channels: Int,
                    frameDuration: Int) throws -> Data {
        
        var asc = [UInt8](repeating: 0, count: 4)
        
        // AOT encoding: for AOT >= 32, encode as 5 bits (31) + 6 bits (AOT - 32)
        // AOT 39 = 32 + 7, so encode as: 11111 (31) + 000111 (7)
        asc[0] |= 0xF8      // 1111 1000 - first 5 bits: 11111 (31)
        
        // Continue AOT encoding: next 3 bits of the 6-bit extension
        asc[1] |= 0xE0      // 1110 0000 - bits 111 (part of 000111 for AOT extension)
        // samplingFrequencyIndex part
        switch sampleRate {
        case 48000:
            asc[1] |= 0x06  // 0000 0110
        case 44100:
            asc[1] |= 0x08  // 0000 1000
        default:
            throw AscError.unsupportedSampleRate
        }
        
        // channelConfiguration bits
        switch channels {
        case 1:
            asc[2] |= 0x20  // 0010 0000
        case 2:
            asc[2] |= 0x40  // 0100 0000
        default:
            throw AscError.unsupportedChannelCount
        }
        
        // constant duration / frame length flag
        switch frameDuration {
        case 512:
            asc[2] |= 0x00  // frameLengthFlag for 512
        case 480:
            asc[2] |= 0x10  // frameLengthFlag for 480
        default:
            throw AscError.unsupportedFrameDuration
        }
        
        // asc[3] left as 0 (same as your C code)
        
        return Data(asc)
    }
}
