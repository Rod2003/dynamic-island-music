import SoundwaveAudio
import SoundwaveConfig
import SoundwaveNowPlaying
import SwiftUI

struct IslandView: View {
    let nowPlaying: NowPlaying
    let tap: AudioTap
    let notchWidth: CGFloat
    let height: CGFloat

    private typealias C = Constants.Island

    var body: some View {
        let icon = height - 2 * C.inset
        HStack(spacing: 0) {
            AsyncImage(url: nowPlaying.artworkURL) {
                $0.resizable().clipShape(RoundedRectangle(cornerRadius: icon * 185.4 / 1024, style: .continuous)).padding(icon * 100 / 1024)
            } placeholder: {
                if let icon = nowPlaying.icon { Image(nsImage: icon).resizable() }
            }
                .padding(C.inset)
                .frame(width: height)
            Spacer().frame(width: notchWidth)
            Bars(tap: tap)
                .padding(C.inset)
                .frame(width: height)
        }
        .padding(.horizontal, C.flare)
        .frame(height: height)
        .background(.black, in: NotchShape())
        .opacity(nowPlaying.isPlaying ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: nowPlaying.isPlaying)
    }
}
