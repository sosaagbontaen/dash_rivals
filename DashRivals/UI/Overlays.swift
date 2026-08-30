import SwiftUI

enum Style {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.15)
    static let panel = Color.black.opacity(0.62)
    static let good = Color(red: 0.35, green: 0.95, blue: 0.45)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.30)

    static func headline(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).italic()
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Menu

struct MenuOverlay: View {
    @ObservedObject var game: GameController

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                Text("DASH")
                    .font(Style.headline(58)).foregroundStyle(.white)
                Text("RIVALS")
                    .font(Style.headline(58)).foregroundStyle(Style.gold)
                    .padding(.top, -26)
                Text("NIGHT MEET · MEN 100M FINAL")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 8) {
                    Text("BEST").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    Text(game.bestTimeText).font(Style.mono(18)).foregroundStyle(Style.gold)
                }
                .padding(.top, 2)

                Button {
                    game.startRace()
                } label: {
                    Text("RACE")
                        .font(Style.headline(30))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 52).padding(.vertical, 12)
                        .background(Style.gold, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 16)

                // A/B tracking toggle (dev) + units
                HStack(spacing: 6) {
                    Text("TRACKING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    trackingChip("LINEAR", .linear)
                    trackingChip("CIRCLE", .circle)
                }
                .padding(.top, 10)
                HStack(spacing: 6) {
                    Text("SPEED IN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    unitChip("M/S", false)
                    unitChip("MPH", true)
                }
                .padding(.top, 4)

                Text("PROOF OF CONCEPT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 10)
                Spacer().frame(height: 30)
            }
            .padding(.leading, 46)
            Spacer()
        }
    }

    private func trackingChip(_ label: String, _ t: TrackingStyle) -> some View {
        Button { game.setTracking(t) } label: {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(game.trackingStyle == t ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(game.trackingStyle == t ? Style.gold : Color.white.opacity(0.12),
                            in: Capsule())
        }
    }

    private func unitChip(_ label: String, _ mph: Bool) -> some View {
        Button { game.setUseMph(mph) } label: {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(game.useMph == mph ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(game.useMph == mph ? Style.gold : Color.white.opacity(0.12),
                            in: Capsule())
        }
    }
}

// MARK: - Intro (field introductions)

struct IntroOverlay: View {
    @ObservedObject var game: GameController

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("TAP TO SKIP")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.trailing, 24).padding(.top, 18)
            }
            Spacer()
            if let a = game.introCard {
                HStack(spacing: 14) {
                    Text(a.flag).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name.uppercased())
                            .font(Style.headline(26)).foregroundStyle(.white)
                        HStack(spacing: 10) {
                            Text(a.country).font(.system(size: 14, weight: .heavy)).foregroundStyle(Style.gold)
                            if !a.isPlayer {
                                Text(String(format: "PB %.2f", a.personalBest))
                                    .font(Style.mono(14)).foregroundStyle(.white.opacity(0.8))
                            } else {
                                Text("THAT'S YOU").font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Style.good)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26).padding(.vertical, 14)
                .background(Style.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
                .id(a.name)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
                .padding(.bottom, 40)
            }
        }
        .animation(.spring(duration: 0.35), value: game.introCard?.name)
        .allowsHitTesting(false)
    }
}

// MARK: - Marks / Set

struct MarksSetOverlay: View {
    @ObservedObject var game: GameController
    let isSet: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                holdZone(active: game.holdingL || isSet, label: "L")
                Spacer()
                holdZone(active: game.holdingR || isSet, label: "R")
            }
            VStack(spacing: 8) {
                if isSet {
                    Text("SET…")
                        .font(Style.headline(44)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 8)
                    Text("GUN: LIFT A THUMB — THEN RIDE THE BAR")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("HOLD BOTH SIDES")
                        .font(Style.headline(34)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 8)
                    Text("CROUCH INTO THE BLOCKS")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .offset(y: -30)
        }
        .allowsHitTesting(false)
    }

    private func holdZone(active: Bool, label: String) -> some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(active ? Style.good.opacity(0.20) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(active ? Style.good.opacity(0.8) : .white.opacity(0.18), lineWidth: 2)
            )
            .overlay(
                Text(label).font(Style.headline(30))
                    .foregroundStyle(active ? Style.good : .white.opacity(0.35))
            )
            .frame(width: 110)
            .padding(.vertical, 60)
            .padding(.horizontal, 18)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

