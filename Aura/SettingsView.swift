import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showAdvanced = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Speech Recognition Languages")) {
                    // Multi-select toggles
                    ForEach(SpeechLanguage.allCases) { lang in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedLanguages.contains(lang) },
                            set: { isOn in
                                if isOn { viewModel.selectedLanguages.insert(lang) } else { viewModel.selectedLanguages.remove(lang) }
                            }
                        )) {
                            HStack {
                                Text(lang.flag)
                                Text(lang.displayName)
                            }
                        }
                    }
                    Picker("Primary (active)", selection: $viewModel.primaryLanguage) {
                        ForEach(viewModel.selectedLanguages.sorted { $0.rawValue < $1.rawValue }) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    Text("Aura listens using the Primary language. You can pre-enable others to switch quickly.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Auto Detection")) {
                    Toggle(isOn: $viewModel.autoDetectEnabled) {
                        Text("Auto-detect & switch primary")
                    }
                    Text("Monitors recent utterances (≥25 chars aggregated). Switches when confidence ≥65% and at least 90s since last switch.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("About")) {
                    Text("Aura AI Companion")
                    Text("Version 0.1 (multilingual prototype)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
