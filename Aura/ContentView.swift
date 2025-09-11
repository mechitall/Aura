//
//  ContentView.swift
//  Aura
//  Created on 9/8/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var isAppearing = false
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CleanAuraView(viewModel: viewModel)
                .tag(0)
                .tabItem {
                    Label("My Aura", systemImage: "waveform.circle")
                }
            ChatTherapyView(viewModel: viewModel)
                .tag(1)
                .tabItem {
                    Label("Chat", systemImage: "text.bubble")
                }
            DebugView(viewModel: viewModel, auraAccentColor: auraAccentColor)
                .tag(2)
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
            DailyAnalysisView(viewModel: viewModel)
                .tag(3)
                .tabItem {
                    Label("Daily", systemImage: "chart.bar.doc.horizontal")
                }
            SettingsView(viewModel: viewModel)
                .tag(4)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
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

// MARK: - Clean Aura Tab
struct CleanAuraView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var pulseScale: CGFloat = 1.0
    @State private var breathingScale: CGFloat = 1.0
    @State private var showingTutorial: Bool = false
    
    private var auraColor: Color { Color(red: 0.4, green: 0.2, blue: 0.8) }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        auraColor.opacity(0.08),
                        auraColor.opacity(0.04)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    // Emotional State (always displayed)
                    let analysis = viewModel.currentAnalysis
                    VStack(spacing: 4) {
                        Text(analysis.emoji)
                            .font(.system(size: 80))
                            .transition(.scale.combined(with: .opacity))
                        Text(analysis.emotion)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .transition(.opacity)
                        EmotionalTrendGraph(points: viewModel.emotionalTrend)
                            .frame(height: 60)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                    
                    // Main listening control with rings
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [auraColor.opacity(0.15), auraColor.opacity(0.05), Color.clear]),
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 150
                                )
                            )
                            .frame(width: 320, height: 320)
                            .scaleEffect(breathingScale)
                            .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: breathingScale)
                        if viewModel.isListening {
                            ForEach(0..<3) { index in
                                Circle()
                                    .stroke(auraColor.opacity(0.35 - Double(index) * 0.1), lineWidth: 2)
                                    .frame(width: 140 + CGFloat(index * 40))
                                    .scaleEffect(pulseScale)
                                    .opacity(2.0 - pulseScale)
                                    .animation(
                                        .easeOut(duration: 1.6)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(index) * 0.25),
                                        value: pulseScale
                                    )
                            }
                        }
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { viewModel.toggleContinuousListening() }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Circle().stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.4), Color.clear, auraColor.opacity(0.25)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                    )
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: viewModel.isListening ? [Color.green, Color.green.opacity(0.85)] : [auraColor, auraColor.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 90, height: 90)
                                    .scaleEffect(viewModel.isListening ? 0.9 : 1.0)
                                Image(systemName: viewModel.isListening ? "waveform" : "ear.and.waveform")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(viewModel.appState == .processing)
                        .scaleEffect(viewModel.appState == .processing ? 0.95 : 1.0)
                        .opacity(viewModel.appState == .processing ? 0.7 : 1.0)
                    }
                    .onAppear { setupAnimations() }
                    .onChange(of: viewModel.isListening) { _ in updatePulse() }
                    
                    Text(viewModel.isListening ? "Aura is listening continuously" : "Tap to start continuous listening")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Help button overlay
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showingTutorial = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(radius: 2, y: 1)
                        }
                        .accessibilityLabel("Open Aura tutorial")
                        .padding([.top, .trailing], 18)
                    }
                    Spacer()
                }
            }
            .sheet(isPresented: $showingTutorial) { TutorialCarouselView(isPresented: $showingTutorial) }
        }
    }
    
    private func setupAnimations() {
        breathingScale = 1.05
        updatePulse()
    }
    private func updatePulse() {
        pulseScale = viewModel.isListening ? 2.0 : 1.0
    }
}

