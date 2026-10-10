import CoreAudio
import Foundation
import Synchronization

// MARK: - Audio thread

/// One input strip's share of the IOProc state.
/// Atomics carry parameters in and meter data out. The plain fields are written once before start, or by the IOProc only.
nonisolated struct StripSlot: ~Copyable {
    let target = Atomic<UInt32>(0)      // linear gain (trim x fader x mute), Float bit pattern
    let peak = Atomic<UInt32>(0)        // post-gain peak (louder of L/R) since the UI last read it, Float bit pattern
    let inPeak = Atomic<UInt32>(0)      // raw input peak (before gain) since the UI last read it, Float bit pattern
    let clipped = Atomic<UInt32>(0)     // 1 when a sample went over full scale after this strip's gain

    // Written by the IOProc only.
    var current: Float = 0              // gain now, ramping toward `target`
    var lastTarget: Float = 0           // the target `step` was computed for
    var step: Float = 0                 // gain change per sample

    // Written before start only.
    var valid = false                   // false: the buffer check failed, skip this strip
    var lBuf = 0, lOff = 0, lStride = 1 // where this device's left sample sits in the input buffer list
    var rBuf = 0, rOff = 0, rStride = 1
}

/// Everything the IOProc touches. Heap-allocated on the main thread before `AudioDeviceStart`,
/// freed only after `AudioDeviceStop` + `AudioDeviceDestroyIOProcID`.
nonisolated struct EngineState: ~Copyable {
    var slots: UnsafeMutablePointer<StripSlot>
    var slotCount = 0                   // written before start
    var inputBuffers = 0                // aggregate input buffers the layout needs
    var rampSamples: Float = 1          // 15 ms at the aggregate's rate

    init(slots: UnsafeMutablePointer<StripSlot>) { self.slots = slots }
}

