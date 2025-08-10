import Foundation

// Simple parser for FTMS Control Point responses (0x2AD9)
struct FTMSControlPointParser {
    struct Opcodes {
        static let responseCode: UInt8 = 0x80
        static let requestControl: UInt8 = 0x00
        static let resetMachine: UInt8 = 0x01
        static let setTargetResistanceLevel: UInt8 = 0x04
        static let setTargetPower: UInt8 = 0x05
        static let startOrResume: UInt8 = 0x07
        static let stopOrPause: UInt8 = 0x08
    }
    struct Result {
        static let success: UInt8 = 0x01
        static let unsupportedOpcode: UInt8 = 0x02
        static let invalidParameter: UInt8 = 0x03
        static let operationFailed: UInt8 = 0x04
        static let controlNotPermitted: UInt8 = 0x05
    }

    func parse(_ data: Data) -> [String: Any]? {
        guard data.count >= 3 else { return nil }
        let resp = data[0]
        let requestOp = data[1]
        let result = data[2]
        guard resp == Opcodes.responseCode else { return nil }
        let dict: [String: Any] = [
            "requestOpcode": requestOp,
            "resultCode": result,
            "success": result == Result.success,
            "opcodeDescription": opcodeDescription(requestOp),
            "resultDescription": resultDescription(result)
        ]
        // Optional payloads (e.g., target values) can be appended here if needed
        return dict
    }

    private func opcodeDescription(_ op: UInt8) -> String {
        switch op {
        case Opcodes.requestControl: return "Request Control"
        case Opcodes.resetMachine: return "Reset Machine"
        case Opcodes.setTargetResistanceLevel: return "Set Target Resistance"
        case Opcodes.setTargetPower: return "Set Target Power"
        case Opcodes.startOrResume: return "Start/Resume"
        case Opcodes.stopOrPause: return "Stop/Pause"
        default: return "Unknown (0x\(String(format: "%02X", op)))"
        }
    }
    private func resultDescription(_ r: UInt8) -> String {
        switch r {
        case Result.success: return "Success"
        case Result.unsupportedOpcode: return "Unsupported Opcode"
        case Result.invalidParameter: return "Invalid Parameter"
        case Result.operationFailed: return "Operation Failed"
        case Result.controlNotPermitted: return "Control Not Permitted"
        default: return "Unknown (0x\(String(format: "%02X", r)))"
        }
    }
}

