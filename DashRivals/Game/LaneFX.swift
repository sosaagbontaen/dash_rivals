import SceneKit
import UIKit

/// Full-flight lane effects: fire and smoke torn off the spikes once a sprinter
/// is at top speed. Sprites are drawn in code (no assets), particles live in
/// world space so the trail hangs in the lane behind the runner.
enum LaneFX {
    /// Soft radial blob, white to clear — tinted per system.
    static let blob: UIImage = {
        let size = 64
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let mid = CGPoint(x: size / 2, y: size / 2)
            c.drawRadialGradient(g, startCenter: mid, startRadius: 0,
                                 endCenter: mid, endRadius: CGFloat(size) / 2, options: [])
        }
    }()

    private static func curve(_ key: SCNParticleSystem.ParticleProperty,
                              _ values: [CGFloat], _ times: [NSNumber]) -> SCNParticlePropertyController {
        let a = CAKeyframeAnimation(keyPath: key.rawValue)
        a.values = values
        a.keyTimes = times
        return SCNParticlePropertyController(animation: a)
    }

    /// Short, hot, additive. Licks backward and up off the shoe.
    static func flame() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.particleImage = blob
        p.birthRate = 0
        p.emitterShape = SCNSphere(radius: 0.035)
        p.particleLifeSpan = 0.34
        p.particleLifeSpanVariation = 0.12
        p.particleSize = 0.28
        p.particleSizeVariation = 0.10
        p.particleVelocity = 1.6
        p.particleVelocityVariation = 1.0
        p.emittingDirection = SCNVector3(0, 0.45, -1)
        p.spreadingAngle = 24
        p.acceleration = SCNVector3(0, 2.4, 0)
        p.particleColor = UIColor(red: 1.0, green: 0.58, blue: 0.12, alpha: 0.95)
        p.particleColorVariation = SCNVector4(0.04, 0.22, 0.06, 0)
        p.blendMode = .additive
        p.isLightingEnabled = false
        p.isLocal = false
        p.orientationMode = .billboardScreenAligned
        p.propertyControllers = [
            .opacity: curve(.opacity, [0.0, 1.0, 0.8, 0.0], [0, 0.12, 0.45, 1]),
            .size: curve(.size, [0.12, 0.34, 0.14], [0, 0.35, 1]),
        ]
        return p
    }

    /// Slow grey roll that lingers in the lane.
    static func smoke() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.particleImage = blob
        p.birthRate = 0
        p.emitterShape = SCNSphere(radius: 0.05)
        p.particleLifeSpan = 1.2
        p.particleLifeSpanVariation = 0.4
        p.particleSize = 0.32
        p.particleSizeVariation = 0.12
        p.particleVelocity = 0.7
        p.particleVelocityVariation = 0.4
        p.emittingDirection = SCNVector3(0, 0.7, -1)
        p.spreadingAngle = 38
        p.acceleration = SCNVector3(0, 0.8, 0)
        p.particleAngularVelocity = 70
        p.particleAngularVelocityVariation = 50
        p.particleColor = UIColor(white: 0.58, alpha: 0.45)
        p.particleColorVariation = SCNVector4(0.08, 0.08, 0.08, 0.05)
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.isLocal = false
        p.orientationMode = .billboardScreenAligned
        p.propertyControllers = [
            .opacity: curve(.opacity, [0.0, 0.55, 0.35, 0.0], [0, 0.15, 0.55, 1]),
            .size: curve(.size, [0.18, 0.45, 0.80], [0, 0.4, 1]),
        ]
        return p
    }
}
