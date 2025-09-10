//
//  ContentView.swift
//  Aura
//  Created on 9/8/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var isAppearing = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Beautiful gradient background
                LinearGradient(
                    stops: [
                        .init(color: Color(.systemBackground), location: 0.0),
                        .init(color: Color(.systemGray6).opacity(0.3), location: 0.3),
                        .init(color: auraAccentColor.opacity(0.1), location: 0.7),
                        .init(color: auraAccentColor.opacity(0.05), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Navigation Header
                    AuraNavigationHeader(
                        isListening: viewModel.isListening,
                        analysisText: viewModel.lastAnalysis,
                        onClear: { viewModel.clearMessages() },
                        onTestAI: { viewModel.sendTestPrompt() },
                        showDebug: viewModel.debugMode
                    )
                    
                    // Chat messages area with glass effect
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // Welcome message area (if no messages)
                                if viewModel.messages.isEmpty {
                                    AuraWelcomeCard()
                                        .padding(.horizontal, 20)
                                        .padding(.top, 30)
                                }
                                
                                ForEach(viewModel.messages) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                                
                                // Extra bottom padding for recording area
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 200)
                            }
                            .padding(.vertical, 12)
                        }
                        .onChange(of: viewModel.messages.count) { _ in
                            if let lastMessage = viewModel.messages.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Premium recording interface
                    AuraRecordingInterface(
                        viewModel: viewModel,
                        screenWidth: geometry.size.width
                    )
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAppearing = true
            }
        }
        .opacity(isAppearing ? 1.0 : 0.0)
    }
    
    // Aura brand colors
    private var auraAccentColor: Color {
        Color(red: 0.4, green: 0.2, blue: 0.8) // Deep purple for Aura theme
    }
}

// MARK: - Aura Navigation Header
struct AuraNavigationHeader: View {
    let isListening: Bool
    let analysisText: String
    let onClear: () -> Void
    var onTestAI: (() -> Void)? = nil
    var showDebug: Bool = false
    
    var body: some View {
        HStack {
            // Aura logo/title with breathing animation
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.3, blue: 0.9),
                                Color(red: 0.3, green: 0.1, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .scaleEffect(isListening ? 1.1 : 1.0)
                    .animation(
                        isListening ? 
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : 
                        .spring(),
                        value: isListening
                    )
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                
                Text("Aura")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            Spacer()
            
            // Emotional Analysis Display
            if !analysisText.isEmpty {
                Text(analysisText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .transition(.opacity.combined(with: .scale))
            }

            // Debug button (if enabled)
            if showDebug, let onTestAI = onTestAI {
                Button(action: onTestAI) {
                    Text("Test AI")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.7))
                        )
                }
                .transition(.opacity)
            }

            // Clear button with glass effect
            Button(action: onClear) {
                Text("Clear")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .animation(.easeInOut, value: analysisText)
    }
}

