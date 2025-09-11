# Aura – AI Life Coach (Continuous Speech + Emotional Intelligence)

> Real-time, privacy-conscious AI life coach that listens continuously, tracks emotional trends, and surfaces deep behavioral patterns.

## 🚀 Overview
Aura is a SwiftUI iOS application that acts as an always-on reflective companion. It continuously transcribes speech locally, periodically summarizes and analyzes what you say, extracts emotions every 30 seconds, and (on demand) performs a **Daily Pattern Analysis** to uncover repeating themes, emotional spikes, coping loops, and growth signals.

The experience is split into focused tabs:
- **My Aura** – Clean end‑user view: current emotional state + trend graph + primary listening control.
- **Daily** – One‑off full‑day behavioral / emotional pattern mining with structured JSON parsing.
- **Debug** – Rich diagnostics: raw transcript flow, timers, manual triggers, internal states.

## ✨ Core Features
| Category | Capability |
|----------|-----------|
| Continuous Listening | Automatically starts after permission; segments speech by silence & time windows |
| Adaptive Accumulation | Bundles ~1 minute of meaningful speech before AI insight request |
| AI Coaching Responses | Sends structured conversation context to Theta EdgeCloud for empathetic coaching replies |
| Emotional Snapshots | Automatic + manual emotional analysis every 30s (fallback Neutral) |
| Emotional Trend Graph | Strava‑like area graph with emoji markers (separate row) & positivity baseline |
| Daily Pattern Analysis | One‑off full transcript mining → structured patterns (title, summary, emoji, evidence) |
| Resilient Parsing | Multi‑strategy emotion & JSON pattern extraction with heuristic fallback |
| Rate Limiting & Context Mgmt | Internal cooldown + trimmed rolling message buffer |
| Accessibility & UX | Always-visible emotional state; safe fallbacks prevent empty UI |
| Debug Utilities | Test prompt injection, diagnostics logging, transcript preview, timers |

## 🧠 Product Philosophy
Aura’s goal is to reduce friction in self‑reflection:
- Passive capture → active insight (no manual journaling)  
- Lightweight emotional bio‑feedback  
- Pattern surfacing for habit change  
- Coaching tone: supportive, contextual, concise

## 🏗 Architecture
**Pattern:** MVVM + service layer.

```
AuraApp
  └── ContentView (TabView)
        ├── CleanAuraView      (consumer UI)
        ├── DailyAnalysisView  (full-day pattern mining)
        └── DebugView          (diagnostics + controls)

ChatViewModel (@MainActor)
  ├── ContinuousSpeechService  (streaming SFSpeechRecognizer orchestration)
  ├── ThetaAPIService          (conversation + one-off inference requests)
  ├── EmotionalAnalysisService (lightweight emotion classifier prompt)
  ├── (Optional) ThetaEdgeAnalysisService (periodic thematic analysis prototype)
  └── State: messages, accumulatedText, livePartial, emotionalTrend, dailyPatterns
```

### Key State Flows
1. **Speech → Accumulation:** `ContinuousSpeechService` builds `accumulatedText` while tracking silence, noise floor, confidence & session boundaries.
2. **Accumulation → AI Insight:** After interval / condition, `ChatViewModel` posts accumulated block via `ThetaAPIService.generateAIInsight()`; AI reply appended to chat.
3. **Emotional Polling:** 30s timer (plus manual trigger) calls `EmotionalAnalysisService.analyzeText()` on merged snapshot (accumulated + live partial). Result mapped to normalized score → appended to `emotionalTrend`.
4. **Daily Pattern Mining:** User taps “Analyse my patterns” → `oneOffAnalysis()` with structured JSON instruction over truncated full transcript (12k char suffix). Parsed into `[DailyPattern]` or heuristic bullets.

### Resilience & Safeguards
- Default Neutral emotion ensures UI never blank.
- Rate-limiting guard for conversational AI; separate one-off bypass for daily pattern analysis.
- JSON parsing fallback: heuristic bullet extraction if model returns prose.
- Truncation of very long transcripts & context trimming to prevent oversized payloads.

## 🔍 Notable Implementation Details
- **Swift Concurrency:** Async/await used for network inference + emotional analysis (always returned to main actor for UI mutation).
- **Combine Bindings:** Services publish audio levels, permission flags, partial transcripts; `ChatViewModel` bridges them into SwiftUI.
- **Graph Rendering:** Custom `EmotionalTrendGraph` with calculated paths, segmented gradient fill, emoji row decoupled from clipping.
- **Heuristic Parsing:** Multi‑strategy colon/emojis/whitelist detection for emotion; JSON substring scanning + fallback bullet detection for patterns.
- **Structured Prompts:** System personality + coaching guidance; dedicated JSON‑only prompt for pattern extraction.

