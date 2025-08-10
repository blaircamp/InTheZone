import Foundation
import CoreBluetooth

// Parses FTMS Indoor Bike Data (0x2AD2) and Supported Resistance Range (0x2AD6)
struct FTMSDataParser {
    private struct Flags {
        static let instantaneousSpeed: UInt16 = 0x0001
        static let averageSpeed: UInt16 = 0x0002
        static let instantaneousCadence: UInt16 = 0x0004
        static let averageCadence: UInt16 = 0x0008
        static let totalDistance: UInt16 = 0x0010
        static let resistanceLevel: UInt16 = 0x0020
        static let instantaneousPower: UInt16 = 0x0040
        static let averagePower: UInt16 = 0x0080
        static let expendedEnergy: UInt16 = 0x0100
        static let heartRate: UInt16 = 0x0200
        static let metabolicEquivalent: UInt16 = 0x0400
        static let elapsedTime: UInt16 = 0x0800
        static let remainingTime: UInt16 = 0x1000
    }

    func parseIndoorBikeData(_ data: Data) -> TrainerData? {
        guard data.count >= 2 else { 
            print("FTMS Parser: Insufficient data length (\(data.count) bytes)")
            return nil 
        }
        
        var offset = 0
        let flags: UInt16 = data.readLEUInt16(at: &offset)
        var result = TrainerData()
        
        print("FTMS Parser: Processing data with flags 0x\(String(format: "%04x", flags))")
        return parseWithFlags(flags: flags, data: data, offset: &offset, result: &result)
    }
    
    private func parseWithFlags(flags: UInt16, data: Data, offset: inout Int, result: inout TrainerData) -> TrainerData? {
        
        // Parse fields based on flags

        // Parse speed (INVERTED LOGIC - present when bit 0 is NOT set)
        if (flags & Flags.instantaneousSpeed) == 0 {
            guard offset + 2 <= data.count else {
                print("FTMS Parser: Insufficient data for speed at offset \(offset)")
                return nil
            }
            let v: UInt16 = data.readLEUInt16(at: &offset)
            let speedKmh = Double(v) * 0.01
            result.speed = min(speedKmh, TrainingConstants.Validation.maxSpeed)
            print("FTMS Parser: Speed parsed: \(speedKmh) km/h")
        } else {
            print("FTMS Parser: Speed field not present (flag bit 0 = 1)")
        }

        // Parse average speed (NORMAL LOGIC - present when bit 1 IS set)
        if (flags & Flags.averageSpeed) != 0 {
            guard offset + 2 <= data.count else {
                return nil
            }
            let _: UInt16 = data.readLEUInt16(at: &offset)
        }

        // Parse cadence (NORMAL LOGIC - present when bit 2 IS set)
        if (flags & Flags.instantaneousCadence) != 0 {
            guard offset + 2 <= data.count else {
                print("FTMS Parser: Insufficient data for cadence at offset \(offset)")
                return nil
            }
            let v: UInt16 = data.readLEUInt16(at: &offset)
            let cadence = Double(v) * 0.5
            result.cadence = min(cadence, TrainingConstants.Validation.maxCadence)
            print("FTMS Parser: Cadence parsed: \(cadence) RPM")
        } else {
            print("FTMS Parser: Cadence field not present (flag bit 2 = 0)")
        }

        // Parse average cadence (NORMAL LOGIC - present when bit 3 IS set)
        if (flags & Flags.averageCadence) != 0 {
            guard offset + 2 <= data.count else {
                return nil
            }
            let _: UInt16 = data.readLEUInt16(at: &offset)
        }

        // Total distance (3 bytes) if present
        if (flags & Flags.totalDistance) != 0 { 
            offset += 3 
        }

        // Resistance level: 2 bytes signed
        if (flags & Flags.resistanceLevel) != 0 {
            guard offset + 2 <= data.count else {
                return nil
            }
            let v: Int16 = data.readLEInt16(at: &offset)
            let resistance = Int(v)
            result.resistance = resistance
        } else {
        }

        // Instantaneous power: 2 bytes signed
        if (flags & Flags.instantaneousPower) != 0 {
            guard offset + 2 <= data.count else {
                print("FTMS Parser: Insufficient data for power at offset \(offset)")
                return nil
            }
            let v: Int16 = data.readLEInt16(at: &offset)
            let power = max(0, min(Int(v), TrainingConstants.Validation.maxPower))
            result.power = power
            print("FTMS Parser: Power parsed: \(power) W")
        } else {
            print("FTMS Parser: Power field not present (flag bit 6 = 0)")
        }
        
        // Parse average power (NORMAL LOGIC - present when bit 7 IS set)
        if (flags & Flags.averagePower) != 0 {
            guard offset + 2 <= data.count else {
                return nil
            }
            let _: Int16 = data.readLEInt16(at: &offset)
        }

        // Expended energy (6 bytes) skip if present
        if (flags & Flags.expendedEnergy) != 0 { offset += 6 }

        // Heart rate (1 byte)
        if (flags & Flags.heartRate) != 0, offset < data.count {
            let hr = Int(data[offset]); offset += 1
            if HeartRateValidator.isValid(Double(hr)) { result.heartRate = hr }
        }

        // Skip MET, elapsed, remaining if present
        if (flags & Flags.metabolicEquivalent) != 0 { offset += 1 }
        if (flags & Flags.elapsedTime) != 0 { offset += 2 }
        if (flags & Flags.remainingTime) != 0 { offset += 2 }

        result.timestamp = Date()
        
        print("FTMS Parser: Parse complete - Speed: \(result.speed?.description ?? "nil"), Cadence: \(result.cadence?.description ?? "nil"), Power: \(result.power?.description ?? "nil")")
        return result
    }

    func parseResistanceRange(_ data: Data) -> (min: Int, max: Int, increment: Int)? {
        guard data.count >= 6 else { 
            return nil 
        }
        
        var off = 0
        let minV: Int16 = data.readLEInt16(at: &off)
        let maxV: Int16 = data.readLEInt16(at: &off)
        let incV: UInt16 = data.readLEUInt16(at: &off) // increment is always positive
        
        return (Int(minV), Int(maxV), Int(incV))
    }
}

private extension Data {
    func readLEUInt16(at offset: inout Int) -> UInt16 {
        let v: UInt16 = withUnsafeBytes { ptr in
            guard offset + 2 <= count else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: v)
    }
    func readLEInt16(at offset: inout Int) -> Int16 {
        let v: Int16 = withUnsafeBytes { ptr in
            guard offset + 2 <= count else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: offset, as: Int16.self)
        }
        offset += 2
        return Int16(littleEndian: v)
    }
    func readLE<T>(at offset: inout Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= count else { return nil }
        let value: T = withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset += size
        if T.self == UInt16.self {
            return UInt16(littleEndian: value as! UInt16) as? T
        }
        if T.self == Int16.self {
            return Int16(littleEndian: value as! Int16) as? T
        }
        return value
    }
}

