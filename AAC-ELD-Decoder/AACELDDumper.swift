//
//  AACDumpManager.swift
//  SwiftScreenCore
//
//  Created by Splenden on 2025/1/20.
//

import Foundation
import OSLog

class AACELDDumper {
    // Packet delimiter marker: 0xFF 0xAA 0xCC 0xDD
    private static let audioPacketMarker = Data([0xFF, 0xAA, 0xCC, 0xDD])
    
    private var recordedData = Data()
#if DEBUG
    private var isDumpEnabled = true
#else
    private var isDumpEnabled = false
#endif
    /// Logger for debugging
    private static let subsystemId = Bundle.main.bundleIdentifier! + ".AACELDDumper"
    private let logger = Logger(subsystem: subsystemId, category: "Main")
    private let maxDumpSize: Int
    
    init(maxDumpSize: Int = Int(500_000)) {
        self.maxDumpSize = maxDumpSize
    }
    
    
    func appendPacket(_ data: Data) {
        guard isDumpEnabled else { return }
        
        if recordedData.count >= maxDumpSize {
            logger.info("collecting dump audio data... \(self.recordedData.count)")
            dumpAACAudioData()
            isDumpEnabled = false
            recordedData.removeAll()
        } else {
            recordedData.append(Self.audioPacketMarker)
            recordedData.append(data)
        }
    }
    
    enum ReadError: Error {
        case fileNotFound
        case readFailed(Error)
        case invalidFormat
    }
    
    private func dumpAACAudioData() {
        logger.info("Dumping audio data...")
        
        let fileManager = FileManager.default
        if let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            // Create the file URL
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let filename = "aaceld_dump_\(timestamp).aeld"
            let fileURL = downloadsURL.appendingPathComponent(filename)
            
            do {
                // Write the data to the file
                try recordedData.write(to: fileURL)
//                let header = try AACELDDecoder.makeAsc(sampleRate: 44100, channels: 2, frameSamples: 480)
//                let combined = header + recordedData
//                try combined.write(to: fileURL)
                logger.info("\(self.maxDumpSize / 1_000_000) MB file successfully written to \(fileURL.path)")
            } catch {
                // Handle errors
                logger.info("Failed to write file: \(error.localizedDescription)")
            }
        } else {
            logger.info("Failed to access the Downloads directory.")
        }
    }
    
    // MARK: - Read Dump File
    
    /// Read all packets from dump file and return as array
    /// - Parameter fileURL: URL of the dump file
    /// - Returns: Array of packet data
    /// - Throws: ReadError if file cannot be read or format is invalid
    static func readPackets(from fileURL: URL) throws -> [Data] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ReadError.fileNotFound
        }
        
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ReadError.readFailed(error)
        }
        
        return parsePackets(from: fileData)
    }
    
    /// Read packets from dump file and provide them one by one via callback
    /// - Parameters:
    ///   - fileURL: URL of the dump file
    ///   - callback: Closure called for each packet with packet data
    /// - Throws: ReadError if file cannot be read or format is invalid
    static func readPackets(from fileURL: URL, callback: (Data) -> Void) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ReadError.fileNotFound
        }
        
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ReadError.readFailed(error)
        }
        
        let packets = parsePackets(from: fileData)
        for packet in packets {
            callback(packet)
        }
    }
    
    /// Parse packets from data by finding packet markers
    /// - Parameter data: Raw dump file data
    /// - Returns: Array of packet data
    private static func parsePackets(from data: Data) -> [Data] {
        var packets: [Data] = []
        var currentIndex = 0
        let marker = audioPacketMarker
        
        while currentIndex < data.count {
            // Search for marker starting from current index
            guard let markerRange = data.range(of: marker, options: [], in: currentIndex..<data.count) else {
                // No more markers found, check if there's remaining data
                if currentIndex < data.count {
                    // There's data after last marker, treat as incomplete packet (skip)
                    break
                }
                break
            }
            
            // Skip the marker
            let packetStartIndex = markerRange.upperBound
            
            // Find next marker to determine packet end
            if let nextMarkerRange = data.range(of: marker, options: [], in: packetStartIndex..<data.count) {
                // Found next marker, packet is between current and next marker
                let packetData = data[packetStartIndex..<nextMarkerRange.lowerBound]
                packets.append(packetData)
                currentIndex = nextMarkerRange.lowerBound
            } else {
                // No more markers, this is the last packet
                let packetData = data[packetStartIndex..<data.count]
                if !packetData.isEmpty {
                    packets.append(packetData)
                }
                break
            }
        }
        
        return packets
    }
}

