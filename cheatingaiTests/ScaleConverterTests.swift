import Testing
import CoreGraphics
@testable import cheatingai

struct ScaleConverterTests {
    @Test func retinaPixelConversion() async throws {
        // Simulate a 100x100pt rect on a 2x screen -> 200x200px
        let rectPt = CGRect(x: 10, y: 20, width: 100, height: 100)
        let scale: CGFloat = 2.0
        let px = CGSize(width: rectPt.width * scale, height: rectPt.height * scale)
        #expect(px.width == 200)
        #expect(px.height == 200)
    }
    
    @Test func standardDisplayConversion() async throws {
        // Test 1x display scaling
        let rectPt = CGRect(x: 0, y: 0, width: 50, height: 75)
        let scale: CGFloat = 1.0
        let px = CGSize(width: rectPt.width * scale, height: rectPt.height * scale)
        #expect(px.width == 50)
        #expect(px.height == 75)
    }
}