/// The IOProc. Real-time: no allocation, locks, logging, ARC or Swift collections.
nonisolated func mixerIOProc(_ device: AudioObjectID,
                             _ now: UnsafePointer<AudioTimeStamp>,
                             _ inData: UnsafePointer<AudioBufferList>,
                             _ inTime: UnsafePointer<AudioTimeStamp>,
                             _ outData: UnsafeMutablePointer<AudioBufferList>,
                             _ outTime: UnsafePointer<AudioTimeStamp>,
                             _ client: UnsafeMutableRawPointer?) -> OSStatus {
    guard let client else { return noErr }
    let s = client.assumingMemoryBound(to: EngineState.self)
    let outs = UnsafeMutableAudioBufferListPointer(outData)

    // Silence every output buffer first; then add each strip over it.
    for i in 0..<outs.count {
        if let d = outs[i].mData { memset(d, 0, Int(outs[i].mDataByteSize)) }
    }
    guard outs.count > 0 else { return noErr }
    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard ins.count >= s.pointee.inputBuffers else { return noErr }

    // Output: left on the first channel; right on the second channel, or on the next buffer if the first is mono.
    let out0 = outs[0]
    let c0 = Int(out0.mNumberChannels)
    guard c0 > 0, let o0 = out0.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    var outFrames = Int(out0.mDataByteSize) / (4 * c0)
    let lDst = o0, lDstStride = c0
    var rDst: UnsafeMutablePointer<Float>? = nil
    var rDstStride = 1, rDstOff = 0
    if c0 >= 2 {
        rDst = o0; rDstStride = c0; rDstOff = 1
    } else if outs.count > 1, outs[1].mNumberChannels > 0,
              let o1 = outs[1].mData?.assumingMemoryBound(to: Float.self) {
        rDst = o1; rDstStride = Int(outs[1].mNumberChannels)
        outFrames = min(outFrames, Int(outs[1].mDataByteSize) / (4 * rDstStride))
    }

    let rampSamples = s.pointee.rampSamples
    for i in 0..<s.pointee.slotCount {
        let slot = s.pointee.slots + i
        guard slot.pointee.valid else { continue }
        let inL = ins[slot.pointee.lBuf], inR = ins[slot.pointee.rBuf]
        let lStride = slot.pointee.lStride, rStride = slot.pointee.rStride
        guard Int(inL.mNumberChannels) == lStride, Int(inR.mNumberChannels) == rStride,
              let lSrc = inL.mData?.assumingMemoryBound(to: Float.self),
              let rSrc = inR.mData?.assumingMemoryBound(to: Float.self) else { continue }
        // Two-argument min only: the three-argument form is variadic and builds an array.
        let frames = min(min(outFrames, Int(inL.mDataByteSize) / (4 * lStride)), Int(inR.mDataByteSize) / (4 * rStride))
        let lOff = slot.pointee.lOff, rOff = slot.pointee.rOff

        let target = Float(bitPattern: slot.pointee.target.load(ordering: .relaxed))
        var gain = slot.pointee.current
        if target != slot.pointee.lastTarget {
            slot.pointee.step = Gain.rampStep(from: gain, to: target, rampSamples: rampSamples)
            slot.pointee.lastTarget = target
        }
        let step = slot.pointee.step
        var peak: Float = 0, peakIn: Float = 0
        var over = false

        for f in 0..<frames {
            if gain < target { gain = min(gain + step, target) } else if gain > target { gain = max(gain - step, target) }
            let rawL = lSrc[f * lStride + lOff], rawR = rSrc[f * rStride + rOff]
            peakIn = max(peakIn, max(abs(rawL), abs(rawR)))
            let l = rawL * gain
            let r = rawR * gain
            let m = max(abs(l), abs(r))
            if m > 1 { over = true }
            peak = max(peak, m)
            lDst[f * lDstStride] += l
            if let rDst { rDst[f * rDstStride + rDstOff] += r }
        }
        slot.pointee.current = gain
        // Positive Float bit patterns sort like the floats, so compare them as integers.
        if peak.bitPattern > slot.pointee.peak.load(ordering: .relaxed) { slot.pointee.peak.store(peak.bitPattern, ordering: .relaxed) }
        if peakIn.bitPattern > slot.pointee.inPeak.load(ordering: .relaxed) { slot.pointee.inPeak.store(peakIn.bitPattern, ordering: .relaxed) }
        if over { slot.pointee.clipped.store(1, ordering: .relaxed) }
    }

    // Hard clip the sum (the master clip light is P4).
    for f in 0..<outFrames {
        lDst[f * lDstStride] = min(max(lDst[f * lDstStride], -1), 1)
        if let rDst { rDst[f * rDstStride + rDstOff] = min(max(rDst[f * rDstStride + rDstOff], -1), 1) }
    }
    return noErr
}

// MARK: - Main thread

/// One device in the engine key: its UID plus its numeric ID, which changes when a USB hub resets (spec R2).
struct EngineDevice: Equatable {
    let uid: String
    let id: AudioObjectID
}

/// A process tap in the engine key. The tap object outlives aggregate rebuilds; the aggregate only references its UID.
struct EngineTap: Equatable {
    let uid: String
    let drift: Bool     // drift compensation on (off for Bluetooth outputs, which crackle with it)
}

/// What the running aggregate was built from. Rebuild only when it changes.
struct EngineKey: Equatable {
    let output: EngineDevice
    let members: [EngineDevice]
    var taps: [EngineTap] = []      // app taps; each fills one slot after the members
}

/// Owns the private aggregate device and its IOProc (spec D2). Main thread only.
final class Engine {
    private var aggregate = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?
    private var state: UnsafeMutablePointer<EngineState>?
    private var slotCount = 0
    /// Name prefixes of the objects this app creates; launch cleanup finds leftovers by them (spec 7.13).
    static let namePrefix = "Turntable Mixer engine"
    static let tapNamePrefix = "Turntable Mixer tap"
    /// Member UIDs in slot order for the running aggregate.
    private(set) var runningUIDs: [String] = []