// MARK: - Debug Tab Wrapper (original complex UI)
struct DebugView: View {
    @ObservedObject var viewModel: ChatViewModel
    var auraAccentColor: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                    AuraNavigationHeader(
                        isListening: viewModel.isListening,
                        onClear: { viewModel.clearMessages() },
                        onTestAI: { viewModel.sendTestPrompt() },
                        onEmotionalAnalysis: { viewModel.triggerAnalysisNow() },
                        showDebug: viewModel.debugMode
                    )
                    let analysis = viewModel.currentAnalysis
                    VStack {
                        Text(analysis.emoji)
                            .font(.system(size: 60))
                        Text(analysis.emotion)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        EmotionalTrendGraph(points: viewModel.emotionalTrend)
                            .frame(height: 50)
                            .padding(.top, 6)
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(20)
                    .transition(.opacity.combined(with: .scale))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
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
                    AuraRecordingInterface(
                        viewModel: viewModel,
                        screenWidth: geometry.size.width
                    )
                }
            }
        }
    }
}

// MARK: - Aura Navigation Header
struct AuraNavigationHeader: View {
    let isListening: Bool
    let onClear: () -> Void
    var onTestAI: (() -> Void)? = nil
    var onEmotionalAnalysis: (() -> Void)? = nil
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

