import SwiftUI
import SwiftData
import GardenCore

/// Chat with the coach (David's persona). Replies can be read aloud in his cloned voice.
struct CoachView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \ChatMessage.created) private var messages: [ChatMessage]
    @Query(sort: \GardenProfile.created) private var profiles: [GardenProfile]
    @FocusState private var inputFocused: Bool
    @State private var confirmClear = false

    private static let suggestions = [
        "What should I feed my tomatoes, using what I have?",
        "Is today a good day for a foliar spray?",
        "How do I know when to water?",
        "My lower leaves are turning yellow. What's going on?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if app.isDemo {
                            Label("Demo mode: answers come from the app's built-in rules until the live coach is connected.", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if app.isSending {
                            TypingRow()
                                .id("typing")
                        }
                        if let error = app.coachError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                Button("Try again") { Task { await app.retryCoach() } }
                                    .buttonStyle(.bordered)
                            }
                            .id("error")
                        }
                        if let voiceError = app.voice.errorMessage {
                            Text(voiceError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count, initial: true) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: app.isSending) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        CoachAvatar(size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app.coachName)
                                .font(.headline)
                            Text("AI garden coach")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if app.voiceAvailable, let profile = profiles.first {
                            Toggle(isOn: Binding(
                                get: { profile.voiceEnabled },
                                set: { profile.voiceEnabled = $0; app.save() }
                            )) {
                                Label("Read replies aloud", systemImage: "speaker.wave.2")
                            }
                        }
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Clear conversation", systemImage: "trash")
                        }
                        .disabled(messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .confirmationDialog("Clear the whole conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear conversation", role: .destructive) { app.clearChat() }
            } message: {
                Text("Your journal and garden records stay as they are.")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                CoachAvatar(size: 88)
                Spacer()
            }
            Text("Ask me anything about your garden. I can see your beds, plants, journal, what you have on hand and the forecast, and I'll keep your records up to date as we talk.")
                .foregroundStyle(.secondary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    Task { await app.sendToCoach(suggestion) }
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(app.isSending)
            }
        }
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        @Bindable var app = app
        return VStack(spacing: 6) {
            if let context = app.pendingCoachContext {
                HStack(alignment: .top) {
                    Image(systemName: "bell")
                        .foregroundStyle(.tint)
                    Text(context.text)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        app.pendingCoachContext = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove nudge")
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask \(app.coachName)...", text: $app.coachDraft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button {
                    let text = app.coachDraft
                    app.coachDraft = ""
                    Task { await app.sendToCoach(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(app.isSending || app.coachDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct MessageRow: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    if let context = message.contextText {
                        Label(context, systemImage: "bell")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                CoachAvatar(size: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.markdown(message.text))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                    ForEach(message.actionLines, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if app.voiceAvailable && !message.isDemo {
                        Button {
                            Task { await app.voice.toggle(text: message.text, service: app.coach) }
                        } label: {
                            if app.voice.isLoading(message.text) {
                                ProgressView()
                            } else if app.voice.isPlaying(message.text) {
                                Label("Stop", systemImage: "stop.fill")
                            } else {
                                Label("Hear \(app.coachName)", systemImage: "play.fill")
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                Spacer(minLength: 24)
            }
        }
    }

    /// Renders the coach's light Markdown (bold, italics, lists) and keeps line breaks.
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct TypingRow: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CoachAvatar(size: 28)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
            }
            .accessibilityLabel("Writing a reply")
        }
    }
}
