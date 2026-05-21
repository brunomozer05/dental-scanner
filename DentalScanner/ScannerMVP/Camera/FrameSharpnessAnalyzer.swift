import CoreVideo
import Foundation

enum FrameSharpnessAnalyzer {
    static func varianceOfLaplacian(in pixelBuffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 4, height > 4, bytesPerRow >= width * 4 else {
            return nil
        }

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let stepX = max(width / 96, 2)
        let stepY = max(height / 72, 2)
        var count = 0
        var sum = 0.0
        var sumSquares = 0.0

        for y in stride(from: 1, to: height - 1, by: stepY) {
            for x in stride(from: 1, to: width - 1, by: stepX) {
                let center = luma(atX: x, y: y, pixels: pixels, bytesPerRow: bytesPerRow)
                let left = luma(atX: x - 1, y: y, pixels: pixels, bytesPerRow: bytesPerRow)
                let right = luma(atX: x + 1, y: y, pixels: pixels, bytesPerRow: bytesPerRow)
                let up = luma(atX: x, y: y - 1, pixels: pixels, bytesPerRow: bytesPerRow)
                let down = luma(atX: x, y: y + 1, pixels: pixels, bytesPerRow: bytesPerRow)
                let laplacian = Double(4 * center - left - right - up - down)

                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }

        guard count > 8 else {
            return nil
        }

        let mean = sum / Double(count)
        let variance = sumSquares / Double(count) - mean * mean
        return variance.isFinite ? max(variance, 0.0) : nil
    }

    private static func luma(
        atX x: Int,
        y: Int,
        pixels: UnsafePointer<UInt8>,
        bytesPerRow: Int
    ) -> Int {
        let offset = y * bytesPerRow + x * 4
        let blue = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let red = Int(pixels[offset + 2])

        return (77 * red + 150 * green + 29 * blue) >> 8
    }
}
