import SwiftUI

/// David's own growing method, with a photo of his beds grown this way.
/// Keep the wording in step with backend/persona/method.md, which is what the live coach reads.
struct DavidsMethodView: View {
    @Environment(AppModel.self) private var app

    private struct Step: Identifiable {
        let title: String
        let symbol: String
        let lines: [String]
        var id: String { title }
    }

    private let steps: [Step] = [
        Step(title: "Where to put a bed", symbol: "sun.max", lines: [
            "Location is the thing I emphasize most.",
            "Best spot: between where you park your car and where you walk into your house, so you see it up close every day.",
            "In the northern hemisphere, face the bed south.",
            "In the hot, humid South, a bit of shade from the west in the afternoon helps, if you can get it.",
            "For winter growing, as much sun as possible.",
        ]),
        Step(title: "Building a raised bed", symbol: "square.stack.3d.up", lines: [
            "5 feet wide so it doesn't dry out as fast, 2 feet tall for easy weeding, oxygen and drainage, and 10 to 12 feet long.",
            "About half silty topsoil and half aged wood chips or finished compost.",
            "As much biochar as I can get, up to about 10% of the mix at most, and a fair amount of Azomite.",
            "Extras if I've got them: fresh kitchen scraps, bones from bone broth, any green organic matter, even a piece of roadkill buried deep.",
            "None of the extras are entirely necessary.",
        ]),
        Step(title: "Starting transplants", symbol: "leaf", lines: [
            "Sow into sifted compost with a bit of Azomite and MicroLife mixed in.",
            "Foliar spray the seedlings about once a week with liquid kelp and fish hydrolysate in a small spray bottle.",
        ]),
        Step(title: "Transplanting", symbol: "hands.sparkles", lines: [
            "Mix a handful of MicroLife into each planting hole.",
            "Keep up the weekly kelp and fish spray for another 2 or 3 weeks.",
            "Give each plant extra-wide spacing so it can grow into an exemplary individual.",
        ]),
        Step(title: "Feeding", symbol: "sparkles", lines: [
            "Mostly MicroLife All Purpose granular.",
            "Lots of crushed eggshells in every bed.",
            "No rock phosphate or other particularly concentrated amendments, so nutrients stay in balance. I've never needed a soil test.",
        ]),
        Step(title: "Watering and mulch", symbol: "drop", lines: [
            "Water regularly enough that plants never wilt: nearly every day early in a plant's life, then I slack off.",
            "Mulch with aged oak leaves, but this is flexible.",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photo = UIImage(named: "DavidsBeds") {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("\(app.coachName)'s raised beds: big collards and chard with wide spacing and wood-chip paths")
                        Text("\(app.coachName)'s beds, grown this way.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .onPhoto()
                    }
                }
                Card {
                    Text("This is how I grow. Ask me about any step and I'll fit it to what you have.")
                        .font(.subheadline)
                }
                ForEach(steps) { step in
                    Card {
                        Label(step.title, systemImage: step.symbol)
                            .font(.headline)
                        ForEach(step.lines, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.tint)
                                Text(line)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(16)
        }
        .gardenBackground()
        .navigationTitle("How \(app.coachName) grows")
        .navigationBarTitleDisplayMode(.inline)
    }
}
