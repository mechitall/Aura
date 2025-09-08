# Aura - AI Life Coach iOS App

**Aura** is a production-ready, native iOS application built with SwiftUI that provides AI-powered life coaching through voice interaction. The app uses your device's microphone to listen to your thoughts and provides empathetic, CBT-based responses through the Theta EdgeCloud API.

## 🎯 Features

- **Voice-to-Text**: Real-time speech transcription using Whisper API
- **AI Life Coach**: Thoughtful responses from Llama-3-8B-Instruct model
- **SwiftUI Interface**: Modern, native iOS user experience
- **MVVM Architecture**: Clean, maintainable code structure
- **Audio Processing**: Professional-grade audio capture and processing
- **Privacy-Focused**: Audio is processed securely and not stored permanently

## 🏗️ Architecture

The app follows a strict MVVM (Model-View-ViewModel) pattern:

- **Models**: `ChatMessage.swift` - Data structures
- **Views**: `ContentView.swift`, `ChatBubbleView.swift` - SwiftUI interfaces
- **ViewModels**: `ChatViewModel.swift` - State management and business logic
- **Services**: `ThetaAPIService.swift`, `AudioService.swift` - External integrations

## 🚀 Quick Start

### Prerequisites

- Xcode 15.0 or later
- iOS 16.0+ target device or simulator
- Theta EdgeCloud API key
- Valid Apple Developer account (for device testing)

### Setup Instructions

1. **Open in Xcode**:
   ```bash
   cd /Users/neo/AIcoach/Aura
   open Aura.xcodeproj
   ```

2. **Configure API Key** (Choose one method):
   
   **Method A: Using Config.plist (Recommended for iOS)**
   - Copy `Config-template.plist` to `Config.plist`
   - Replace `YOUR_THETA_API_KEY_HERE` with your actual Theta EdgeCloud API key
   - Add `Config.plist` to your Xcode project if not already included
   
   **Method B: Using Environment Variables**
   - Copy `.env.template` to `.env`
   - Replace `YOUR_THETA_API_KEY_HERE` with your actual API key
   
   **Note**: Both `Config.plist` and `.env` are in `.gitignore` for security

3. **Update Bundle Identifier**:
   - Select the project in Xcode Navigator
   - Under "Signing & Capabilities", change the bundle identifier
   - Ensure your development team is selected

4. **Build and Run**:
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

### First Launch

1. The app will request microphone permission - **Grant this for the app to function**
2. Tap the microphone button to start your first conversation with Aura
3. Speak naturally - the app will detect silence and auto-stop recording
4. Wait for Aura's thoughtful response

## 💬 How to Use

1. **Start Conversation**: Tap the blue microphone button
2. **Speak Freely**: Share your thoughts, feelings, or concerns
3. **Auto-Stop**: The app detects 4 seconds of silence and stops recording
4. **Manual Stop**: Tap the red stop button to end recording early
5. **AI Response**: Aura provides empathetic, CBT-based guidance
6. **Continue**: The conversation flows naturally - just tap to speak again

## 🔧 Technical Details

### Audio Processing
- **Format**: 16kHz, 16-bit, Mono PCM
- **Framework**: AVFoundation AVAudioEngine
- **Conversion**: Automatic PCM to WAV conversion for Whisper API
- **Real-time**: Live audio level monitoring and silence detection

### API Integration
- **Whisper**: Speech-to-text transcription
- **Llama-3**: AI responses with CBT-focused system prompt
- **Async/Await**: Modern Swift concurrency for all network calls
- **Error Handling**: Comprehensive error management and user feedback

### SwiftUI Features
- **Animations**: Smooth pulsing microphone button during recording
- **Auto-scroll**: Chat automatically scrolls to latest messages
- **Dark Mode**: Full support for iOS dark/light mode
- **Accessibility**: Voice Over and accessibility features supported

## 🛡️ Privacy & Security

- **Microphone**: Only accessed when explicitly recording
- **Audio Data**: Converted and sent to API, not stored locally
- **API Communication**: HTTPS encryption for all network requests
- **Permissions**: Explicit user consent required for microphone access

## 🔧 Customization

### Modify AI Behavior
Edit the system prompt in `ThetaAPIService.swift`:
```swift
private let systemPrompt = """
Your custom AI personality and instructions here...
"""
```

### Adjust Audio Settings
Modify recording parameters in `AudioService.swift`:
```swift
private let sampleRate: Double = 16000 // Change sample rate
private let silenceTimeout: TimeInterval = 4.0 // Change silence detection
```

### Customize UI
- Edit colors and styling in `ContentView.swift` and `ChatBubbleView.swift`
- Modify animations and transitions
- Add new UI components

## 📱 Testing

### iOS Simulator
- Limited microphone testing capability
- Use for UI and basic flow testing
- No real audio processing possible

### Physical Device
- **Recommended** for full functionality testing
- Real microphone input and audio processing
- Complete user experience validation

## 🐛 Troubleshooting

### Common Issues

**"Microphone permission denied"**:
- Go to Settings > Privacy & Security > Microphone > Aura > Enable

**"API Error"**:
- Verify your Theta EdgeCloud API key is correct
- Check internet connection
- Ensure API endpoints are accessible

**"Audio not recording"**:
- Test microphone with other apps
- Restart the app
- Check device audio settings

### Debug Mode
Enable detailed logging by adding debug prints in:
- `AudioService.swift` - Audio processing events
- `ThetaAPIService.swift` - API request/response logging
- `ChatViewModel.swift` - State changes and flow

## 🚀 Deployment

### App Store Preparation
1. Configure proper app icons and launch screens
2. Add App Store metadata and screenshots
3. Ensure all privacy descriptions are accurate
4. Test thoroughly on multiple devices and iOS versions
5. Follow Apple's App Store Review Guidelines

### API Key Security
**Important**: For production deployment:
- Never commit API keys to version control
- Use Xcode build configurations or secure key management
- Consider server-side API proxy for additional security

## 📝 File Structure

```
Aura/
├── Aura.xcodeproj/           # Xcode project file
├── Aura/
│   ├── AuraApp.swift          # Main app entry point
│   ├── ContentView.swift      # Main interface
│   ├── ChatBubbleView.swift   # Individual message display
│   ├── ChatMessage.swift      # Message data model
│   ├── ChatViewModel.swift    # State management
│   ├── ThetaAPIService.swift  # API integration
│   ├── AudioService.swift     # Audio processing
│   ├── Info.plist            # App configuration
│   └── Preview Content/       # SwiftUI previews
└── README.md                 # This file
```

## 🤝 Contributing

This is a complete, production-ready codebase. Key areas for enhancement:
- Additional AI models and providers
- Enhanced audio processing (noise reduction, etc.)
- Conversation history persistence
- User customization options
- Advanced CBT features and exercises

---

**Aura** demonstrates professional iOS development practices with real-world API integration, proper architecture, and production-ready code quality. The app provides a foundation for AI-powered therapeutic applications while maintaining user privacy and delivering excellent user experience.