// MARK: - Race HUD

struct RaceHUD: View {
    @ObservedObject var game: GameController

    var body: some View {
        ZStack {
            // Cinematic letterbox: slides in when you hit full flight.
            VStack {
                Rectangle().fill(.black)
                    .frame(height: game.cinematicBars ? 36 : 0)
                Spacer()
                Rectangle().fill(.black)
                    .frame(height: game.cinematicBars ? 36 : 0)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: game.cinematicBars)

            VStack {
                // Broadcast clock bug: event · clock · sprint phase
                HStack(spacing: 0) {
                    Text("M 100m")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Style.gold)
                    Text(game.clockText)
                        .font(Style.mono(17))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.black.opacity(0.75))
                    if let phase = game.phaseLabel {
                        Text(phase)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Style.gold)
                            .padding(.horizontal, 10).padding(.vertical, 6.5)
                            .background(Color.black.opacity(0.55))
                            .transition(.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeOut(duration: 0.2), value: game.phaseLabel)
                .padding(.top, 14)

                if let toast = game.splitToast {
                    Text(toast)
                        .font(Style.mono(16))
                        .foregroundStyle(Style.gold)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Style.panel, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 6)
                }
                Spacer()
            }

            // Tap-timing verdict flash
            if let flash = game.verdictFlash {
                Text(flash.text)
                    .font(Style.headline(30))
                    .foregroundStyle(flash.good ? Style.good : Style.bad)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .id(flash.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.6).combined(with: .opacity),
                        removal: .opacity))
                    .offset(y: -46)
                    .task(id: flash.id) {
                        try? await Task.sleep(for: .milliseconds(600))
                        if game.verdictFlash?.id == flash.id { game.verdictFlash = nil }
                    }
            }

            VStack(spacing: 8) {
                Spacer()
                if let p = game.prompt {
                    Text(p)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.8), radius: 6)
                }
                HStack(spacing: 10) {
                    FormMeter(value: game.formValue)
                    HStack(spacing: 4) {
                        Text(game.speedText).font(Style.mono(18)).foregroundStyle(.white)
                        Text(game.useMph ? "mph" : "m/s")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Style.panel, in: Capsule())
                }
                ProgressStrip(dots: game.miniMap)
                    .padding(.bottom, game.gaugeVisible ? 48 : 16)
            }

            // The dip cue: yank both thumbs down at the line.
            if game.leanCue {
                LeanCueView()
                    .offset(y: -20)
            }

            // Twin tracking gauges at the bottom corners (A/B: bars vs pads).
            if game.gaugeVisible {
                VStack {
                    Spacer()
                    if game.trackingStyle == .circle {
                        HStack {
                            EffortGauge(effort: game.effortL,
                                        angle: game.stickAngleL,
                                        targetRadius: game.bandCenter,
                                        targetTol: game.discTol,
                                        targetAngle: Double.pi - game.targetAngle,
                                        tension: game.tensionValue)
                                .padding(.leading, 14)
                            Spacer()
                            EffortGauge(effort: game.effortR,
                                        angle: game.stickAngleR,
                                        targetRadius: game.bandCenter,
                                        targetTol: game.discTol,
                                        targetAngle: game.targetAngle,
                                        tension: game.tensionValue)
                                .padding(.trailing, 14)
                        }
                        .padding(.bottom, 14)
                    } else {
                        HStack {
                            LinearGauge(effort: game.effortL,
                                        bandCenter: game.bandCenter,
                                        bandHalf: game.bandHalf,
                                        tension: game.tensionValue)
                                .scaleEffect(x: -1, y: 1)   // left thumb: outward = leftward
                                .padding(.leading, 16)
                            Spacer()
                            LinearGauge(effort: game.effortR,
                                        bandCenter: game.bandCenter,
                                        bandHalf: game.bandHalf,
                                        tension: game.tensionValue)
                                .padding(.trailing, 16)
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: game.splitToast)
        .animation(.easeOut(duration: 0.2), value: game.verdictFlash)
        .allowsHitTesting(false)
    }
}

/// Joystick pursuit gauge — the linear-band tracking made 2D. A filled yellow
/// dot wanders around the pad; chase it with your thumb (the white knob, drawn
/// 1:1 under your finger). Knob turns red the moment it slips off the dot;
/// red rim = tension building from overpushing.
struct EffortGauge: View {
    let effort: Double
    let angle: Double        // radians, thumb's direction (view space)
    let targetRadius: Double // dot's distance from center, effort units
    let targetTol: Double    // dot's radius, effort units
    let targetAngle: Double  // radians, dot's direction (view space)
    let tension: Double

    private let size: CGFloat = 190
    private let deadR: CGFloat = 9
    private let usable: CGFloat = 82   // must match TouchSCNView mapping

    private func r(_ value: Double) -> CGFloat {
        deadR + usable * CGFloat(min(1, max(0, value)))
    }

    private var onTarget: Bool {
        let kx = effort * cos(angle), ky = effort * sin(angle)
        let tx = targetRadius * cos(targetAngle), ty = targetRadius * sin(targetAngle)
        return ((kx - tx) * (kx - tx) + (ky - ty) * (ky - ty)).squareRoot() <= targetTol
    }

    var body: some View {
        // Honest size: the drawn dot IS the scoring tolerance (+ a hair of grace).
        let discR = CGFloat(targetTol) * usable + 4
        ZStack {
            // Stick base
            Circle()
                .fill(Color.black.opacity(0.40))
                .overlay(
                    Circle().strokeBorder(tension > 0.4 ? Style.bad.opacity(0.3 + 0.6 * tension)
                                                        : Color.white.opacity(0.16),
                                          lineWidth: tension > 0.4 ? 2.5 : 1)
                )
            Circle().fill(Color.white.opacity(0.22)).frame(width: 8, height: 8)
            // The target: a filled yellow dot on the move — keep your thumb on it.
            Circle()
                .fill(Style.gold.opacity(onTarget ? 0.85 : 0.6))
                .overlay(Circle().strokeBorder(Style.gold, lineWidth: 2))
                .frame(width: discR * 2, height: discR * 2)
                .offset(x: cos(targetAngle) * r(targetRadius),
                        y: sin(targetAngle) * r(targetRadius))
            // The knob: your thumb. White on the dot, red off it.
            Circle()
                .fill(onTarget ? Color.white : Style.bad)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.7), radius: 3)
                .offset(x: cos(angle) * r(effort), y: sin(angle) * r(effort))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.08), value: effort)
        .animation(.linear(duration: 0.08), value: targetRadius)
        .animation(.linear(duration: 0.08), value: targetAngle)
    }
}