## 📦 Key Source Files
| File | Purpose |
|------|---------|
| `AuraApp.swift` | App entry; loads `.env` config |
| `ContentView.swift` | Tab orchestration + main views |
| `ChatViewModel.swift` | Central orchestration & published state |
| `ContinuousSpeechService.swift` | Continuous speech recognition pipeline |
| `ThetaAPIService.swift` | Core model interaction (insights + one-off analysis) |
| `EmotionalAnalysisService.swift` | 30s emotional snapshot analysis & parsing |
| `ThetaEdgeAnalysisService.swift` | Experimental periodic thematic analyzer |
| `AudioService.swift` | Legacy / alternative speech recognition implementation |
| `ChatMessage.swift` | Chat message model (role, timestamp) |
| `Config.swift` | API key / environment loading |

## ⚙️ Configuration
Create a `.env` file (loaded at launch) with:
```
THETA_API_KEY=your_theta_edge_api_key_here
```
Ensure the key has access to the deployed model endpoints defined in `ThetaAPIService.baseURL`.

## ▶️ Running the App
1. Open `Aura.xcodeproj` in Xcode 15+.
2. Add your `.env` file to the project root (not committed).  
3. Build & run on device (recommended for microphone access) or simulator (limited speech features).  
4. Grant microphone & speech recognition permissions.  
5. Speak naturally; watch emotional graph populate; open **Daily** tab for pattern analysis.

## 🧪 Debugging / Diagnostics
- **Debug Tab:** Inspect timers, raw transcript, last AI request, emotional countdown.
- **Manual Emotional Analysis:** Trigger on-demand if you want immediate emotion refresh.
- **Logging:** Uses `os.Logger` categories (filter in Console: `ChatViewModel`, `ContinuousSpeechService`, `ThetaAPIService`).

## 📊 Emotional Trend Scoring
Mapped internally (`score(for:)`) to numeric range -1.0 … +1.0; used for vertical graph placement. Example mapping:
```
Happy 0.8   Calm 0.4   Neutral 0.0   Stressed -0.3   Depressed -0.9
```
New emotions gracefully default to 0.

## 🧩 Daily Pattern Output (Example)
```json
{
  "patterns": [
    {
      "title": "Evening Rumination",
      "summary": "You repeatedly revisit unresolved work thoughts after 9pm, increasing anxiety.",
      "emoji": "🌀",
      "evidence": "...kept thinking about the project even after dinner..."
    }
  ]
}
```
Heuristic fallback displays bullet-like extracted lines if JSON parse fails.

## 🔐 Privacy & Data Handling
- Transcript resides in-memory only for current session (no persistence yet).
- AI requests send only trimmed context & not raw audio.
- Potential future enhancement: on-device summarization before cloud relay.

## 🛣 Roadmap Ideas
| Area | Enhancement |
|------|-------------|
| Persistence | Secure local storage of emotional trend & daily patterns |
| Personalization | Adaptive emotion scoring & custom mood taxonomy |
| UI | Tap-to-inspect graph points / pattern drill-down modals |
| Coaching Loop | Action plan tracking & reminder notifications |
| Privacy | On-device summarization + encryption at rest |
| Analytics | Streaks, variability metrics, sentiment volatility index |
| Internationalization | Multi-language transcription & responses |
| Offline Mode | Local fallback model for basic emotion classification |

## 🧪 Testing Suggestions
- Unit test emotion parsing permutations (colon/no-colon/emoji-first).  
- Snapshot test emotional trend graph with synthetic data.  
- Mock `ThetaAPIService` for deterministic pattern analysis JSON.

## ⚠️ Known Limitations
- No persistence: App restart loses transcript & trends.
- Large transcripts truncated to last 12k chars for daily analysis.
- Pattern extraction depends on LLM compliance with JSON instruction.
- Some duplicated service responsibilities (`AudioService` vs `ContinuousSpeechService`).

## 🤝 Contributing
1. Fork & branch (`feature/my-improvement`).
2. Add focused changes + concise logs.
3. Include brief test or reproduction notes.
4. Open PR with before/after behavior summary.

## 📄 License
Currently proprietary / unpublished (add license choice here).

---
**Aura** aims to make continuous self‑reflection effortless. Speak. Observe. Adapt.

Feel free to propose refinements or ask for a slim marketing-focused README variant.
