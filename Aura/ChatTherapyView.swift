import SwiftUI

struct ChatTherapyView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var inputText: String = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesScroll
            composer
                .background(.ultraThinMaterial)
        }
        .background(LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.9)], startPoint: .top, endPoint: .bottom))
        .onChange(of: viewModel.therapyMessages.count) { _ in
            scrollToBottom(animated: true)
        }
        .onAppear { scrollToBottom(animated: false) }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.8))
                Text("Reflective Chat")
                    .font(.headline)
                Spacer()
                if viewModel.isTherapyLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .transition(.opacity)
                }
            }
            Text("Ask anything that's on your mind. I'll guide you with curious, supportive questions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.therapyMessages.isEmpty {
                        EmptyTherapyPlaceholder()
                            .padding(.top, 60)
                    }
                    ForEach(viewModel.therapyMessages) { msg in
                        ChatBubbleView(message: msg)
                            .id(msg.id)
                    }
                    if viewModel.isTherapyLoading {
                        HStack {
                            AuraTypingIndicator()
                                .padding(.leading, 20)
                            Spacer()
                        }
                    }
                    Color.clear.frame(height: 40).id("BOTTOM")
                }
                .padding(.top, 8)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: viewModel.isTherapyLoading) { _ in scrollToBottom(animated: true) }
        }
    }
    
    private var composer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Share what's coming up for you...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.secondarySystemBackground))
                    )
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(
                            Circle().fill(LinearGradient(colors: [Color(red:0.4,green:0.2,blue:0.8), Color(red:0.55,green:0.3,blue:0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTherapyLoading)
                .opacity(viewModel.isTherapyLoading ? 0.6 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private func send() {
        let text = inputText
        inputText = ""
        viewModel.sendTherapyMessage(text)
        scrollToBottom(animated: true)
    }
    
    private func scrollToBottom(animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(animated ? .easeOut(duration: 0.35) : nil) {
                scrollProxy?.scrollTo("BOTTOM", anchor: .bottom)
            }
        }
    }
}

// Typing indicator
struct AuraTypingIndicator: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color(red:0.4,green:0.2,blue:0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(1 + 0.25 * sin(phase + CGFloat(i) * 0.9))
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .onAppear { phase = .pi / 2 }
    }
}

struct EmptyTherapyPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 42))
                .foregroundColor(Color(red:0.4,green:0.2,blue:0.8).opacity(0.6))
            Text("Start a reflective chat")
                .font(.title3).fontWeight(.semibold)
            Text("Share what's on your mind—I'll help you unpack it with gentle, curious questions.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 320)
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial))
        .padding(.horizontal, 32)
    }
}