/// Linear tracking gauge: the horizontal band — keep the white marker inside the
/// gold target area as it slides through the race. Left instance is x-flipped so
/// outward = more effort on both thumbs.
struct LinearGauge: View {
    let effort: Double
    let bandCenter: Double
    let bandHalf: Double
    let tension: Double

    private let width: CGFloat = 300
    private let height: CGFloat = 30

    private func x(_ value: Double) -> CGFloat {
        width * CGFloat(min(1, max(0, value)))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(tension > 0.4 ? Style.bad.opacity(0.3 + 0.6 * tension)
                                                    : Color.white.opacity(0.18),
                                      lineWidth: tension > 0.4 ? 2.5 : 1)
                )
            RoundedRectangle(cornerRadius: 7)
                .fill(Style.gold.opacity(0.38))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Style.gold.opacity(0.85), lineWidth: 1.5))
                .frame(width: max(12, width * CGFloat(bandHalf * 2)), height: height - 8)
                .offset(x: x(bandCenter - bandHalf), y: 0)
                .padding(.vertical, 4)
            Capsule()
                .fill(abs(effort - bandCenter) <= bandHalf ? Color.white : Style.bad)
                .frame(width: 5, height: height + 10)
                .shadow(color: .black.opacity(0.7), radius: 3)
                .offset(x: x(effort) - 2.5, y: 0)
        }
        .frame(width: width, height: height)
        .animation(.linear(duration: 0.08), value: effort)
        .animation(.linear(duration: 0.08), value: bandCenter)
    }
}

