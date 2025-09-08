//
//  ContentView.swift
//  Aura
//
//  Created on 9/8/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var scrollProxy: ScrollViewReader?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        scrollToBottom()
                    }
                }
                
                Divider()
                
                // Control area
                VStack(spacing: 16) {
                    // Status text
                    Text(viewModel.appState.displayText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Microphone button
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            if viewModel.isRecording {
                                viewModel.stopRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        }) {
                            ZStack {
                                // Outer circle with pulse animation
                                Circle()
                                    .stroke(
                                        viewModel.isRecording ? Color.red : Color.blue,
                                        lineWidth: 3
                                    )
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                                    .opacity(viewModel.isRecording ? 0.6 : 1.0)
                                    .animation(
                                        viewModel.isRecording ?
                                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                                        .easeOut(duration: 0.3),
                                        value: viewModel.isRecording
                                    )
                                
                                // Inner circle
                                Circle()
                                    .fill(
                                        viewModel.isRecording ? Color.red : Color.blue
                                    )
                                    .frame(width: 80, height: 80)
                                
                                // Microphone icon
                                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(viewModel.appState == .processing)
                        
                        Spacer()
                    }
                    
                    // Recording level indicator
                    if viewModel.isRecording {
                        RecordingLevelView(level: viewModel.recordingLevel)
                            .frame(height: 20)
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.vertical, 20)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Aura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        viewModel.clearMessages()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Helper Methods
    private func scrollToBottom() {
        guard let lastMessage = viewModel.messages.last else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Recording Level View
struct RecordingLevelView: View {
    let level: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                
                // Level indicator
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}