import Foundation
import libzstd

enum ZstandardDecompressionError: Error, Equatable {
    case initializationFailed
    case invalidFrame(String)
    case truncatedFrame
    case outputLimitExceeded(Int)
}

struct ZstandardDecompressor: Sendable {
    let maximumOutputSize: Int

    init(maximumOutputSize: Int = 256 * 1_024 * 1_024) {
        self.maximumOutputSize = maximumOutputSize
    }

    /// Decompresses one or more concatenated Zstandard frames.
    func decompress(_ compressed: Data) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        guard let stream = ZSTD_createDStream() else {
            throw ZstandardDecompressionError.initializationFailed
        }
        defer { ZSTD_freeDStream(stream) }

        let initialization = ZSTD_initDStream(stream)
        guard ZSTD_isError(initialization) == 0 else {
            throw ZstandardDecompressionError.invalidFrame(errorName(for: initialization))
        }

        let outputBufferSize = Int(ZSTD_DStreamOutSize())
        var outputData = Data()
        var outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
        var finalResult = initialization

        try compressed.withUnsafeBytes { inputBytes in
            guard let inputBase = inputBytes.baseAddress else { return }
            var input = ZSTD_inBuffer(src: inputBase, size: inputBytes.count, pos: 0)

            repeat {
                let previousInputPosition = input.pos
                var written = 0
                finalResult = try outputBuffer.withUnsafeMutableBytes { outputBytes in
                    var output = ZSTD_outBuffer(
                        dst: outputBytes.baseAddress,
                        size: outputBytes.count,
                        pos: 0
                    )
                    let result = ZSTD_decompressStream(stream, &output, &input)
                    guard ZSTD_isError(result) == 0 else {
                        throw ZstandardDecompressionError.invalidFrame(errorName(for: result))
                    }
                    written = output.pos
                    return result
                }

                if written > 0 {
                    guard outputData.count <= maximumOutputSize - written else {
                        throw ZstandardDecompressionError.outputLimitExceeded(maximumOutputSize)
                    }
                    outputData.append(contentsOf: outputBuffer[0..<written])
                }

                if input.pos == previousInputPosition, written == 0, finalResult != 0 {
                    throw ZstandardDecompressionError.truncatedFrame
                }
            } while input.pos < input.size || finalResult != 0
        }

        guard finalResult == 0 else {
            throw ZstandardDecompressionError.truncatedFrame
        }
        return outputData
    }

    private func errorName(for code: Int) -> String {
        guard let name = ZSTD_getErrorName(code) else { return "Unknown Zstandard error" }
        return String(cString: name)
    }
}