            // Test AI button and Emotional analysis button
            if let onTestAI = onTestAI {
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

                // Manual Emotional Analysis trigger (always visible)
                if let onEmotional = onEmotionalAnalysis {
                    Button(action: onEmotional) {
                        Text("Emotional")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.85))
                            )
                    }
                    .transition(.opacity)
                }
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
    // Removed invalid dependency on undefined 'analysisText'; animate on listening state instead
    .animation(.easeInOut, value: isListening)
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
    @State private var manualText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            debugControls
            statusSection
            accumulatedTextSection
            latestAnalysisSection
            diagnosticsSection
            timerSection
            listeningButton
            waveformSection
            privacyHintSection
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

    // MARK: - Subviews
    @ViewBuilder private var debugControls: some View {
        if viewModel.debugMode {
            HStack {
                TextField("Append text for testing...", text: $manualText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .onSubmit { commitManualText() }
                Button("Append") { commitManualText() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.purple.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(manualText.isEmpty)
            }
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var statusSection: some View {
        VStack(spacing: 8) {
            Text(viewModel.appState.displayText)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.primary, Color.primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
            if viewModel.isListening { listeningContextInfo }
        }
        .padding(.horizontal, 32)
    }

    private var listeningContextInfo: some View {
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

    @ViewBuilder private var accumulatedTextSection: some View {
        if !viewModel.accumulatedText.isEmpty {
            ScrollView {
                Text("\"\(viewModel.accumulatedText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(auraColor.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .frame(maxHeight: 100)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var latestAnalysisSection: some View {
        if let analysis = viewModel.lastAnalysis {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain.head.profile").foregroundColor(auraColor)
                    Text("Emotional Analysis")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(auraColor)
                    Spacer()
                }
                HStack {
                    Text(analysis.emoji).font(.title2)
                    Text(analysis.emotion)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(auraColor.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder private var diagnosticsSection: some View {
        if viewModel.isListening {
            VStack(alignment: .leading, spacing: 6) {
                livePartialText
                diagnosticsCounters
                analysisStatus
                lastSentPreview
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(auraColor.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .transition(.opacity)
        }
    }

    private var livePartialText: some View {
        Group {
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
        }
    }

    private var diagnosticsCounters: some View {
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
    }

    private var analysisStatus: some View {
        HStack(spacing: 12) {
            Label("analysis: \(viewModel.isAnalyzing ? "running" : "ready")", systemImage: viewModel.isAnalyzing ? "brain.head.profile" : "brain")
                .font(.caption2)
                .foregroundColor(viewModel.isAnalyzing ? .orange : .green)
            // Removed analysisHistory references causing compile error
            // Removed analysisHistory references causing compile error
            // if viewModel.analysisHistory.count > 0 {
            //     Label("\(viewModel.analysisHistory.count) analyses", systemImage: "chart.line.uptrend.xyaxis")
            //         .font(.caption2)
            //         .foregroundColor(.secondary)
            // }
        }
    }

    private var lastSentPreview: some View {
        Group {
            if !viewModel.lastSentUserAccumulation.isEmpty {
                Text("Last sent: \(String(viewModel.lastSentUserAccumulation.prefix(80)))\(viewModel.lastSentUserAccumulation.count > 80 ? "…" : "")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private var timerSection: some View {
        if viewModel.isListening {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundColor(auraColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next send: \(Int(viewModel.timeUntilNextSend))s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(auraColor)
                    Text("Next emotion: \(Int(viewModel.timeUntilNextEmotionalAnalysis))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(auraColor.opacity(0.1))
                    .overlay(
                        Capsule().stroke(auraColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var listeningButton: some View {
        ZStack {
            breathingBackground
            pulseRings
            mainToggleButton
        }
        .onAppear { setupAnimations() }
        .onChange(of: viewModel.isListening) { updatePulse(for: $0) }
    }

    private var breathingBackground: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [auraColor.opacity(0.1), auraColor.opacity(0.05), Color.clear]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 150
                )
            )
            .frame(width: 300, height: 300)
            .scaleEffect(breathingScale)
            .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: breathingScale)
    }

    @ViewBuilder private var pulseRings: some View {
        if viewModel.isListening {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(auraColor.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
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
    }

    private var mainToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { viewModel.toggleContinuousListening() }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear, auraColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                    )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: viewModel.isListening ? [Color.green, Color.green.opacity(0.8)] : [auraColor, auraColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(viewModel.isListening ? 0.9 : 1.0)
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

    @ViewBuilder private var waveformSection: some View {
        if viewModel.isListening {
            AuraWaveformView(level: viewModel.recordingLevel)
                .frame(height: 50)
                .padding(.horizontal, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var privacyHintSection: some View {
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
    }

    // MARK: - Helpers
    private func commitManualText() {
        guard !manualText.isEmpty else { return }
        viewModel.appendText(manualText)
        manualText = ""
    }

    private func setupAnimations() {
        breathingScale = 1.05
        if viewModel.isListening { pulseScale = 2.0 }
    }

    private func updatePulse(for listening: Bool) {
        pulseScale = listening ? 2.0 : 1.0
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

// MARK: - Emotional Trend Bar
struct EmotionalTrendBar: View {
    let points: [ChatViewModel.EmotionalPoint]
    
    private func color(for score: Double) -> Color {
        switch score {
        case let x where x >= 0.7: return .green
        case 0.3..<0.7: return .mint
        case 0.05..<0.3: return .teal
        case -0.2..<0.05: return .gray
        case -0.5 ..< -0.2: return .orange
        case -0.8 ..< -0.5: return .red
        default: return .purple
        }
    }
    
    private func height(for score: Double, in total: CGFloat) -> CGFloat {
        // Map -1...+1 to 0...1 then scale by total
        let normalized = (score + 1.0) / 2.0
        return max(4, normalized * total)
    }
    
    var body: some View {
        GeometryReader { geo in
            let barWidth = max(2, geo.size.width / CGFloat(max(points.count, 1)))
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(points) { point in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: point.score).opacity(0.25))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: point.score))
                                .frame(height: height(for: point.score, in: geo.size.height - 16))
                        }
                        .frame(width: barWidth, height: geo.size.height - 20)
                        Text(point.emoji)
                            .font(.system(size: 10))
                            .frame(height: 14)
                    }
                    .accessibilityLabel("Emotion \(point.emotion)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeInOut(duration: 0.4), value: points.count)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Emotional Trend Graph (Strava-like)
struct EmotionalTrendGraph: View {
    let points: [ChatViewModel.EmotionalPoint]
    private let horizontalInset: CGFloat = 14
    private let topMargin: CGFloat = 4 // reduced since emojis now outside chart
    private let emojiRowHeight: CGFloat = 24
    private let emojiSpacing: CGFloat = 4
    
    private func path(for size: CGSize) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        let midY = size.height / 2
        let amplitude = midY - topMargin
        let stepX = (size.width - 2 * horizontalInset) / CGFloat(max(points.count - 1, 1))
        path.move(to: CGPoint(x: horizontalInset, y: midY))
        for (idx, p) in points.enumerated() {
            let x = horizontalInset + CGFloat(idx) * stepX
            let y = midY - CGFloat(p.score) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: horizontalInset + CGFloat(max(points.count - 1, 0)) * stepX, y: midY))
        return path
    }
    
    private func fillPath(for size: CGSize) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        let midY = size.height / 2
        let amplitude = midY - topMargin
        let stepX = (size.width - 2 * horizontalInset) / CGFloat(max(points.count - 1, 1))
        path.move(to: CGPoint(x: horizontalInset, y: midY))
        for (idx, p) in points.enumerated() {
            let x = horizontalInset + CGFloat(idx) * stepX
            let y = midY - CGFloat(p.score) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: horizontalInset + CGFloat(max(points.count - 1, 0)) * stepX, y: midY))
        path.closeSubpath()
        return path
    }
    
    private func color(for score: Double) -> Color {
        switch score {
        case let x where x >= 0.7: return .green
        case 0.3..<0.7: return .mint
        case 0.05..<0.3: return .teal
        case -0.2..<0.05: return .gray
        case -0.5 ..< -0.2: return .orange
        case -0.8 ..< -0.5: return .red
        default: return .purple
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalSize = geo.size
            // Allocate remaining height to chart after emoji row + spacing
            let chartHeight = max(10, totalSize.height - emojiRowHeight - emojiSpacing)
            let chartSize = CGSize(width: totalSize.width, height: chartHeight)
            VStack(spacing: emojiSpacing) {
                EmotionalTrendEmojiRow(points: points, horizontalInset: horizontalInset)
                    .frame(height: emojiRowHeight)
                    .animation(Animation.easeInOut(duration: 0.5), value: points.count)
                EmotionalTrendGraphBody(
                    size: chartSize,
                    points: points,
                    path: path(for: chartSize),
                    areaPath: fillPath(for: chartSize),
                    colorProvider: color,
                    horizontalInset: horizontalInset,
                    topMargin: topMargin
                )
                .frame(height: chartHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .animation(Animation.easeInOut(duration: 0.5), value: points.count)
            }
            .frame(width: totalSize.width, height: totalSize.height, alignment: .top)
        }
    }
}

// MARK: - Extracted Body To Assist Type Checker
private struct EmotionalTrendGraphBody: View {
    let size: CGSize
    let points: [ChatViewModel.EmotionalPoint]
    let path: Path
    let areaPath: Path
    let colorProvider: (Double) -> Color
    let horizontalInset: CGFloat
    let topMargin: CGFloat

    // Precompute gradients outside main body expression
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.red.opacity(0.25),
                Color.orange.opacity(0.2),
                Color.gray.opacity(0.15),
                Color.green.opacity(0.25)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var lineGradient: LinearGradient {
        LinearGradient(
            colors: [Color.red, Color.orange, Color.teal, Color.green],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    var body: some View {
        ZStack {
            baseline
            areaPath.fill(areaGradient)
            path.stroke(lineGradient, lineWidth: 2)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var baseline: some View {
        Path { p in
            p.move(to: CGPoint(x: horizontalInset, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width - horizontalInset, y: size.height / 2))
        }
        .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4,4]))
    }

}

// Emoji row above chart
private struct EmotionalTrendEmojiRow: View {
    let points: [ChatViewModel.EmotionalPoint]
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let stepX = (width - 2 * horizontalInset) / CGFloat(max(points.count - 1, 1))
            ZStack(alignment: .topLeading) {
                ForEach(Array(points.enumerated()), id: \.0) { (idx, p) in
                    Text(p.emoji)
                        .font(.system(size: 16))
                        .position(x: horizontalInset + CGFloat(idx) * stepX, y: 12)
                        .accessibilityLabel("Emotion \(p.emotion)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - Daily Analysis Tab
struct DailyAnalysisView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    analyzeSection
                    resultSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            .navigationTitle("Daily Analysis")
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appear = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Pattern Insights")
                .font(.title2).bold()
            Text("Run an end-of-session analysis of everything you've said so far. Aura will surface repeating themes, emotional spikes, and behavior loops.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
    }

    private var analyzeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { viewModel.analyzeDailyPatterns() }) {
                HStack(spacing: 12) {
                    if viewModel.isPatternAnalyzing {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title2)
                    }
                    Text(viewModel.isPatternAnalyzing ? "Analyzing…" : "Analyse my patterns")
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(LinearGradient(colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .foregroundColor(.white)
            }
            .disabled(viewModel.isPatternAnalyzing || (viewModel.accumulatedText.isEmpty && viewModel.livePartial.isEmpty))
            if let lastAt = viewModel.lastPatternAnalysisAt {
                Text("Last run: \(lastAt, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if viewModel.patternAnalysisError != nil {
                Text(viewModel.patternAnalysisError ?? "")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !viewModel.isPatternAnalyzing && viewModel.dailyPatterns.isEmpty {
                Text("No patterns analyzed yet. Tap the button above once you've spoken for a while.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.dailyPatterns.isEmpty {
                Text("Identified Patterns")
                    .font(.headline)
                ForEach(viewModel.dailyPatterns) { pattern in
                    patternCard(pattern)
                }
            }
        }
        .animation(.easeInOut, value: viewModel.dailyPatterns)
    }

    private func patternCard(_ pattern: ChatViewModel.DailyPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(pattern.emoji).font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.title)
                        .font(.headline)
                    Text(pattern.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !pattern.evidenceSnippet.isEmpty {
                        Text("“\(pattern.evidenceSnippet)”")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Tutorial Carousel View
struct TutorialCarouselView: View {
    @Binding var isPresented: Bool
    @State private var selection: Int = 0

    private struct Slide: Identifiable { let id = UUID(); let title: String; let subtitle: String; let image: String; let detail: String }
    private let slides: [Slide] = [
        .init(title: "Welcome to Aura", subtitle: "AI Life Coach", image: "waveform.circle", detail: "Aura listens (with permission) and periodically summarizes or responds. Just speak—no need to tap each time."),
        .init(title: "Listening", subtitle: "1‑minute windows", image: "ear.and.waveform", detail: "Speech is batched roughly every minute or after longer pauses and sent for contextual insight."),
        .init(title: "Emotions", subtitle: "30s snapshots", image: "brain.head.profile", detail: "Aura takes lightweight emotional readings to chart your mood over time."),
        .init(title: "Patterns", subtitle: "Daily insights", image: "chart.bar.doc.horizontal", detail: "Run a pattern analysis to surface triggers, loops, coping strategies, and growth signals."),
        .init(title: "Therapy Chat", subtitle: "Context aware", image: "text.bubble", detail: "Use the Chat tab to reflect—Aura has access to your recent transcript, emotions & patterns."),
        .init(title: "Privacy", subtitle: "Control & clear", image: "shield.lefthalf.filled", detail: "You can clear conversation & context anytime. Only processed text is sent to the model."),
        .init(title: "Get Started", subtitle: "You're ready", image: "hand.thumbsup", detail: "Close this guide and tap the center button if not already listening.")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $selection) {
                    ForEach(Array(slides.enumerated()), id: \.0) { idx, slide in
                        VStack(spacing: 18) {
                            Image(systemName: slide.image)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 70))
                                .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .padding(.bottom, 4)
                            Text(slide.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(slide.subtitle)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(slide.detail)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                            Spacer()
                        }
                        .padding(.horizontal, 28)
                        .tag(idx)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .animation(.easeInOut, value: selection)

                HStack(spacing: 16) {
                    Button("Close") { isPresented = false }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    if selection < slides.count - 1 {
                        Button(action: { withAnimation { selection += 1 } }) {
                            HStack { Text("Next"); Image(systemName: "chevron.right") }
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)))
                                .foregroundColor(.white)
                        }
                    } else {
                        Button(action: { isPresented = false }) {
                            HStack { Image(systemName: "play.circle.fill"); Text("Start Using Aura") }
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.top, 24)
            .navigationTitle("Guide")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isPresented = false } } }
        }
    }
}
