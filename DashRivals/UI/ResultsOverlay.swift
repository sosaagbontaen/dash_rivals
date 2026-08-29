import SwiftUI

struct ResultsOverlay: View {
    @ObservedObject var game: GameController

    var body: some View {
        HStack(spacing: 18) {
            resultsTable
            Spacer()
            yourRacePanel
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 22)
    }

    private var winnerTime: Double? {
        game.resultRows.first?.time
    }

    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RESULT · MEN 100M FINAL")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Style.gold)
                .padding(.bottom, 3)
            ForEach(game.resultRows) { row in
                HStack(spacing: 9) {
                    Text("\(row.place)")
                        .font(Style.mono(13))
                        .foregroundStyle(row.place == 1 ? Style.gold : .white.opacity(0.65))
                        .frame(width: 16, alignment: .trailing)
                    Text(row.athlete.flag).font(.system(size: 13))
                    Text(row.athlete.bib)
                        .font(.system(size: 13, weight: row.isPlayer ? .black : .semibold))
                        .foregroundStyle(row.isPlayer ? Style.gold : .white)
                        .frame(width: 92, alignment: .leading)
                    Text(row.time.map { String(format: "%.2f", $0) } ?? "DNF")
                        .font(Style.mono(13))
                        .foregroundStyle(.white)
                    if let t = row.time, let w = winnerTime, row.place > 1 {
                        Text(String(format: "+%.2f", t - w))
                            .font(Style.mono(10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.vertical, 1.5)
                .padding(.horizontal, 8)
                .background(row.isPlayer ? Color.white.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Style.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
    }

    private var yourRacePanel: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let s = game.summary {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if s.isNewPB {
                        Text("NEW PB")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Style.good, in: Capsule())
                    }
                    Text(s.time > 0 ? placeLabel(s.place) : "—")
                        .font(Style.headline(26))
                        .foregroundStyle(s.time > 0 && s.place <= 3 ? Style.gold : .white.opacity(0.8))
                }
                Text(s.time > 0 ? String(format: "%.2f", s.time) : "DNF")
                    .font(Style.mono(64, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.top, -12)

                VStack(alignment: .trailing, spacing: 5) {
                    statRow("REACTION", String(format: "%.3f", s.reaction),
                            tag: s.reaction < 0.16 ? "SHARP" : (s.reaction < 0.24 ? "OK" : "SLOW"),
                            good: s.reaction < 0.2)
                    if let split = s.split50 {
                        statRow("50M SPLIT", String(format: "%.2f", split), tag: nil, good: true)
                    }
                    statRow("TOP SPEED", String(format: "%.1f m/s", s.topSpeed), tag: nil, good: true)
                    if s.leanCredit > 0.001 {
                        statRow("LEAN", String(format: "−%.3f", s.leanCredit), tag: "DIP", good: true)
                    }
                    if s.burn > 0.01 {
                        statRow("BURN", String(format: "%.0f%%", s.burn * 100),
                                tag: s.burn > 0.85 ? "HOT" : (s.burn < 0.4 ? "TIMID" : "GOOD"),
                                good: s.burn >= 0.4 && s.burn <= 0.85)
                    }
                    if let pb = s.previousPB, !s.isNewPB {
                        statRow("YOUR BEST", String(format: "%.2f", pb), tag: nil, good: true)
                    }
                }

                HStack(spacing: 12) {
                    Button { game.backToMenu() } label: {
                        Text("MENU")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button { game.runAgain() } label: {
                        Text("RUN AGAIN")
                            .font(Style.headline(22))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 26).padding(.vertical, 10)
                            .background(Style.gold, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(18)
        .background(Style.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
    }

    private func statRow(_ label: String, _ value: String, tag: String?, good: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(Style.mono(14)).foregroundStyle(.white)
            if let tag {
                Text(tag)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(good ? Style.good : Style.bad)
            }
        }
    }

    private func placeLabel(_ p: Int) -> String {
        switch p {
        case 1: return "1ST 🏆"
        case 2: return "2ND"
        case 3: return "3RD"
        default: return "\(p)TH"
        }
    }
}
