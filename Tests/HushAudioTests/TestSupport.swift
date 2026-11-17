import CoreAudio
import Foundation

func isApproximatelyEqual(_ a: Float, _ b: Float, tolerance: Float = 1e-5) -> Bool {
    abs(a - b) <= tolerance
}

/// Owns a heap AudioBufferList with Float32 buffers for tests.
final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(_ buffers: [(channels: Int, samples: [Float])]) {
        // allocate(maximumBuffers:) traps on 0, so reserve at least one and set the real count.
        list = AudioBufferList.allocate(maximumBuffers: max(buffers.count, 1))
        list.count = buffers.count
        for (index, buffer) in buffers.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(buffer.samples.count, 1))
            pointer.initialize(from: buffer.samples, count: buffer.samples.count)
            storage.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(buffer.channels),
                mDataByteSize: UInt32(buffer.samples.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(pointer))
        }
    }

    func samples(_ index: Int) -> [Float] {
        let count = Int(list[index].mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: storage[index], count: count))
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}
