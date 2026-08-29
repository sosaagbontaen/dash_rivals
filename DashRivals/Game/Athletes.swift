import UIKit

/// A fictional sprinter. All identities are original — no real athletes.
struct Athlete {
    let name: String            // display name, e.g. "Jamal Carter"
    let bib: String             // surname for bibs/results, e.g. "CARTER"
    let country: String         // 3-letter code
    let flag: String            // emoji flag for UI only
    let personalBest: Double    // seconds, drives AI difficulty
    let isPlayer: Bool

    // Performance profile
    let reactionMean: Double    // seconds
    let accelTau: Double        // acceleration time constant (bigger = slower starter)
    let enduranceK: Double      // late-race decay factor (smaller = holds speed better)

    // Appearance
    let skinTone: UIColor
    let kitPrimary: UIColor     // vest
    let kitSecondary: UIColor   // shorts
    let shoeColor: UIColor
}

enum Roster {
    static let laneCount = 8
    static let playerLane = 4   // 1-indexed

    static let skin: [UIColor] = [
        UIColor(red: 0.36, green: 0.23, blue: 0.15, alpha: 1),  // deep brown
        UIColor(red: 0.55, green: 0.36, blue: 0.24, alpha: 1),  // brown
        UIColor(red: 0.72, green: 0.52, blue: 0.38, alpha: 1),  // tan
        UIColor(red: 0.85, green: 0.66, blue: 0.50, alpha: 1),  // light tan
        UIColor(red: 0.29, green: 0.18, blue: 0.12, alpha: 1),  // very deep brown
    ]

    /// Index = lane - 1. Championship seeding: fastest in the middle lanes.
    static let athletes: [Athlete] = [
        Athlete(name: "Dmitri Ivanov", bib: "IVANOV", country: "RUS", flag: "🇷🇺",
                personalBest: 10.28, isPlayer: false,
                reactionMean: 0.152, accelTau: 1.30, enduranceK: 0.0030,
                skinTone: skin[3], kitPrimary: UIColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1),
                kitSecondary: UIColor(red: 0.12, green: 0.22, blue: 0.48, alpha: 1),
                shoeColor: UIColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)),
        Athlete(name: "Rafael Silva", bib: "SILVA", country: "BRA", flag: "🇧🇷",
                personalBest: 10.20, isPlayer: false,
                reactionMean: 0.144, accelTau: 1.22, enduranceK: 0.0026,
                skinTone: skin[2], kitPrimary: UIColor(red: 1.00, green: 0.85, blue: 0.10, alpha: 1),
                kitSecondary: UIColor(red: 0.05, green: 0.42, blue: 0.24, alpha: 1),
                shoeColor: UIColor(red: 0.10, green: 0.60, blue: 0.95, alpha: 1)),
        Athlete(name: "Mateo Rossi", bib: "ROSSI", country: "ITA", flag: "🇮🇹",
                personalBest: 10.04, isPlayer: false,
                reactionMean: 0.148, accelTau: 1.34, enduranceK: 0.0020,   // smooth top speed, slow starter
                skinTone: skin[3], kitPrimary: UIColor(red: 0.05, green: 0.45, blue: 0.85, alpha: 1),
                kitSecondary: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1),
                shoeColor: UIColor(red: 1.00, green: 0.55, blue: 0.05, alpha: 1)),
        Athlete(name: "You", bib: "YOU", country: "YOU", flag: "⭐️",
                personalBest: 11.50, isPlayer: true,
                reactionMean: 0.15, accelTau: 1.26, enduranceK: 0.0022,
                skinTone: skin[1], kitPrimary: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
                kitSecondary: UIColor(red: 0.78, green: 0.95, blue: 0.20, alpha: 1),
                shoeColor: UIColor(red: 0.78, green: 0.95, blue: 0.20, alpha: 1)),
        Athlete(name: "Jamal Carter", bib: "CARTER", country: "USA", flag: "🇺🇸",
                personalBest: 9.98, isPlayer: false,
                reactionMean: 0.138, accelTau: 1.24, enduranceK: 0.0022,
                skinTone: skin[0], kitPrimary: UIColor(red: 0.10, green: 0.14, blue: 0.38, alpha: 1),
                kitSecondary: UIColor(red: 0.75, green: 0.10, blue: 0.15, alpha: 1),
                shoeColor: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)),
        Athlete(name: "Andre Mensah", bib: "MENSAH", country: "GHA", flag: "🇬🇭",
                personalBest: 9.96, isPlayer: false,
                reactionMean: 0.146, accelTau: 1.30, enduranceK: 0.0014,   // strong finisher
                skinTone: skin[4], kitPrimary: UIColor(red: 0.95, green: 0.78, blue: 0.05, alpha: 1),
                kitSecondary: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
                shoeColor: UIColor(red: 0.05, green: 0.75, blue: 0.35, alpha: 1)),
        Athlete(name: "Takumi Sato", bib: "SATO", country: "JPN", flag: "🇯🇵",
                personalBest: 10.18, isPlayer: false,
                reactionMean: 0.122, accelTau: 1.16, enduranceK: 0.0034,   // rocket start, fades late
                skinTone: skin[3], kitPrimary: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1),
                kitSecondary: UIColor(red: 0.85, green: 0.10, blue: 0.15, alpha: 1),
                shoeColor: UIColor(red: 0.85, green: 0.10, blue: 0.15, alpha: 1)),
        Athlete(name: "Liam O'Connor", bib: "O'CONNOR", country: "AUS", flag: "🇦🇺",
                personalBest: 10.12, isPlayer: false,
                reactionMean: 0.150, accelTau: 1.28, enduranceK: 0.0024,
                skinTone: skin[3], kitPrimary: UIColor(red: 0.02, green: 0.35, blue: 0.28, alpha: 1),
                kitSecondary: UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1),
                shoeColor: UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)),
    ]

    static var playerIndex: Int { athletes.firstIndex(where: { $0.isPlayer })! }

    /// Lane center x-coordinate in meters. Lane 1 is nearest the infield (x = 0 side).
    static func laneX(_ lane: Int) -> Float {
        Track.laneWidth * (Float(lane) - 0.5)
    }
}

/// Track geometry constants (meters). Runners run along +Z, from z=0 to z=100.
enum Track {
    static let laneWidth: Float = 1.22
    static let lanes = 8
    static let width: Float = laneWidth * Float(lanes)   // 9.76
    static let raceLength: Float = 100
    static let runoutLength: Float = 32                  // deceleration zone past the line
    static let backstretch: Float = 22                   // track behind the start line
}
