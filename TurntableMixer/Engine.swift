import CoreAudio
import Foundation
import Synchronization

// MARK: - Audio thread

/// Everything the IOProc touches. Heap-allocated on the main thread before `AudioDeviceStart`,
/// freed only after `AudioDeviceStop` + `AudioDeviceDestroyIOProcID`.
/// Atomics carry parameters in and meter data out. The plain fields are written once, before start.
struct EngineState: ~Copyable {
    let target = Atomic<UInt32>(0)      // linear gain (fader x mute), Float bit pattern
    let peakL = Atomic<UInt32>(0)       // post-fader peak since the UI last read it, Float bit pattern
    let peakR = Atomic<UInt32>(0)
    let inPeak = Atomic<UInt32>(0)      // raw turntable input peak (before gain and clip) since the UI last read it, Float bit pattern
    let clipped = Atomic<UInt32>(0)     // 1 when a sample went over full scale before the hard clip

    // Written by the IOProc only.
    var current: Float = 0              // gain now, ramping toward `target`

    // Written before start only.
    var valid = false
    var step: Float = 0                 // gain change per sample (reaches any target in about 15 ms)
    var inputBuffers = 0                // aggregate input buffers the layout below needs
    var lBuf = 0, lOff = 0, lStride = 1 // where the turntable's left sample sits in the input buffer list
    var rBuf = 0, rOff = 0, rStride = 1
}

/// The IOProc. Real-time: no allocation, locks, logging, ARC or Swift collections.
nonisolated func turntableIOProc(_ device: AudioObjectID,
                                 _ now: UnsafePointer<AudioTimeStamp>,
                                 _ inData: UnsafePointer<AudioBufferList>,
                                 _ inTime: UnsafePointer<AudioTimeStamp>,
                                 _ outData: UnsafeMutablePointer<AudioBufferList>,
                                 _ outTime: UnsafePointer<AudioTimeStamp>,
                                 _ client: UnsafeMutableRawPointer?) -> OSStatus {
    guard let client else { return noErr }
    let s = client.assumingMemoryBound(to: EngineState.self)
    let outs = UnsafeMutableAudioBufferListPointer(outData)

    // Silence every output buffer first; then write L and R over it.
    for i in 0..<outs.count {
        if let d = outs[i].mData { memset(d, 0, Int(outs[i].mDataByteSize)) }
    }
    guard s.pointee.valid, outs.count > 0 else { return noErr }
    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard ins.count >= s.pointee.inputBuffers else { return noErr }

    let lBuf = s.pointee.lBuf, rBuf = s.pointee.rBuf
    let lStride = s.pointee.lStride, rStride = s.pointee.rStride
    let inL = ins[lBuf], inR = ins[rBuf]
    guard Int(inL.mNumberChannels) == lStride, Int(inR.mNumberChannels) == rStride,
          let lSrc = inL.mData?.assumingMemoryBound(to: Float.self),
          let rSrc = inR.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    var frames = min(Int(inL.mDataByteSize) / (4 * lStride), Int(inR.mDataByteSize) / (4 * rStride))

    // Output: left on the first channel; right on the second channel, or on the next buffer if the first is mono.
    let out0 = outs[0]
    let c0 = Int(out0.mNumberChannels)
    guard c0 > 0, let o0 = out0.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    frames = min(frames, Int(out0.mDataByteSize) / (4 * c0))
    let lDst = o0, lDstStride = c0
    var rDst: UnsafeMutablePointer<Float>? = nil
    var rDstStride = 1, rDstOff = 0
    if c0 >= 2 {
        rDst = o0; rDstStride = c0; rDstOff = 1
    } else if outs.count > 1, outs[1].mNumberChannels > 0,
              let o1 = outs[1].mData?.assumingMemoryBound(to: Float.self) {
        rDst = o1; rDstStride = Int(outs[1].mNumberChannels)
        frames = min(frames, Int(outs[1].mDataByteSize) / (4 * rDstStride))
    }

    let target = Float(bitPattern: s.pointee.target.load(ordering: .relaxed))
    let step = s.pointee.step
    let lOff = s.pointee.lOff, rOff = s.pointee.rOff
    var gain = s.pointee.current
    var peakL: Float = 0, peakR: Float = 0
    var peakIn: Float = 0
    var over = false

    for f in 0..<frames {
        if gain < target { gain = min(gain + step, target) } else if gain > target { gain = max(gain - step, target) }
        let rawL = lSrc[f * lStride + lOff], rawR = rSrc[f * rStride + rOff]
        peakIn = max(peakIn, max(abs(rawL), abs(rawR)))
        var l = rawL * gain
        var r = rawR * gain
        if abs(l) > 1 || abs(r) > 1 { over = true }
        l = min(max(l, -1), 1)
        r = min(max(r, -1), 1)
        lDst[f * lDstStride] = l
        if let rDst { rDst[f * rDstStride + rDstOff] = r }
        peakL = max(peakL, abs(l))
        peakR = max(peakR, abs(r))
    }
    s.pointee.current = gain
    // Positive Float bit patterns sort like the floats, so compare them as integers.
    if peakL.bitPattern > s.pointee.peakL.load(ordering: .relaxed) { s.pointee.peakL.store(peakL.bitPattern, ordering: .relaxed) }
    if peakR.bitPattern > s.pointee.peakR.load(ordering: .relaxed) { s.pointee.peakR.store(peakR.bitPattern, ordering: .relaxed) }
    if peakIn.bitPattern > s.pointee.inPeak.load(ordering: .relaxed) { s.pointee.inPeak.store(peakIn.bitPattern, ordering: .relaxed) }
    if over { s.pointee.clipped.store(1, ordering: .relaxed) }
    return noErr
}

