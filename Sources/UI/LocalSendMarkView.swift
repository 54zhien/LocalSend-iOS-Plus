import SwiftUI

/// Draws both logo parts in one coordinate system, so rotating the ring never shifts its center.
struct LocalSendMarkView: View {
  let rotates: Bool
  var size: CGFloat = 200

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !rotates)) { timeline in
      let angle = rotates
        ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 15) * 24
        : 0

      ZStack {
        LocalSendRingShape()
          .fill(.tint)
          .frame(width: size, height: size)
          .rotationEffect(.degrees(angle))

        Circle()
          .fill(.tint)
          .frame(width: size * 420 / 1024, height: size * 420 / 1024)
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
    }
    .frame(width: size, height: size)
  }
}

private struct LocalSendRingShape: Shape {
  func path(in rect: CGRect) -> Path {
    let scaleX = rect.width / 1024
    let scaleY = rect.height / 1024
    var path = Path()

    func point(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat) -> CGPoint {
      let radians = angle * .pi / 180
      let dx = x - 512
      let dy = y - 512
      return CGPoint(
        x: rect.minX + (512 + dx * cos(radians) - dy * sin(radians)) * scaleX,
        y: rect.minY + (512 + dx * sin(radians) + dy * cos(radians)) * scaleY
      )
    }

    for step in 0..<8 {
      let angle = CGFloat(step) * 45
      path.move(to: point(402, 137, angle))
      path.addCurve(to: point(622, 137, angle), control1: point(473, 117, angle), control2: point(551, 117, angle))
      path.addCurve(to: point(568, 184, angle), control1: point(615, 168, angle), control2: point(600, 187, angle))
      path.addCurve(to: point(456, 184, angle), control1: point(531, 180, angle), control2: point(493, 180, angle))
      path.addCurve(to: point(402, 137, angle), control1: point(424, 187, angle), control2: point(409, 168, angle))
      path.closeSubpath()
    }

    return path
  }
}
