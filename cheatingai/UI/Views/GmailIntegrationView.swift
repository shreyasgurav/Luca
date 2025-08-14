import SwiftUI

struct GmailIntegrationView: View {
    @State private var statusText: String = "Checking…"
    @State private var connectedEmail: String = ""
    @State private var emailHint: String = ""
    @State private var isLoading: Bool = false
    @State private var disconnecting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Status:")
                    .fontWeight(.medium)
                Text(statusText)
                if !connectedEmail.isEmpty {
                    Text("(") + Text(connectedEmail).foregroundColor(.secondary) + Text(")")
                }
                if isLoading { ProgressView().scaleEffect(0.8) }
            }

            HStack(spacing: 8) {
                TextField("your@gmail.com (optional)", text: $emailHint)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Button("Connect Gmail") { connectGmail() }
                Button("Refresh Status") { fetchStatus() }
            }

            HStack(spacing: 8) {
                Button("Disconnect") { disconnect() }
                    .disabled(isLoading || disconnecting)
                Spacer()
                Button("List 5 Emails") { listFive() }
                    .disabled(isLoading)
            }
        }
        .onAppear { fetchStatus() }
    }

    private func fetchStatus() {
        isLoading = true
        statusText = "Checking…"
        ClientAPI.shared.gmailStatus { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let resp):
                    if resp.connected {
                        self.statusText = "Connected"
                        self.connectedEmail = resp.email ?? ""
                    } else {
                        self.statusText = "Not connected"
                        self.connectedEmail = ""
                    }
                case .failure(let err):
                    self.statusText = "Error: \(err.localizedDescription)"
                    self.connectedEmail = ""
                }
            }
        }
    }

    private func connectGmail() {
        isLoading = true
        ClientAPI.shared.gmailAuthURL(emailHint: emailHint) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let url):
                    NSWorkspace.shared.open(url)
                case .failure(let err):
                    self.statusText = "Auth URL error: \(err.localizedDescription)"
                }
            }
        }
    }

    private func listFive() {
        isLoading = true
        ClientAPI.shared.gmailListEmails(max: 5) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let resp):
                    self.statusText = "Fetched \(resp.emails.count) emails. Use overlay to ask questions."
                case .failure(let err):
                    self.statusText = "List error: \(err.localizedDescription)"
                }
            }
        }
    }

    private func disconnect() {
        disconnecting = true
        ClientAPI.shared.gmailDisconnect { result in
            DispatchQueue.main.async {
                self.disconnecting = false
                switch result {
                case .success:
                    self.statusText = "Disconnected"
                    self.connectedEmail = ""
                case .failure(let err):
                    self.statusText = "Disconnect error: \(err.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    GmailIntegrationView()
}


