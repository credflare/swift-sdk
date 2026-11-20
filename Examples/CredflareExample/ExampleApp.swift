import SwiftUI
import CredflareSDK

@main
struct CredflareExampleApp: App {
    var body: some Scene { WindowGroup { DemoView() } }
}
struct DemoView: View {
    @State private var presenting = false
    @State private var mode = "either"
    @State private var result: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Native iOS SDK demo").font(.title2.bold())
            Text("Choose a sample profile. The SDK follows the capture rules returned by the backend.").foregroundStyle(.secondary)
            Picker("Sample profile", selection: $mode) {
                Text("Photo or file").tag("either")
                Text("Camera photos").tag("snapshot")
                Text("File uploads").tag("upload")
                Text("Photo and saved file").tag("snapshot_and_upload")
            }.pickerStyle(.menu)
            Button("Start verification") { presenting = true }.buttonStyle(.borderedProminent).controlSize(.large)
            if let result { Text(result).foregroundStyle(.secondary) }
            Spacer()
            Text("Sandbox demo. Use sample documents.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        .fullScreenCover(isPresented: $presenting) {
            CredflareVerificationView(sessionProvider: {
                var request = URLRequest(url: URL(string: "http://localhost:3107/session")!)
                request.httpMethod = "POST"; request.timeoutInterval = 30
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["email": "native-demo@example.test", "mode": mode])
                let configuration = URLSessionConfiguration.ephemeral
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CredflareError.network("The local demo backend could not create a session.") }
                return try JSONDecoder().decode(SessionDescriptor.self, from: data)
            }, autoStart: true, onResult: { value in
                switch value {
                case .submitted: result = "Documents received for review."
                case .cancelled: result = "Verification closed."
                case .hostActionRequired: result = "Return to your application for the remaining checks."
                }
                presenting = false
            })
        }
    }
}
