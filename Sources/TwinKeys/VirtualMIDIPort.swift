#if os(macOS)
import CoreMIDI
import Foundation
import TwinKeysCore

enum MIDIPortError: Error, CustomStringConvertible {
    case client(OSStatus), source(OSStatus)
    var description: String {
        switch self {
        case let .client(s): return "MIDIClientCreate failed (\(s))"
        case let .source(s): return "MIDISourceCreate failed (\(s))"
        }
    }
}

/// A virtual MIDI source named "TwinKeys". Music software sees it as a MIDI input device.
final class VirtualMIDIPort: MIDIOutput {
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()

    init(name: String, uniqueID: Int32?) throws {
        var status = MIDIClientCreateWithBlock(name as CFString, &client, nil)
        guard status == noErr else { throw MIDIPortError.client(status) }
        status = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        guard status == noErr else { throw MIDIPortError.source(status) }
        // Keep the same unique ID across launches so software remembers the port's settings.
        if let id = uniqueID {
            _ = MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, id)
        }
        _ = MIDIObjectSetStringProperty(source, kMIDIPropertyManufacturer, "TwinKeys" as CFString)
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    var uniqueID: Int32 {
        var v: Int32 = 0
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &v)
        return v
    }

    /// Sends one MIDI 1.0 channel voice message as a Universal MIDI Packet. Thread-safe.
    func send(_ bytes: [UInt8]) {
        guard bytes.count == 3 else { return }
        var word: UInt32 = 0x2000_0000 | (UInt32(bytes[0]) << 16) | (UInt32(bytes[1]) << 8) | UInt32(bytes[2])
        var list = MIDIEventList()
        withUnsafeMutablePointer(to: &list) { listPtr in
            let packet = MIDIEventListInit(listPtr, ._1_0)
            _ = MIDIEventListAdd(listPtr, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
            _ = MIDIReceivedEventList(source, listPtr)
        }
    }
}
#endif
