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
                    Text("EXPLODE ON THE GUN")
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
            VStack {
                // Broadcast clock bug
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
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

            VStack {
                Spacer()
                if let p = game.prompt {
                    Text(p)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.8), radius: 6)
                        .padding(.bottom, 6)
                }
                ProgressStrip(dots: game.miniMap)
                    .padding(.bottom, 16)
            }

            // Speed readout
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text(game.speedText).font(Style.mono(20)).foregroundStyle(.white)
                        Text("m/s").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Style.panel, in: Capsule())
                    .padding(.trailing, 18).padding(.bottom, 48)
                }
            }

            // Side tap cues
            if let side = game.nextSide {
                HStack {
                    sideCue(active: side == .left, label: "TAP")
                    Spacer()
                    sideCue(active: side == .right, label: "TAP")
                }
                .padding(.horizontal, 10)
            }
        }
        .animation(.spring(duration: 0.3), value: game.splitToast)
        .animation(.easeOut(duration: 0.2), value: game.verdictFlash)
        .allowsHitTesting(false)
    }

    private func sideCue(active: Bool, label: String) -> some View {
        Circle()
            .fill(active ? Style.gold.opacity(0.30) : .clear)
            .overlay(Circle().strokeBorder(active ? Style.gold : .white.opacity(0.10), lineWidth: 2))
            .overlay(Text(label).font(.system(size: 11, weight: .heavy))
                .foregroundStyle(active ? Style.gold : .white.opacity(0.2)))
            .frame(width: 54, height: 54)
            .animation(.easeOut(duration: 0.12), value: active)
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
