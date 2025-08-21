//
//  ContentView.swift
//  cheatingai
//
//  Created by Shreyas Gurav on 09/08/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        DebugTestView()
    }
}

// MARK: - Debug Test View for Deepgram Integration
struct DebugTestView: View {
    @StateObject private var transcriptStore = SessionTranscriptStore.shared
    @State private var testResults: [String] = []
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🔧 Deepgram Debug Test")
                .font(.title)
                .bold()
            
            // Connection Status
            HStack {
                Circle()
                    .fill(isListening ? .green : .red)
                    .frame(width: 12, height: 12)
                Text("Status: \(isListening ? "Listening" : "Stopped")")
            }
            
            // Sessions Count
            VStack(alignment: .leading, spacing: 8) {
                Text("Sessions:")
                    .font(.headline)
                Text("Total: \(transcriptStore.sessions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Control Buttons
            HStack(spacing: 20) {
                Button(action: {
                    isListening.toggle()
                    if isListening {
                        startTestSession()
                    } else {
                        stopTestSession()
                    }
                }) {
                    Text(isListening ? "Stop" : "Start")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(isListening ? .red : .green)
                        .cornerRadius(25)
                }
                
                Button("Test API Key") {
                    testDeepgramAPIKey()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            
            // Test Results
            if !testResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test Results:")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(testResults, id: \.self) { result in
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func startTestSession() {
        testResults.removeAll()
        testResults.append("🔄 Starting test session...")
        testResults.append("✅ Session started")
    }
    
    private func stopTestSession() {
        testResults.append("🛑 Session stopped")
    }
    
    private func testDeepgramAPIKey() {
        testResults.removeAll()
        testResults.append("🔍 Testing Deepgram API key...")
        
        // Test Deepgram API key
        if DeepgramConfig.apiKey != "YOUR_DEEPGRAM_API_KEY_HERE" {
            testResults.append("✅ Deepgram API key found")
        } else {
            testResults.append("❌ No Deepgram API key configured")
            testResults.append("💡 Set your API key in DeepgramConfig.swift")
        }
        
        // Test if configured
        if DeepgramConfig.isConfigured {
            testResults.append("✅ Deepgram is properly configured")
        } else {
            testResults.append("❌ Deepgram configuration incomplete")
        }
    }
}

#Preview {
    ContentView()
}
