import SwiftUI

/// A rectangle whose corners are rounded as a chunky pixel "staircase" instead
/// of a smooth arc — the classic retro game-UI border corner. `step` is the
/// pixel block size; `steps` is how many blocks make the rounded corner.
struct PixelFrame: Shape {
    var step: CGFloat = 3
    var steps: Int = 3

    func path(in rect: CGRect) -> Path {
        let c = step * CGFloat(steps)                  // corner cut size
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        var p = Path()

        p.move(to: CGPoint(x: minX + c, y: minY))
        p.addLine(to: CGPoint(x: maxX - c, y: minY))                 // top edge
        for i in 0..<steps {                                          // top-right corner
            p.addLine(to: CGPoint(x: maxX - c + CGFloat(i + 1) * step, y: minY + CGFloat(i) * step))
            p.addLine(to: CGPoint(x: maxX - c + CGFloat(i + 1) * step, y: minY + CGFloat(i + 1) * step))
        }
        p.addLine(to: CGPoint(x: maxX, y: maxY - c))                 // right edge
        for i in 0..<steps {                                          // bottom-right corner
            p.addLine(to: CGPoint(x: maxX - CGFloat(i) * step, y: maxY - c + CGFloat(i + 1) * step))
            p.addLine(to: CGPoint(x: maxX - CGFloat(i + 1) * step, y: maxY - c + CGFloat(i + 1) * step))
        }
        p.addLine(to: CGPoint(x: minX + c, y: maxY))                 // bottom edge
        for i in 0..<steps {                                          // bottom-left corner
            p.addLine(to: CGPoint(x: minX + c - CGFloat(i + 1) * step, y: maxY - CGFloat(i) * step))
            p.addLine(to: CGPoint(x: minX + c - CGFloat(i + 1) * step, y: maxY - CGFloat(i + 1) * step))
        }
        p.addLine(to: CGPoint(x: minX, y: minY + c))                 // left edge
        for i in 0..<steps {                                          // top-left corner
            p.addLine(to: CGPoint(x: minX + CGFloat(i) * step, y: minY + c - CGFloat(i + 1) * step))
            p.addLine(to: CGPoint(x: minX + CGFloat(i + 1) * step, y: minY + c - CGFloat(i + 1) * step))
        }
        p.closeSubpath()
        return p
    }
}
