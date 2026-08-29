import UIKit

/// CoreGraphics-drawn textures so the app ships zero asset files.
enum ProceduralTexture {

    static func skyGradient() -> UIImage {
        render(size: CGSize(width: 64, height: 512)) { ctx, size in
            let colors = [
                UIColor(red: 0.010, green: 0.015, blue: 0.055, alpha: 1).cgColor,  // zenith
                UIColor(red: 0.030, green: 0.050, blue: 0.130, alpha: 1).cgColor,
                UIColor(red: 0.100, green: 0.110, blue: 0.240, alpha: 1).cgColor,  // horizon glow
                UIColor(red: 0.240, green: 0.170, blue: 0.280, alpha: 1).cgColor,  // city light haze
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 0.45, 0.8, 1])!
            ctx.drawLinearGradient(grad, start: .zero,
                                   end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    static func trackSpeckle() -> UIImage {
        render(size: CGSize(width: 128, height: 128)) { ctx, size in
            let base = UIColor(red: 0.52, green: 0.19, blue: 0.16, alpha: 1)
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<900 {
                let shade = CGFloat.random(in: -0.06...0.06)
                UIColor(red: 0.52 + shade, green: 0.19 + shade * 0.5, blue: 0.16 + shade * 0.5, alpha: 1).setFill()
                let r = CGFloat.random(in: 0.5...1.6)
                ctx.fillEllipse(in: CGRect(x: .random(in: 0...size.width), y: .random(in: 0...size.height),
                                           width: r, height: r))
            }
        }
    }

    static func grass() -> UIImage {
        render(size: CGSize(width: 128, height: 128)) { ctx, size in
            UIColor(red: 0.045, green: 0.135, blue: 0.075, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<600 {
                let shade = CGFloat.random(in: -0.03...0.035)
                UIColor(red: 0.045 + shade * 0.4, green: 0.135 + shade, blue: 0.075 + shade * 0.5, alpha: 1).setFill()
                ctx.fill(CGRect(x: .random(in: 0...size.width), y: .random(in: 0...size.height),
                                width: .random(in: 1...4), height: .random(in: 1...3)))
            }
            // Mown stripes
            for i in 0..<8 where i % 2 == 0 {
                UIColor(white: 1, alpha: 0.03).setFill()
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * size.height / 8, width: size.width, height: size.height / 8))
            }
        }
    }

    /// A bank of spectators: rows of head/torso dots on a dark background.
    static func crowd() -> UIImage {
        render(size: CGSize(width: 512, height: 512)) { ctx, size in
            UIColor(red: 0.035, green: 0.04, blue: 0.07, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let rows = 24
            let cols = 40
            let cellH = size.height / CGFloat(rows)
            let cellW = size.width / CGFloat(cols)
            let hues: [CGFloat] = [0.0, 0.06, 0.1, 0.55, 0.6, 0.66, 0.75, 0.85, 0.13, 0.33]
            for r in 0..<rows {
                // Aisle gaps
                if r % 9 == 4 { continue }
                for c in 0..<cols {
                    if Int.random(in: 0..<100) < 7 { continue }   // empty seats
                    let x = CGFloat(c) * cellW + cellW / 2 + CGFloat.random(in: -2...2) + (r % 2 == 0 ? cellW / 3 : 0)
                    let y = CGFloat(r) * cellH + cellH / 2 + CGFloat.random(in: -1.5...1.5)
                    // Mostly muted, dark clothing; the odd bright jacket.
                    let standout = Int.random(in: 0..<100) < 6
                    let bright = standout ? CGFloat.random(in: 0.55...0.8) : CGFloat.random(in: 0.10...0.38)
                    let sat = standout ? CGFloat.random(in: 0.5...0.8) : CGFloat.random(in: 0.08...0.35)
                    let hue = hues.randomElement()!
                    // Torso
                    UIColor(hue: hue, saturation: sat, brightness: bright, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x - 4.2, y: y, width: 8.4, height: 9.5))
                    // Head
                    UIColor(hue: 0.07, saturation: CGFloat.random(in: 0.25...0.55),
                            brightness: CGFloat.random(in: 0.18...0.55), alpha: 1).setFill()
                    ctx.fillEllipse(in: CGRect(x: x - 2.8, y: y - 5.4, width: 5.6, height: 5.6))
                }
            }
        }
    }

    static func adBoard() -> UIImage {
        render(size: CGSize(width: 1024, height: 64)) { ctx, size in
            UIColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "DASH RIVALS      ✦      NIGHT MEET      ✦      DASH RIVALS      ✦      NIGHT MEET"
            draw(text: text, font: UIFont.systemFont(ofSize: 34, weight: .heavy),
                 color: UIColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 1),
                 at: CGPoint(x: 12, y: 12))
        }
    }

    static func ledBanner() -> UIImage {
        render(size: CGSize(width: 2048, height: 80)) { ctx, size in
            UIColor(red: 0.02, green: 0.05, blue: 0.16, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "DASH RIVALS   ⚡   MEN 100M FINAL   ⚡   NIGHT MEET   ⚡   DASH RIVALS   ⚡   MEN 100M FINAL   ⚡   NIGHT MEET"
            draw(text: text, font: UIFont.systemFont(ofSize: 44, weight: .black),
                 color: UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1),
                 at: CGPoint(x: 10, y: 16))
        }
    }

    static func infieldLogo() -> UIImage {
        render(size: CGSize(width: 512, height: 512)) { ctx, size in
            ctx.setFillColor(UIColor.clear.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 1, alpha: 0.10).setStroke()
            ctx.setLineWidth(10)
            ctx.strokeEllipse(in: CGRect(x: 40, y: 40, width: 432, height: 432))
            draw(text: "DR", font: UIFont.systemFont(ofSize: 220, weight: .black),
                 color: UIColor(white: 1, alpha: 0.13),
                 at: CGPoint(x: 116, y: 130))
        }
    }

    // MARK: helpers

    private static func render(size: CGSize, _ body: (CGContext, CGSize) -> Void) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            body(rc.cgContext, size)
        }
    }

    private static func draw(text: String, font: UIFont, color: UIColor, at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