    /// Most strips the engine mixes (slots are allocated once).
    static let maxStrips = 16
    private static let bufferFrames: UInt32 = 256

    /// Builds the aggregate for the output plus the members and taps and starts it. `targets[i]` is slot i's starting gain
    /// (members first, then taps). Returns an error message, or nil on success. Members plus taps are capped at `maxStrips`.
    func start(key: EngineKey, targets: [Float]) -> String? {
        stop()
        let members = Array(key.members.prefix(Self.maxStrips))
        let taps = Array(key.taps.prefix(Self.maxStrips - members.count))
        guard !members.isEmpty || !taps.isEmpty else { return nil }

        // Never hog mode (D6): nothing here sets kAudioDevicePropertyHogMode.
        // A member that is also the output device is not listed twice.
        let extra = members.filter { $0.uid != key.output.uid }
        var subDevices: [[String: Any]] = [[kAudioSubDeviceUIDKey: key.output.uid, kAudioSubDeviceDriftCompensationKey: 0]]
        for m in extra {
            subDevices.append([kAudioSubDeviceUIDKey: m.uid, kAudioSubDeviceDriftCompensationKey: 1,
                               kAudioSubDeviceDriftCompensationQualityKey: kAudioAggregateDriftCompensationMediumQuality])
        }
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.namePrefix,
            kAudioAggregateDeviceUIDKey: "io.github.qaid.turntablemixer.engine." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: key.output.uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
        ]
        // No kAudioAggregateDeviceTapAutoStartKey: the tap starts with the aggregate.
        if !taps.isEmpty {
            description[kAudioAggregateDeviceTapListKey] = taps.map {
                [kAudioSubTapUIDKey: $0.uid, kAudioSubTapDriftCompensationKey: $0.drift ? 1 : 0]
            }
        }
        var agg = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &agg) == noErr else {
            return "Could not create the audio engine."
        }
        aggregate = agg

        setBufferSize(agg)
        guard let layout = Self.layout(aggregate: agg, output: key.output, members: members, tapCount: taps.count) else {
            destroy()
            return "Could not read the input channels."
        }

        let rate = Audio.value(agg, kAudioDevicePropertyNominalSampleRate, Float64(48000))
        let slots = UnsafeMutablePointer<StripSlot>.allocate(capacity: Self.maxStrips)
        for i in 0..<Self.maxStrips { (slots + i).initialize(to: StripSlot()) }
        for (i, l) in layout.slots.enumerated() {
            let slot = slots + i
            if let l {
                slot.pointee.valid = true
                slot.pointee.lBuf = l.l.buf; slot.pointee.lOff = l.l.off; slot.pointee.lStride = l.l.stride
                slot.pointee.rBuf = l.r.buf; slot.pointee.rOff = l.r.off; slot.pointee.rStride = l.r.stride
            }
            if i < targets.count { slot.pointee.target.store(targets[i].bitPattern, ordering: .relaxed) }
        }
        let p = UnsafeMutablePointer<EngineState>.allocate(capacity: 1)
        p.initialize(to: EngineState(slots: slots))
        p.pointee.slotCount = members.count + taps.count
        p.pointee.inputBuffers = layout.inputBuffers
        p.pointee.rampSamples = max(Gain.rampSeconds * Float(rate), 1)
        state = p
        slotCount = members.count + taps.count
        runningUIDs = members.map(\.uid)

        var id: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcID(agg, mixerIOProc, p, &id) == noErr, let id else {
            destroy()
            return "Could not create the audio engine."
        }
        procID = id
        guard AudioDeviceStart(agg, id) == noErr else {
            destroy()
            return "Could not start the audio engine."
        }
        return nil
    }

    /// Stops and destroys the aggregate. Safe to call when not running.
    func stop() {
        destroy()
    }

    /// Sets member `slot`'s linear gain (trim x fader x mute). The IOProc ramps to it in 15 ms.
    func setTarget(slot: Int, _ linear: Float) {
        guard let s = state, slot >= 0, slot < slotCount else { return }
        (s.pointee.slots + slot).pointee.target.store(linear.bitPattern, ordering: .relaxed)
    }

    /// Per member, in slot order: post-gain peak and raw input peak since the last call (resets them), and whether the clip flag was set.
    func takePeaks() -> [(peak: Float, input: Float, clipped: Bool)] {
        guard let s = state else { return [] }
        return (0..<slotCount).map { i in
            let slot = s.pointee.slots + i
            return (Float(bitPattern: slot.pointee.peak.exchange(0, ordering: .relaxed)),
                    Float(bitPattern: slot.pointee.inPeak.exchange(0, ordering: .relaxed)),
                    slot.pointee.clipped.exchange(0, ordering: .relaxed) != 0)
        }
    }

    // The order matters: stop, destroy the IOProc, then free the state, then destroy the aggregate.
    private func destroy() {
        var procGone = true
        if let procID {
            AudioDeviceStop(aggregate, procID)
            procGone = AudioDeviceDestroyIOProcID(aggregate, procID) == noErr
        }
        procID = nil
        // ponytail: if the IOProc could still run, leak the state and slots (small) instead of freeing them under it.
        if let state, procGone {
            let slots = state.pointee.slots
            state.deinitialize(count: 1)
            state.deallocate()
            slots.deinitialize(count: Self.maxStrips)
            slots.deallocate()
        }
        state = nil
        slotCount = 0
        runningUIDs = []
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = 0
    }

    private func setBufferSize(_ agg: AudioObjectID) {
        var a = Audio.address(kAudioDevicePropertyBufferFrameSizeRange)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var frames = Self.bufferFrames
        if AudioObjectGetPropertyData(agg, &a, 0, nil, &size, &range) == noErr, range.mMaximum >= range.mMinimum {
            frames = min(max(frames, UInt32(range.mMinimum)), UInt32(range.mMaximum))
        }
        var b = Audio.address(kAudioDevicePropertyBufferFrameSize)
        AudioObjectSetPropertyData(agg, &b, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
    }

    typealias Pos = (buf: Int, off: Int, stride: Int)

    /// Finds each member's first two channels in the aggregate's input buffer list.
    /// Aggregate inputs = each sub-device's input streams, in sub-device order: the output first, then the members
    /// (a member that is the output has no second entry; its buffers start at 0), then one interleaved stereo buffer per tap
    /// (48 kHz, 2 channels, Float32; measured). A nil slot failed the check and is skipped.
    private static func layout(aggregate: AudioObjectID, output: EngineDevice, members: [EngineDevice], tapCount: Int)
        -> (slots: [(l: Pos, r: Pos)?], inputBuffers: Int)? {
        let outChannels = Audio.inputBufferChannels(output.id)
        var expected = outChannels
        var starts: [Int] = []
        var owns: [[Int]] = []
        for m in members {
            let own = Audio.inputBufferChannels(m.id)
            owns.append(own)
            if m.uid == output.uid {
                starts.append(0)
            } else {
                starts.append(expected.count)
                expected += own
            }
        }
        for _ in 0..<tapCount {
            starts.append(expected.count)
            owns.append([2])
            expected.append(2)
        }
        guard Audio.inputBufferChannels(aggregate) == expected else { return nil }

        let slots: [(l: Pos, r: Pos)?] = zip(starts, owns).map { start, own in
            guard let first = own.first, first > 0 else { return nil }
            let l: Pos = (start, 0, first)
            let r: Pos
            if first >= 2 {
                r = (start, 1, first)                       // interleaved stereo (more than 2 channels: first two)
            } else if own.count > 1, own[1] > 0 {
                r = (start + 1, 0, own[1])                  // one stream per channel
            } else {
                r = l                                       // mono: both sides
            }
            return (l, r)
        }
        return (slots, expected.count)
    }
}
