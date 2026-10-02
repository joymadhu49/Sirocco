// Talks to the AppleSMC user client. Reading works for any user; writing fan keys needs root,
// which is why only fanlined writes.
//
// The kernel expects the 80 byte SMCKeyData_t struct from Apple's old smc.h. Swift gives no
// layout guarantee for a mirrored struct, so the bytes are packed by hand at the offsets clang
// reports for the C definition: key 0, keyInfo.dataSize 28, keyInfo.dataType 32, result 40,
// data8 42, data32 44, bytes 48.
import Foundation
import IOKit

final class SMC {
    private var connection: io_connect_t = 0

    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let command = 42
        static let index = 44
        static let bytes = 48
        static let total = 80
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case keyAtIndex = 8
        case keyInfo = 9
    }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: Raw access

    private static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var inBuffer = input
        var outBuffer = [UInt8](repeating: 0, count: Offset.total)
        var outSize = Offset.total
        let status = IOConnectCallStructMethod(connection, 2, &inBuffer, Offset.total, &outBuffer, &outSize)
        guard status == KERN_SUCCESS, outBuffer[Offset.result] == 0 else { return nil }
        return outBuffer
    }

    private func request(_ key: String, _ command: Command) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: Offset.total)
        buffer.put(SMC.code(key), at: Offset.key)
        buffer[Offset.command] = command.rawValue
        return buffer
    }

    private func info(_ key: String) -> (size: UInt32, type: UInt32)? {
        guard let out = call(request(key, .keyInfo)) else { return nil }
        return (out.uint32(at: Offset.dataSize), out.uint32(at: Offset.dataType))
    }

    func read(_ key: String) -> [UInt8]? {
        guard let info = info(key) else { return nil }
        var buffer = request(key, .readBytes)
        buffer.put(info.size, at: Offset.dataSize)
        guard let out = call(buffer) else { return nil }
        return Array(out[Offset.bytes ..< Offset.bytes + Int(min(info.size, 32))])
    }

    @discardableResult
    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let info = info(key), Int(info.size) == bytes.count else { return false }
        var buffer = request(key, .writeBytes)
        buffer.put(info.size, at: Offset.dataSize)
        buffer.replaceSubrange(Offset.bytes ..< Offset.bytes + bytes.count, with: bytes)
        return call(buffer) != nil
    }

    // MARK: Typed values

    func float(_ key: String) -> Double? {
        guard let bytes = read(key), bytes.count == 4 else { return nil }
        return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
    }

    func uint8(_ key: String) -> Int? {
        guard let bytes = read(key), let first = bytes.first else { return nil }
        return Int(first)
    }

    @discardableResult
    func setFloat(_ key: String, _ value: Double) -> Bool {
        var f = Float32(value)
        return write(key, withUnsafeBytes(of: &f) { Array($0) })
    }

    @discardableResult
    func setUInt8(_ key: String, _ value: UInt8) -> Bool {
        write(key, [value])
    }

    // MARK: Fans

    struct Fan: Codable, Equatable {
        var actual: Double
        var target: Double
        var min: Double
        var max: Double
        var manual: Bool
    }

    var fanCount: Int { uint8("FNum") ?? 0 }

    func fans() -> [Fan] {
        (0 ..< fanCount).map { i in
            Fan(actual: float("F\(i)Ac") ?? 0,
                target: float("F\(i)Tg") ?? 0,
                min: float("F\(i)Mn") ?? 0,
                max: float("F\(i)Mx") ?? 0,
                manual: uint8("F\(i)Md") == 1)
        }
    }

    /// Puts every fan in manual mode at `rpm`. Root only.
    ///
    /// On Apple Silicon the fans belong to thermalmonitord. Writing Ftst=1 asks it to let go,
    /// which takes a few seconds, so the mode write is retried until it reads back as manual.
    @discardableResult
    func setManual(rpm: Double) -> Bool {
        let count = fanCount
        guard count > 0 else { return false }
        if uint8("Ftst") != 1 { setUInt8("Ftst", 1) }
        for i in 0 ..< count {
            let modeKey = "F\(i)Md"
            var manual = uint8(modeKey) == 1
            var tries = 0
            while !manual && tries < 40 {
                setUInt8(modeKey, 1)
                manual = uint8(modeKey) == 1
                if !manual { usleep(250_000) }
                tries += 1
            }
            guard manual else { return false }
            let low = float("F\(i)Mn") ?? 0
            let high = float("F\(i)Mx") ?? rpm
            guard setFloat("F\(i)Tg", Swift.min(Swift.max(rpm, low), high)) else { return false }
        }
        return true
    }

    /// Hands every fan back to macOS. Root only.
    func releaseToSystem() {
        for i in 0 ..< fanCount { setUInt8("F\(i)Md", 0) }
        setUInt8("Ftst", 0)
    }

    // MARK: Key scan (fallback temperatures)

    func keys(withPrefixes prefixes: [String]) -> [String] {
        guard let countBytes = read("#KEY"), countBytes.count >= 4 else { return [] }
        let count = countBytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var found: [String] = []
        for index in 0 ..< count {
            var buffer = [UInt8](repeating: 0, count: Offset.total)
            buffer[Offset.command] = Command.keyAtIndex.rawValue
            buffer.put(index, at: Offset.index)
            guard let out = call(buffer) else { continue }
            let raw = out.uint32(at: Offset.key)
            let name = String(bytes: [24, 16, 8, 0].map { UInt8((raw >> $0) & 0xff) }, encoding: .ascii) ?? ""
            if prefixes.contains(where: name.hasPrefix) { found.append(name) }
        }
        return found
    }
}

private extension Array where Element == UInt8 {
    mutating func put(_ value: UInt32, at offset: Int) {
        Swift.withUnsafeBytes(of: value) { raw in
            for (i, byte) in raw.enumerated() { self[offset + i] = byte }
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        self[offset ..< offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
}