/// Broadcast replay dressing: letterbox bars, red REPLAY bug, skip hint.
struct ReplayOverlay: View {
    @State private var blink = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(.black).frame(height: 54)
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(Style.bad).frame(width: 9, height: 9)
                            .opacity(blink ? 0.25 : 1)
                        Text("REPLAY")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .kerning(2)
                    }
                    Spacer()
                    Text("TAP TO SKIP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 26)
            }
            Spacer()
            Rectangle().fill(.black).frame(height: 54)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
    }
}

/// The line is coming: falling chevrons — yank both thumbs down to dip.
struct LeanCueView: View {
    @State private var fall = false

    var body: some View {
        VStack(spacing: 2) {
            Text("DIP!")
                .font(Style.headline(26))
                .foregroundStyle(Style.gold)
                .shadow(color: .black.opacity(0.8), radius: 6)
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Style.gold.opacity(1 - Double(i) * 0.28))
            }
            .offset(y: fall ? 14 : -4)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.35).repeatForever(autoreverses: false)) {
                fall = true
            }
        }
    }
}

/// Rhythm quality made visible: this is the number that decides your speed.
struct FormMeter: View {
    let value: Double

    private var color: Color {
        if value >= 0.8 { return Style.gold }
        if value >= 0.55 { return Color(red: 1.0, green: 0.62, blue: 0.2) }
        return Style.bad
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("FORM")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.6))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: 110, height: 7)
                Capsule().fill(color)
                    .frame(width: max(7, 110 * CGFloat(min(1, value))), height: 7)
                    .animation(.linear(duration: 0.12), value: value)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Style.panel, in: Capsule())
    }
}


/// Mini race-progress strip: 8 dots moving left→right.
struct ProgressStrip: View {
    let dots: [MiniMapDot]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3).offset(y: 8)
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 2, height: 14)
                    .offset(x: geo.size.width - 2)
                ForEach(dots) { dot in
                    Circle()
                        .fill(Color(uiColor: dot.color))
                        .frame(width: dot.isPlayer ? 12 : 8, height: dot.isPlayer ? 12 : 8)
                        .overlay(Circle().strokeBorder(.white, lineWidth: dot.isPlayer ? 2 : 0.5))
                        .offset(x: CGFloat(dot.progress) * (geo.size.width - 12),
                                y: dot.isPlayer ? 2 : 4)
                }
            }
        }
        .frame(width: 380, height: 18)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Style.panel, in: Capsule())
        .opacity(dots.isEmpty ? 0 : 1)
    }
}

// MARK: - Finish interstitial (crossing the line → results)

struct FinishOverlay: View {
    @ObservedObject var game: GameController

    var body: some View {
        VStack(spacing: 4) {
            Text(game.clockText)
                .font(Style.mono(74, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 10)
            Text("FINISH")
                .font(Style.headline(22))
                .foregroundStyle(Style.gold)
        }
        .allowsHitTesting(false)
    }
}