// MARK: - Main thread

/// Owns the private aggregate device and its IOProc (spec D2). Main thread only.
final class Engine {
    private var aggregate = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?
    private var state: UnsafeMutablePointer<EngineState>?
    private(set) var runningDeviceID: AudioObjectID?

    private static let bufferFrames: UInt32 = 256

    /// Builds the aggregate for the turntable and starts it. Returns an error message, or nil on success.
    func start(turntable: InputDevice) -> String? {
        stop()
        let out = Audio.defaultOutput()
        guard out != 0, let outUID = Audio.string(out, kAudioDevicePropertyDeviceUID) else { return "No output device." }

        // Never hog mode (D6): nothing here sets kAudioDevicePropertyHogMode.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Turntable Mixer engine",
            kAudioAggregateDeviceUIDKey: "io.github.qaid.turntablemixer.engine." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outUID, kAudioSubDeviceDriftCompensationKey: 0],
                [kAudioSubDeviceUIDKey: turntable.uid, kAudioSubDeviceDriftCompensationKey: 1,
                 kAudioSubDeviceDriftCompensationQualityKey: kAudioAggregateDriftCompensationMediumQuality],
            ],
        ]
        var agg = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &agg) == noErr else {
            return "Could not create the audio engine."
        }
        aggregate = agg

        setBufferSize(agg)
        guard let layout = Self.layout(aggregate: agg, output: out, turntable: turntable.id) else {
            destroy()
            return "Could not read the turntable's channels."
        }

        let rate = Audio.value(agg, kAudioDevicePropertyNominalSampleRate, Float64(48000))
        let p = UnsafeMutablePointer<EngineState>.allocate(capacity: 1)
        p.initialize(to: EngineState())
        p.pointee.step = Gain.linear(db: Gain.maxDB) / Float(0.015 * rate)
        p.pointee.inputBuffers = layout.inputBuffers
        p.pointee.lBuf = layout.l.buf; p.pointee.lOff = layout.l.off; p.pointee.lStride = layout.l.stride
        p.pointee.rBuf = layout.r.buf; p.pointee.rOff = layout.r.off; p.pointee.rStride = layout.r.stride
        p.pointee.valid = true
        state = p

        var id: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcID(agg, turntableIOProc, p, &id) == noErr, let id else {
            destroy()
            return "Could not create the audio engine."
        }
        procID = id
        guard AudioDeviceStart(agg, id) == noErr else {
            destroy()
            return "Could not start the audio engine."
        }
        runningDeviceID = turntable.id
        return nil
    }

    /// Stops and destroys the aggregate. Safe to call when not running.
    func stop() {
        destroy()
    }

    func setTarget(_ linear: Float) {
        state?.pointee.target.store(linear.bitPattern, ordering: .relaxed)
    }

    /// Peaks since the last call (resets them), and whether the clip flag was set.
    func takePeaks() -> (l: Float, r: Float, input: Float, clipped: Bool) {
        guard let s = state else { return (0, 0, 0, false) }
        return (Float(bitPattern: s.pointee.peakL.exchange(0, ordering: .relaxed)),
                Float(bitPattern: s.pointee.peakR.exchange(0, ordering: .relaxed)),
                Float(bitPattern: s.pointee.inPeak.exchange(0, ordering: .relaxed)),
                s.pointee.clipped.exchange(0, ordering: .relaxed) != 0)
    }

    // The order matters: stop, destroy the IOProc, then free the state, then destroy the aggregate.
    private func destroy() {
        var procGone = true
        if let procID {
            AudioDeviceStop(aggregate, procID)
            procGone = AudioDeviceDestroyIOProcID(aggregate, procID) == noErr
        }
        procID = nil
        // ponytail: if the IOProc could still run, leak the state (one small struct) instead of freeing it under it.
        if let state, procGone {
            state.deinitialize(count: 1)
            state.deallocate()
        }
        state = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = 0
        runningDeviceID = nil
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

    typealias Slot = (buf: Int, off: Int, stride: Int)

    /// Finds the turntable's first two channels in the aggregate's input buffer list.
    /// Aggregate inputs = each sub-device's input streams, in sub-device order (output first, turntable second).
    private static func layout(aggregate: AudioObjectID, output: AudioObjectID, turntable: AudioObjectID)
        -> (l: Slot, r: Slot, inputBuffers: Int)? {
        let skip = Audio.inputStreamCount(output)
        let own = Audio.inputBufferChannels(turntable)
        let all = Audio.inputBufferChannels(aggregate)
        guard let first = own.first, first > 0, all.count == skip + own.count,
              Array(all[skip...]) == own else { return nil }
        let l: Slot = (skip, 0, first)
        let r: Slot
        if first >= 2 {
            r = (skip, 1, first)                       // interleaved stereo (more than 2 channels: first two)
        } else if own.count > 1, own[1] > 0 {
            r = (skip + 1, 0, own[1])                  // one stream per channel
        } else {
            r = l                                      // mono: both sides
        }
        return (l, r, all.count)
    }
}
