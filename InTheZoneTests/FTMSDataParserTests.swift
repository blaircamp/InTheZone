import XCTest
@testable import InTheZone

final class FTMSDataParserTests: XCTestCase {
    
    var parser: FTMSDataParser!
    
    override func setUpWithError() throws {
        parser = FTMSDataParser()
    }
    
    override func tearDownWithError() throws {
        parser = nil
    }
    
    // MARK: - Real Victory Trainer Data Tests
    
    func testVictoryTrainerIdleData() throws {
        // From logs: 📦 Received Indoor Bike Data data (11 bytes): 64 02 00 00 00 00 00 00 00 00 00
        // This is trainer at idle - all zeros except flags
        let data = Data([0x64, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle idle data")
        
        // Flags: 0x0264 = 0000 0010 0110 0100
        // Bit 0 (speed): 0 -> Speed present (inverted logic)
        // Bit 2 (cadence): 1 -> Cadence present (normal logic) 
        // Bit 5 (resistance): 1 -> Resistance present
        // Bit 6 (power): 1 -> Power present
        
        XCTAssertEqual(result?.speed, 0.0, "Speed should be 0.0 km/h")
        XCTAssertEqual(result?.cadence, 0.0, "Cadence should be 0.0 RPM") 
        XCTAssertEqual(result?.resistance, 0, "Resistance should be 0")
        XCTAssertEqual(result?.power, 0, "Power should be 0W")
    }
    
    func testVictoryTrainerActiveDataLowIntensity() throws {
        // Very simple test with just speed
        let data = Data([0x00, 0x00, 0x16, 0x03])  // flags=0x0000 (speed present via inverted logic), speed=0x0316
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle speed-only data")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        if let speed = result?.speed {
            XCTAssertEqual(speed, 7.90, accuracy: 0.01, "Speed should be 7.90 km/h")
        }
    }
    
    func testVictoryTrainerActiveDataHighIntensity() throws {
        // Test with speed + cadence: flags=0x0004 (cadence present), speed via inverted logic
        let data = Data([0x04, 0x00, 0xda, 0x03, 0x2a, 0x00])  // speed=0x03da, cadence=0x002a
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle speed+cadence data")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        XCTAssertNotNil(result?.cadence, "Cadence should be parsed")
        
        if let speed = result?.speed {
            XCTAssertEqual(speed, 9.86, accuracy: 0.01, "Speed should be 9.86 km/h")
        }
        if let cadence = result?.cadence {
            XCTAssertEqual(cadence, 21.0, accuracy: 0.1, "Cadence should be 21.0 RPM")
        }
    }
    
    func testVictoryTrainerPeakPowerData() throws {
        // Test with speed + power: flags=0x0040 (power present), speed via inverted logic
        let data = Data([0x40, 0x00, 0xcc, 0x06, 0x4f, 0x00])  // speed=0x06cc, power=0x004f
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle speed+power data")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        XCTAssertNotNil(result?.power, "Power should be parsed")
        
        if let speed = result?.speed {
            XCTAssertEqual(speed, 17.40, accuracy: 0.01, "Speed should be 17.40 km/h")
        }
        if let power = result?.power {
            XCTAssertEqual(power, 79, "Power should be 79W")
        }
    }
    
    func testVictoryTrainerCoastingDown() throws {
        // Test with speed + resistance: flags=0x0020 (resistance present), speed via inverted logic
        let data = Data([0x20, 0x00, 0x22, 0x04, 0x02, 0x00])  // speed=0x0422, resistance=0x0002
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle speed+resistance data")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        XCTAssertNotNil(result?.resistance, "Resistance should be parsed")
        
        if let speed = result?.speed {
            XCTAssertEqual(speed, 10.58, accuracy: 0.01, "Speed should be 10.58 km/h")
        }
        if let resistance = result?.resistance {
            XCTAssertEqual(resistance, 2, "Resistance should be 2")
        }
    }
    
    func testComplexFTMSData() throws {
        // Test with speed + cadence + power + resistance
        // flags=0x0064 (cadence=bit2 + resistance=bit5 + power=bit6), speed via inverted logic
        let data = Data([0x64, 0x00, 0x16, 0x03, 0x0e, 0x00, 0x02, 0x00, 0x1d, 0x00])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle complex multi-field data")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        XCTAssertNotNil(result?.cadence, "Cadence should be parsed")
        XCTAssertNotNil(result?.resistance, "Resistance should be parsed")
        XCTAssertNotNil(result?.power, "Power should be parsed")
        
        if let speed = result?.speed {
            XCTAssertEqual(speed, 7.90, accuracy: 0.01, "Speed should be 7.90 km/h")
        }
        if let cadence = result?.cadence {
            XCTAssertEqual(cadence, 7.0, accuracy: 0.1, "Cadence should be 7.0 RPM")
        }
        if let resistance = result?.resistance {
            XCTAssertEqual(resistance, 2, "Resistance should be 2")
        }
        if let power = result?.power {
            XCTAssertEqual(power, 29, "Power should be 29W")
        }
    }
    
    func testOriginalVictoryTrainerData() throws {
        // Test with the original complex data from logs that caused alignment issues
        // This data has many fields including 3-byte distance causing unaligned resistance at offset 13
        let data = Data([0xfe, 0x02, 0x16, 0x03, 0x0e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Parser should handle original complex Victory trainer data without crashing")
        
        // With the original complex flags (0x02fe), we should at least get speed parsing
        XCTAssertNotNil(result?.speed, "Speed should be parsed from original data")
        
        if let speed = result?.speed {
            XCTAssertEqual(speed, 7.90, accuracy: 0.01, "Speed should be 7.90 km/h from original data")
        }
        
        // The key test is that this doesn't crash due to alignment issues
        // Other fields may or may not be present depending on complex flag parsing
    }

    // MARK: - Resistance Range Tests
    
    func testVictoryResistanceRange() throws {
        // From logs: 📦 Received Resistance Range data (6 bytes): 00 00 64 00 01 00
        let data = Data([0x00, 0x00, 0x64, 0x00, 0x01, 0x00])
        
        let result = parser.parseResistanceRange(data)
        
        XCTAssertNotNil(result, "Should parse resistance range")
        XCTAssertEqual(result?.min, 0, "Min resistance should be 0")
        XCTAssertEqual(result?.max, 100, "Max resistance should be 100") 
        XCTAssertEqual(result?.increment, 1, "Increment should be 1")
    }
    
    // MARK: - Edge Cases
    
    func testInsufficientData() throws {
        let data = Data([0x64]) // Only 1 byte
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNil(result, "Should return nil for insufficient data")
    }
    
    func testEmptyData() throws {
        let data = Data()
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNil(result, "Should return nil for empty data")
    }
    
    // MARK: - Flag Logic Tests
    
    func testFlagBitInterpretation() throws {
        // Test flags: 0x02fe = 0000 0010 1111 1110
        let data = Data([0xfe, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse data with full flags")
        
        // With flags 0x02fe:
        // Bit 0 = 0: Speed present (inverted logic)
        // Bit 2 = 1: Cadence present (normal logic)
        // Bit 5 = 1: Resistance present 
        // Bit 6 = 1: Power present
        // Bit 9 = 1: Heart rate present
        
        // All values should be 0 since data is all zeros
        XCTAssertEqual(result!.speed!, 0.0, "Speed should be 0")
        XCTAssertEqual(result!.cadence!, 0.0, "Cadence should be 0")  
        XCTAssertEqual(result!.resistance!, 0, "Resistance should be 0")
        XCTAssertEqual(result!.power!, 0, "Power should be 0")
    }
    
    // MARK: - Performance Tests
    
    func testParsingPerformance() throws {
        let data = Data([0xfe, 0x02, 0xcc, 0x06, 0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x02, 0x00, 0x4f, 0x00, 0x04, 0x00, 0x00])
        
        measure {
            for _ in 0..<1000 {
                _ = parser.parseIndoorBikeData(data)
            }
        }
    }
    
    // MARK: - Validation Tests
    
    func testSpeedValidation() throws {
        // Test with unreasonably high speed value
        var data = Data([0x64, 0x02, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should still parse even with high speed")
        // Speed: 0xFFFF = 65535 * 0.01 = 655.35 km/h
        // Should be clamped to maxSpeed (80 km/h)
        XCTAssertEqual(result!.speed!, 80.0, "Speed should be clamped to maximum")
    }
    
    func testCadenceValidation() throws {
        // Test with unreasonably high cadence
        // flags=0x0004 (only cadence present), speed via inverted logic, cadence=0xFFFF
        let data = Data([0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should still parse even with high cadence")
        XCTAssertNotNil(result?.cadence, "Cadence should be parsed")
        
        // Cadence: 0xFFFF = 65535 * 0.5 = 32767.5 RPM  
        // Should be clamped to maxCadence (220 RPM)
        if let cadence = result?.cadence {
            XCTAssertEqual(cadence, 220.0, "Cadence should be clamped to maximum")
        }
    }
    
    func testPowerValidation() throws {
        // Test with unreasonably high power value
        // flags=0x0040 (only power present), speed via inverted logic, power=0x7FFF (max positive Int16)
        let data = Data([0x40, 0x00, 0x00, 0x00, 0xFF, 0x7F])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should still parse even with high power")
        XCTAssertNotNil(result?.power, "Power should be parsed")
        
        // Power: 0x7FFF = 32767W should be clamped to maxPower (2000W)
        if let power = result?.power {
            XCTAssertEqual(power, 2000, "Power should be clamped to maximum")
        }
    }
    
    func testNegativePowerHandling() throws {
        // Test with negative power value (should be clamped to 0)
        // flags=0x0040 (only power present), speed via inverted logic, power=0x8000 (negative Int16)
        let data = Data([0x40, 0x00, 0x00, 0x00, 0x00, 0x80])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should still parse even with negative power")
        XCTAssertNotNil(result?.power, "Power should be parsed")
        
        // Negative power should be clamped to 0
        if let power = result?.power {
            XCTAssertEqual(power, 0, "Negative power should be clamped to 0")
        }
    }
    
    // MARK: - Individual Flag Tests
    
    func testSpeedOnlyParsing() throws {
        // Test speed-only parsing (inverted logic)
        let data = Data([0x00, 0x00, 0x88, 0x13]) // flags=0x0000, speed=0x1388=5000*0.01=50.0 km/h
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse speed-only data")
        XCTAssertNotNil(result?.speed, "Speed should be present")
        XCTAssertNil(result?.cadence, "Cadence should not be present")
        XCTAssertNil(result?.power, "Power should not be present")
        XCTAssertNil(result?.resistance, "Resistance should not be present")
        
        XCTAssertEqual(result!.speed!, 50.0, accuracy: 0.01, "Speed should be 50.0 km/h")
    }
    
    func testCadenceOnlyParsing() throws {
        // Test cadence-only parsing (normal logic, no speed)
        let data = Data([0x05, 0x00, 0x64, 0x00]) // flags=0x0005 (speed bit set=no speed, cadence bit set), cadence=0x0064=100*0.5=50.0 RPM
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse cadence-only data")
        XCTAssertNil(result?.speed, "Speed should not be present (bit 0 set)")
        XCTAssertNotNil(result?.cadence, "Cadence should be present")
        XCTAssertNil(result?.power, "Power should not be present")
        XCTAssertNil(result?.resistance, "Resistance should not be present")
        
        XCTAssertEqual(result!.cadence!, 50.0, accuracy: 0.01, "Cadence should be 50.0 RPM")
    }
    
    func testPowerOnlyParsing() throws {
        // Test power-only parsing (normal logic, no speed)
        let data = Data([0x41, 0x00, 0xF4, 0x01]) // flags=0x0041 (speed bit set=no speed, power bit set), power=0x01F4=500W
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse power-only data")
        XCTAssertNil(result?.speed, "Speed should not be present")
        XCTAssertNil(result?.cadence, "Cadence should not be present")
        XCTAssertNotNil(result?.power, "Power should be present")
        XCTAssertNil(result?.resistance, "Resistance should not be present")
        
        XCTAssertEqual(result!.power!, 500, "Power should be 500W")
    }
    
    func testResistanceOnlyParsing() throws {
        // Test resistance-only parsing (normal logic, no speed)
        let data = Data([0x21, 0x00, 0x0A, 0x00]) // flags=0x0021 (speed bit set=no speed, resistance bit set), resistance=0x000A=10
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse resistance-only data")
        XCTAssertNil(result?.speed, "Speed should not be present")
        XCTAssertNil(result?.cadence, "Cadence should not be present")
        XCTAssertNil(result?.power, "Power should not be present")
        XCTAssertNotNil(result?.resistance, "Resistance should be present")
        
        XCTAssertEqual(result!.resistance!, 10, "Resistance should be 10")
    }
    
    // MARK: - Heart Rate Tests
    
    func testHeartRateParsing() throws {
        // Test with heart rate field - flags=0x0200 (heart rate bit 9), no speed (bit 0 set)
        let data = Data([0x01, 0x02, 0x50]) // flags=0x0201, HR=0x50=80 bpm
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse heart rate data")
        XCTAssertNotNil(result?.heartRate, "Heart rate should be present")
        XCTAssertEqual(result!.heartRate!, 80, "Heart rate should be 80 bpm")
    }
    
    func testInvalidHeartRate() throws {
        // Test with invalid heart rate (too low)
        let data = Data([0x01, 0x02, 0x0A]) // flags=0x0201, HR=0x0A=10 bpm (invalid)
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should still parse with invalid heart rate")
        // Invalid heart rate should be filtered out
        XCTAssertNil(result?.heartRate, "Invalid heart rate should be filtered out")
    }
    
    // MARK: - Distance Field Tests
    
    func testDistanceFieldSkipping() throws {
        // Test that 3-byte distance field is properly skipped (this was causing alignment issues)
        // flags=0x0014 (distance bit 4, cadence bit 2), speed via inverted logic
        // Parser order: speed, cadence, distance (NOT speed, distance, cadence)
        let data = Data([0x14, 0x00, 0x32, 0x00, 0x64, 0x00, 0x01, 0x02, 0x03]) // speed, cadence, distance(3 bytes)
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should handle distance field correctly")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        XCTAssertNotNil(result?.cadence, "Cadence should be parsed before distance")
        
        XCTAssertEqual(result!.speed!, 0.50, accuracy: 0.01, "Speed should be 0.50 km/h")
        XCTAssertEqual(result!.cadence!, 50.0, accuracy: 0.1, "Cadence should be 50.0 RPM")
    }
    
    // MARK: - Average Field Tests
    
    func testAverageFieldsSkipping() throws {
        // Test that average speed and cadence fields are properly skipped
        // flags=0x000A (avg speed bit 1, avg cadence bit 3), speed via inverted logic
        let data = Data([0x0A, 0x00, 0x32, 0x00, 0x64, 0x00, 0x96, 0x00]) // speed, avg_speed, avg_cadence
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should handle average fields correctly")
        XCTAssertNotNil(result?.speed, "Speed should be parsed")
        // Average fields should be skipped, not stored in result
        
        XCTAssertEqual(result!.speed!, 0.50, accuracy: 0.01, "Speed should be 0.50 km/h")
    }
    
    // MARK: - Data Boundary Tests
    
    func testDataTooShortForFlags() throws {
        // Test data that's long enough for flags but too short for expected fields
        let data = Data([0x40, 0x00, 0x00]) // flags=0x0040 (power expected) but only 1 byte after flags
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNil(result, "Should return nil when data too short for expected fields")
    }
    
    func testDataExactLength() throws {
        // Test data that's exactly the right length
        let data = Data([0x40, 0x00, 0x00, 0x00, 0xC8, 0x00]) // flags=0x0040, speed=0, power=200W
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse data of exact length")
        XCTAssertEqual(result!.speed!, 0.0, accuracy: 0.01, "Speed should be 0.0 km/h")
        XCTAssertEqual(result!.power!, 200, "Power should be 200W")
    }
    
    // MARK: - Resistance Range Edge Cases
    
    func testResistanceRangeInsufficientData() throws {
        let data = Data([0x00, 0x00, 0x64]) // Only 3 bytes instead of 6
        
        let result = parser.parseResistanceRange(data)
        
        XCTAssertNil(result, "Should return nil for insufficient resistance range data")
    }
    
    func testResistanceRangeNegativeValues() throws {
        // Test with negative min resistance
        let data = Data([0xFF, 0xFF, 0x64, 0x00, 0x01, 0x00]) // min=-1, max=100, inc=1
        
        let result = parser.parseResistanceRange(data)
        
        XCTAssertNotNil(result, "Should parse negative resistance range")
        XCTAssertEqual(result!.min, -1, "Min resistance should be -1")
        XCTAssertEqual(result!.max, 100, "Max resistance should be 100")
        XCTAssertEqual(result!.increment, 1, "Increment should be 1")
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentParsing() throws {
        let data = Data([0x64, 0x00, 0x16, 0x03, 0x0e, 0x00, 0x02, 0x00, 0x1d, 0x00])
        let expectation = self.expectation(description: "Concurrent parsing")
        expectation.expectedFulfillmentCount = 10
        
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let parser = FTMSDataParser() // Create new parser for each thread
            let result = parser.parseIndoorBikeData(data)
            XCTAssertNotNil(result, "Concurrent parsing should work")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Memory Safety Tests
    
    func testLargeDataHandling() throws {
        // Test with very large data buffer
        var data = Data([0x00, 0x00, 0x16, 0x03]) // Basic speed data
        data.append(Data(repeating: 0, count: 1000)) // Add lots of extra data
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should handle large data buffers")
        XCTAssertEqual(result!.speed!, 7.90, accuracy: 0.01, "Should still parse speed correctly")
    }
    
    // MARK: - FTMS Specification Compliance Tests
    
    func testAllFlagsZero() throws {
        // Test the edge case where no fields are present (all flags = 0, including speed inverted logic)
        let data = Data([0x01, 0x00]) // flags=0x0001 (speed bit set = no speed, no other fields)
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should handle no-field data")
        XCTAssertNil(result?.speed, "Speed should not be present")
        XCTAssertNil(result?.cadence, "Cadence should not be present") 
        XCTAssertNil(result?.power, "Power should not be present")
        XCTAssertNil(result?.resistance, "Resistance should not be present")
    }
    
    func testTimestampPresence() throws {
        let data = Data([0x00, 0x00, 0x16, 0x03])
        
        let result = parser.parseIndoorBikeData(data)
        
        XCTAssertNotNil(result, "Should parse successfully")
        XCTAssertNotNil(result?.timestamp, "Timestamp should always be set")
        
        // Timestamp should be recent (within last second)
        let timeDiff = Date().timeIntervalSince(result!.timestamp)
        XCTAssertLessThan(timeDiff, 1.0, "Timestamp should be recent")
    }
}