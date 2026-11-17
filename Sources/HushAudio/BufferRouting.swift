import CoreAudio
import Foundation
import HushCore

/// Realtime-safe routing between a tap's input buffers and a device's output buffers.
/// No allocation, no locks, no Objective-C. Assumes Float32 samples (the HAL's canonical format).
enum BufferRouting {
    static func render(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        startGain: Float,
        endGain: Float
    ) -> Float {
        var totalInputChannels = 0
        for buffer in input { totalInputChannels += Int(buffer.mNumberChannels) }

        var peak: Float = 0
        var outputChannel = 0
        for buffer in output {
            let outChannels = max(Int(buffer.mNumberChannels), 1)
            guard let outData = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                outputChannel += outChannels
                continue
            }
            let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
            for channel in 0..<outChannels {
                let destination = outData.advanced(by: channel)
                var written = 0
                if totalInputChannels > 0,
                   let source = locate(channel: outputChannel % totalInputChannels, in: input) {
                    written = min(outFrames, source.frames)
                    let channelPeak = SampleProcessor.apply(
                        startGain: startGain,
                        endGain: endGain,
                        input: source.pointer,
                        inputStride: source.stride,
                        output: destination,
                        outputStride: outChannels,
                        frameCount: written)
                    peak = max(peak, channelPeak)
                }
                var frame = written
                while frame < outFrames {
                    destination[frame * outChannels] = 0
                    frame += 1
                }
                outputChannel += 1
            }
        }
        return peak
    }

    static func peak(of input: UnsafeMutableAudioBufferListPointer) -> Float {
        var peak: Float = 0
        for buffer in input {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            peak = max(peak, SampleProcessor.peak(input: data, stride: 1, frameCount: samples))
        }
        return peak
    }

    static func silence(_ output: UnsafeMutableAudioBufferListPointer) {
        for buffer in output {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    private static func locate(
        channel: Int,
        in list: UnsafeMutableAudioBufferListPointer
    ) -> (pointer: UnsafePointer<Float>, stride: Int, frames: Int)? {
        var remaining = channel
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            if remaining < channels {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return nil }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                return (UnsafePointer(data.advanced(by: remaining)), channels, frames)
            }
            remaining -= channels
        }
        return nil
    }
}
