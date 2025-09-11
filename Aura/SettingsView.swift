import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showAdvanced = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Speech Recognition Language")) {
                    Picker("Active Language", selection: $viewModel.primaryLanguage) {
                        ForEach(SpeechLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    Text("Aura will listen using this language. Switching updates recognition immediately.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Auto Detection")) {
                    HStack {
                        Text("Auto-detect & switch language")
                        Spacer()
                        Text("Coming Soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Automatic language detection will arrive in a future version. It will listen for language shifts and switch recognition seamlessly.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .italic()
                }
                Section(header: Text("About")) {
                    Text("Aura AI Companion")
                    Text("Version 0.1 (multilingual prototype)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { viewModel.autoDetectEnabled = false }
        }
    }
}
