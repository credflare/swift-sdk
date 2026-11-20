import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private struct Envelope<T: Decodable>: Decodable { let success: Bool; let message: String?; let data: T }
private struct SubmissionReceipt: Decodable { let id: Int }

public actor VerificationSession {
    private var descriptor: SessionDescriptor
    private let transport: URLSession
    public init(_ descriptor: SessionDescriptor, timeout: TimeInterval = 60) {
        self.descriptor = descriptor
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        transport = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { transport.invalidateAndCancel() }
    public func replaceSession(_ next: SessionDescriptor) throws {
        guard next.apiBaseURL == descriptor.apiBaseURL else { throw CredflareError.validation("Renew access to the same verification session.") }
        descriptor = next
    }
    private func call<T: Decodable>(_ method: String, suffix: String = "", body: Data? = nil, contentType: String? = nil, key: UUID? = nil, as type: T.Type) async throws -> T {
        let base = descriptor.apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/sdk/sessions/\(descriptor.sessionID.uuidString.lowercased())\(suffix)") else { throw CredflareError.validation("Invalid API URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(descriptor.token)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key.uuidString.lowercased(), forHTTPHeaderField: "X-Idempotency-Key") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw CredflareError.network("Could not reach Credflare. Retry with the same evidence.") }
        guard let http = response as? HTTPURLResponse else { throw CredflareError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw CredflareError.api(http.statusCode, json?["message"] as? String ?? "Request failed.")
        }
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { throw CredflareError.invalidResponse }
        guard envelope.success else { throw CredflareError.api(http.statusCode, envelope.message ?? "Request failed.") }
        return envelope.data
    }
    public func cancel() async throws { _ = try await call("DELETE", as: JSONValue.self) }
    public func get() async throws -> SessionInfo { try await call("GET", as: SessionInfo.self) }
    public func upload(_ data: Data, filename: String, source: CaptureSource, side: DocumentSide, documentTypeID: Int, key: UUID) async throws -> UploadedEvidence {
        try await uploadEvidence(data, filename: filename, source: source, side: side, documentTypeID: documentTypeID, key: key)
    }
    public func uploadSelfie(_ data: Data, filename: String, key: UUID) async throws -> UploadedEvidence {
        guard ["jpg", "jpeg", "png", "webp"].contains((filename as NSString).pathExtension.lowercased()) else { throw CredflareError.validation("Use a supported selfie image format.") }
        return try await uploadEvidence(data, filename: filename, source: .camera, side: .front, documentTypeID: nil, key: key)
    }
    private func uploadEvidence(_ data: Data, filename: String, source: CaptureSource, side: DocumentSide, documentTypeID: Int?, key: UUID) async throws -> UploadedEvidence {
        guard !filename.isEmpty, !filename.contains("\r"), !filename.contains("\n"), !filename.contains("\""), !filename.contains("/"), !filename.contains("\\") else { throw CredflareError.validation("Choose a file with a valid name.") }
        let ext = (filename as NSString).pathExtension.lowercased()
        let mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp", "pdf": "application/pdf", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"][ext]
        guard let mime else { throw CredflareError.validation("This file type is not supported.") }
        let boundary = "Credflare-" + UUID().uuidString
        var body = Data()
        for (name, value) in [("side", side.rawValue), ("capture_source", source.rawValue), ("document_type_id", documentTypeID.map(String.init) ?? "")] where !value.isEmpty {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await call("POST", suffix: documentTypeID == nil ? "/uploads/biometrics" : "/uploads/documents", body: body, contentType: "multipart/form-data; boundary=\(boundary)", key: key, as: UploadedEvidence.self)
    }
    public func submitSelfie(imageFileID: Int, key: UUID) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["type": "facial_verification", "image_file_id": imageFileID])
        return try await call("POST", suffix: "/submit", body: body, contentType: "application/json", key: key, as: SubmissionReceipt.self).id
    }
    public func submit(documentTypeID: Int, evidence: [Evidence], key: UUID) async throws -> Int {
        struct Payload: Encodable {
            let type = "document_verification"; let documentTypeID: Int; let evidence: [Evidence]
            enum CodingKeys: String, CodingKey { case type, documentTypeID = "document_type_id", evidence }
        }
        let body = try JSONEncoder().encode(Payload(documentTypeID: documentTypeID, evidence: evidence))
        return try await call("POST", suffix: "/submit", body: body, contentType: "application/json", key: key, as: SubmissionReceipt.self).id
    }
}