// MARK: - Aura Welcome Card
struct AuraWelcomeCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated Aura symbol
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.3),
                                    Color(red: 0.6, green: 0.4, blue: 0.9).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 100 + CGFloat(index * 20))
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                        .opacity(isAnimating ? 0.3 : 0.7)
                        .animation(
                            .easeInOut(duration: 2.0 + Double(index) * 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
                
                // Center icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.3, blue: 0.9),
                                Color(red: 0.3, green: 0.1, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.white)
                    }
            }
            
            VStack(spacing: 12) {
                Text("Hello, I'm Aura ✨")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text("Your AI life coach is here to listen continuously. I'll automatically start listening and respond to your thoughts and feelings every minute or when you pause. Just speak naturally!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            // Subtle hint
            HStack(spacing: 4) {
                Image(systemName: "ear.and.waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Always listening")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Aura Continuous Listening Interface
struct AuraRecordingInterface: View {
    @ObservedObject var viewModel: ChatViewModel
    let screenWidth: CGFloat
    @State private var pulseScale: CGFloat = 1.0
    @State private var breathingScale: CGFloat = 1.0
    @State private var debugText: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Status text with enhanced information
            VStack(spacing: 8) {
                Text(viewModel.appState.displayText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.primary,
                                Color.primary.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
                
                // Show context info when listening
                if viewModel.isListening {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "message")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.messages.count) msgs")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.getApiContextSize() > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "brain")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.getApiContextSize()) context")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 32)
            
            // Accumulated text preview
            if !viewModel.accumulatedText.isEmpty {
                ScrollView {
                    Text("\"\(viewModel.accumulatedText)\"")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(auraColor.opacity(0.2), lineWidth: 1)
                                }
                        }
                }
                .frame(maxHeight: 100)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Latest Analysis Result
            if !viewModel.lastAnalysis.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(auraColor)
                        Text("Theta Edge Analysis")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(auraColor)
                        Spacer()
                        if viewModel.isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    ScrollView {
                        Text(viewModel.lastAnalysis)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                    
                    if let recentAnalysis = viewModel.mostRecentAnalysis {
                        HStack {
                            if let emotionalTone = recentAnalysis.emotionalTone {
                                Label(emotionalTone, systemImage: "heart")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(recentAnalysis.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(auraColor.opacity(0.2), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Live partial + diagnostics (always show when listening for visibility)
            if viewModel.isListening {
                VStack(alignment: .leading, spacing: 6) {
                    if !viewModel.livePartial.isEmpty {
                        Text(viewModel.livePartial)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("(no partial yet)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        Label("acc \(viewModel.accumulatedText.count)", systemImage: "square.stack.3d.up")
                            .font(.caption2)
                        Label("partial \(viewModel.livePartial.count)", systemImage: "waveform")
                            .font(.caption2)
                        if !viewModel.lastSentUserAccumulation.isEmpty {
                            Label("sent \(viewModel.lastSentUserAccumulation.count)c", systemImage: "paperplane")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)
                    
                    // Theta Edge Analysis Status
                    HStack(spacing: 12) {
                        Label("analysis: \(viewModel.isAnalyzing ? "running" : "ready")", 
                              systemImage: viewModel.isAnalyzing ? "brain.head.profile" : "brain")
                            .font(.caption2)
                            .foregroundColor(viewModel.isAnalyzing ? .orange : .green)
                        
                        if viewModel.analysisHistory.count > 0 {
                            Label("\(viewModel.analysisHistory.count) analyses", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !viewModel.lastSentUserAccumulation.isEmpty {
                        Text("Last sent: \(String(viewModel.lastSentUserAccumulation.prefix(80)))\(viewModel.lastSentUserAccumulation.count > 80 ? "…" : "")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(auraColor.opacity(0.15), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
            
            // Timer countdown
            if viewModel.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundColor(auraColor)
                    Text("Next send: \(Int(viewModel.timeUntilNextSend))s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(auraColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(auraColor.opacity(0.1))
                        .overlay {
                            Capsule()
                                .stroke(auraColor.opacity(0.3), lineWidth: 1)
                        }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Continuous listening button
            ZStack {
                // Breathing background effect
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                auraColor.opacity(0.1),
                                auraColor.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 50,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(breathingScale)
                    .animation(
                        .easeInOut(duration: 3.0)
                        .repeatForever(autoreverses: true),
                        value: breathingScale
                    )
                
                // Pulse rings when listening
                if viewModel.isListening {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                auraColor.opacity(0.3 - Double(index) * 0.1),
                                lineWidth: 2
                            )
                            .frame(width: 120 + CGFloat(index * 30))
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - pulseScale)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                                value: pulseScale
                            )
                    }
                }
                
                // Main button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        viewModel.toggleContinuousListening()
                    }
                }) {
                    ZStack {
                        // Glass background
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay {
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.clear,
                                                auraColor.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            }
                        
                        // Inner gradient circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: viewModel.isListening ? 
                                    [Color.green, Color.green.opacity(0.8)] :
                                    [auraColor, auraColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .scaleEffect(viewModel.isListening ? 0.9 : 1.0)
                        
                        // Icon with better styling - shows continuous listening state
                        Group {
                            if viewModel.isListening {
                                Image(systemName: "waveform")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .scaleEffect(1.1)
                            } else {
                                Image(systemName: "ear.and.waveform")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .scaleEffect(1.0)
                            }
                        }
                    }
                }
                .disabled(viewModel.appState == .processing)
                .scaleEffect(viewModel.appState == .processing ? 0.95 : 1.0)
                .opacity(viewModel.appState == .processing ? 0.7 : 1.0)
            }
            .onAppear {
                breathingScale = 1.05
                if viewModel.isListening {
                    pulseScale = 2.0
                }
            }
            .onChange(of: viewModel.isListening) { isListening in
                if isListening {
                    pulseScale = 2.0
                } else {
                    pulseScale = 1.0
                }
            }
            
            // Enhanced recording level indicator
            if viewModel.isListening {
                AuraWaveformView(level: viewModel.recordingLevel)
                    .frame(height: 50)
                    .padding(.horizontal, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Privacy and recording hint
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.caption2)
                        .foregroundColor(auraColor.opacity(0.7))
                    
                    Text(viewModel.isListening ? "Continuous listening active" : "Tap to start continuous listening")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isListening && viewModel.timeUntilNextApiRequest > 0 {
                    Text("Next API request in \(Int(viewModel.timeUntilNextApiRequest))s")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 8)
            
            // Debug controls
            if viewModel.debugMode {
                HStack {
                    TextField("Append text...", text: $debugText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Append") {
                        viewModel.appendText(debugText)
                        debugText = ""
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [Color.clear, Color.black, Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
    
    private var auraColor: Color {
        Color(red: 0.4, green: 0.2, blue: 0.8)
    }
}

// MARK: - Aura Waveform View
struct AuraWaveformView: View {
    let level: Float
    @State private var animationValues: [CGFloat] = Array(repeating: 0.1, count: 20)
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9),
                                Color(red: 0.5, green: 0.4, blue: 1.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3)
                    .frame(height: max(4, animationValues[index] * 50))
                    .animation(
                        .easeInOut(duration: 0.1 + Double(index) * 0.02),
                        value: animationValues[index]
                    )
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateWaveform()
        }
    }
    
    private func updateWaveform() {
        let baseLevel = CGFloat(level)
        for i in 0..<animationValues.count {
            let randomVariation = CGFloat.random(in: 0.5...1.5)
            let newValue = (baseLevel * randomVariation + animationValues[i]) / 2
            animationValues[i] = max(0.1, min(1.0, newValue))
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}