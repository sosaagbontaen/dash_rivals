import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameController()

    var body: some View {
        ZStack {
            RaceHostView(controller: game)
                .ignoresSafeArea()

            switch game.uiPhase {
            case .menu:
                MenuOverlay(game: game)
            case .intro:
                IntroOverlay(game: game)
            case .marks:
                MarksSetOverlay(game: game, isSet: false)
            case .set:
                MarksSetOverlay(game: game, isSet: true)
            case .racing:
                RaceHUD(game: game)
            case .finished:
                ZStack {
                    RaceHUD(game: game)
                    FinishOverlay(game: game)
                }
            case .results:
                ResultsOverlay(game: game)
            }

            // Gun / finish-line white flashes
            Color.white
                .opacity(game.gunFlash ? 0.55 : (game.finishFlash ? 0.75 : 0))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.18), value: game.gunFlash)
                .animation(.easeOut(duration: 0.22), value: game.finishFlash)
        }
        .persistentSystemOverlays(.hidden)
    }
}
