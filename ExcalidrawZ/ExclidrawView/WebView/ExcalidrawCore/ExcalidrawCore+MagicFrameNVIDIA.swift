//
//  ExcalidrawCore+MagicFrameNVIDIA.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/02/07.
//

import Foundation
import WebKit

extension ExcalidrawCore {
    static let nvidiaMagicFrameBridgeName = "excalidrawZAI"
    
    /// Intercepts Excalidraw AI fetch calls and forwards them to native NVIDIA bridge.
    static let nvidiaMagicFrameFetchProxyScript = #"""
(() => {
  if (window.__excalidrawZNvidiaBridgeInstalled) {
    return;
  }
  window.__excalidrawZNvidiaBridgeInstalled = true;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.excalidrawZAI;
  if (!handler || !window.fetch) {
    return;
  }

  const diagramToCodeUrl = "https://oss-ai.excalidraw.com/v1/ai/diagram-to-code/generate";
  const textToDiagramGenerateUrl = "https://oss-ai.excalidraw.com/v1/ai/text-to-diagram/generate";
  const textToDiagramStreamingUrl = "https://oss-ai.excalidraw.com/v1/ai/text-to-diagram/chat-streaming";
  const pending = new Map();
  let counter = 0;
  const originalFetch = window.fetch.bind(window);

  window.__excalidrawZNvidiaBridgeResolve = (response) => {
    if (!response || !response.id) {
      return;
    }
    const request = pending.get(response.id);
    if (!request) {
      return;
    }
    pending.delete(response.id);
    request.resolve(response);
  };

  window.fetch = async (input, init) => {
    const requestUrl = typeof input === "string" ? input : ((input && input.url) ? input.url : "");

    // Intercept diagram-to-code (Magic Frame)
    if (typeof requestUrl === "string" && requestUrl.indexOf(diagramToCodeUrl) === 0) {
      const id = "nvidia_bridge_" + Date.now() + "_" + (++counter);
      const body = init && typeof init.body === "string" ? init.body : null;

      const bridgeResponse = await new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        try {
          handler.postMessage({
            id,
            body,
            method: init && init.method ? init.method : "POST",
            url: requestUrl,
            type: "diagram-to-code"
          });
        } catch (error) {
          pending.delete(id);
          reject(error);
        }
      });

      const status = Number.isInteger(bridgeResponse.status) ? bridgeResponse.status : 500;
      const safeStatus = status >= 100 && status <= 599 ? status : 500;
      const responseHeaders =
        bridgeResponse && typeof bridgeResponse.headers === "object"
          ? bridgeResponse.headers
          : { "Content-Type": "application/json" };
      const responseBody =
        bridgeResponse && typeof bridgeResponse.body === "string"
          ? bridgeResponse.body
          : JSON.stringify({ message: "Invalid native response body." });

      return new Response(responseBody, {
        status: safeStatus,
        headers: responseHeaders
      });
    }

    // Intercept text-to-diagram (AI Text to Diagram)
    if (
      typeof requestUrl === "string" &&
      (
        requestUrl.indexOf(textToDiagramGenerateUrl) === 0 ||
        requestUrl.indexOf(textToDiagramStreamingUrl) === 0
      )
    ) {
      const id = "nvidia_ttd_" + Date.now() + "_" + (++counter);
      const body = init && typeof init.body === "string" ? init.body : null;

      const bridgeResponse = await new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        try {
          handler.postMessage({
            id,
            body,
            method: init && init.method ? init.method : "POST",
            url: requestUrl,
            type: "text-to-diagram"
          });
        } catch (error) {
          pending.delete(id);
          reject(error);
        }
      });

      const status = Number.isInteger(bridgeResponse.status) ? bridgeResponse.status : 500;
      const safeStatus = status >= 100 && status <= 599 ? status : 500;
      const responseHeaders =
        bridgeResponse && typeof bridgeResponse.headers === "object"
          ? bridgeResponse.headers
          : { "Content-Type": "application/json" };
      const responseBody =
        bridgeResponse && typeof bridgeResponse.body === "string"
          ? bridgeResponse.body
          : "";

      return new Response(responseBody, {
        status: safeStatus,
        headers: responseHeaders
      });
    }

    return originalFetch(input, init);
  };
})();
"""#
    
    func handleNvidiaMagicFrameBridgeMessage(_ message: WKScriptMessage) {
        guard JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body),
              let request = try? JSONDecoder().decode(NvidiaMagicFrameBridgeRequest.self, from: data) else {
            logger.error("Invalid NVIDIA bridge request payload.")
            return
        }
        
        let requestType = request.type ?? "diagram-to-code"
        logger.info("AI request intercepted for NVIDIA bridge (\(requestType)): \(request.id)")
        
        Task { [weak self] in
            guard let self else { return }
            
            switch requestType {
            case "text-to-diagram":
                await self.handleTextToDiagramRequest(request)
            default:
                await self.handleDiagramToCodeRequest(request)
            }
        }
    }
    
    private func handleDiagramToCodeRequest(_ request: NvidiaMagicFrameBridgeRequest) async {
        do {
            let html = try await self.generateMagicFrameHTML(requestBody: request.body)
            let body = try Self.jsonString(["html": html])
            await self.resolveNvidiaMagicFrameBridgeRequest(
                id: request.id,
                ok: true,
                status: 200,
                body: body
            )
        } catch {
            self.logger.error("Magic Frame NVIDIA generation failed: \(error.localizedDescription)")
            let body = (try? Self.jsonString(["message": error.localizedDescription])) ?? "{\"message\":\"Generation failed.\"}"
            await self.resolveNvidiaMagicFrameBridgeRequest(
                id: request.id,
                ok: false,
                status: 500,
                body: body
            )
        }
    }
    
    private func handleTextToDiagramRequest(_ request: NvidiaMagicFrameBridgeRequest) async {
        do {
            let mermaidCode = try await self.generateTextToDiagramMermaid(requestBody: request.body)
            let isStreaming = request.url?.contains("chat-streaming") == true
            if isStreaming {
                let sseBody = Self.buildSSEResponse(content: mermaidCode)
                await self.resolveNvidiaMagicFrameBridgeRequest(
                    id: request.id,
                    ok: true,
                    status: 200,
                    body: sseBody,
                    headers: [
                        "Content-Type": "text/event-stream",
                        "X-RateLimit-Limit": "100",
                        "X-RateLimit-Remaining": "99"
                    ]
                )
            } else {
                let body = try Self.jsonString(["generatedResponse": mermaidCode])
                await self.resolveNvidiaMagicFrameBridgeRequest(
                    id: request.id,
                    ok: true,
                    status: 200,
                    body: body,
                    headers: [
                        "Content-Type": "application/json",
                        "X-RateLimit-Limit": "100",
                        "X-RateLimit-Remaining": "99"
                    ]
                )
            }
        } catch {
            self.logger.error("Text-to-diagram NVIDIA generation failed: \(error.localizedDescription)")
            let isStreaming = request.url?.contains("chat-streaming") == true
            if isStreaming {
                let errorSSE = "data: {\"error\":{\"message\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\",\"code\":\"server_error\"}}\n\n"
                await self.resolveNvidiaMagicFrameBridgeRequest(
                    id: request.id,
                    ok: false,
                    status: 500,
                    body: errorSSE,
                    headers: [
                        "Content-Type": "text/event-stream",
                        "X-RateLimit-Limit": "100",
                        "X-RateLimit-Remaining": "99"
                    ]
                )
            } else {
                let body = (try? Self.jsonString(["message": error.localizedDescription])) ?? "{\"message\":\"Request failed.\"}"
                await self.resolveNvidiaMagicFrameBridgeRequest(
                    id: request.id,
                    ok: false,
                    status: 500,
                    body: body,
                    headers: [
                        "Content-Type": "application/json",
                        "X-RateLimit-Limit": "100",
                        "X-RateLimit-Remaining": "99"
                    ]
                )
            }
        }
    }
}

extension ExcalidrawCore {
    fileprivate struct NvidiaMagicFrameBridgeRequest: Decodable {
        let id: String
        let body: String?
        let type: String?
        let url: String?
    }
    
    fileprivate struct NvidiaMagicFrameBridgeResponse: Encodable {
        let id: String
        let ok: Bool
        let status: Int
        let body: String
        let headers: [String: String]
    }
    
    fileprivate struct NvidiaDiagramToCodeRequest: Decodable {
        let texts: String?
        let image: String?
        let theme: String?
    }
    
    fileprivate enum NvidiaMagicFrameError: LocalizedError {
        case invalidRequest
        case missingAPIKey
        case invalidResponse
        case emptyResponse
        case serverError(status: Int, message: String)
        
        var errorDescription: String? {
            switch self {
                case .invalidRequest:
                    return "Invalid request payload."
                case .missingAPIKey:
                    return "NVIDIA_API_KEY is missing in Secrets.plist."
                case .invalidResponse:
                    return "NVIDIA returned an invalid response."
                case .emptyResponse:
                    return "NVIDIA returned an empty response."
                case .serverError(let status, let message):
                    return "NVIDIA request failed (\(status)): \(message)"
            }
        }
    }
    
    fileprivate struct TextToDiagramRequest: Decodable {
        let prompt: String?
        let messages: [[String: String]]?
    }
    
    fileprivate func generateMagicFrameHTML(requestBody: String?) async throws -> String {
        guard let requestBody,
              let data = requestBody.data(using: .utf8) else {
            throw NvidiaMagicFrameError.invalidRequest
        }
        let payload = try JSONDecoder().decode(NvidiaDiagramToCodeRequest.self, from: data)
        
        if Secrets.shared.nvidiaAPIKey.isEmpty {
            throw NvidiaMagicFrameError.missingAPIKey
        }
        
        if let image = payload.image,
           !image.isEmpty {
            do {
                return try await requestMagicFrameHTMLFromNvidia(payload: payload, includeImage: true)
            } catch {
                logger.warning("NVIDIA multimodal request failed, fallback to text-only: \(error.localizedDescription)")
            }
        }
        
        return try await requestMagicFrameHTMLFromNvidia(payload: payload, includeImage: false)
    }
    
    fileprivate func requestMagicFrameHTMLFromNvidia(
        payload: NvidiaDiagramToCodeRequest,
        includeImage: Bool
    ) async throws -> String {
        let endpoint = Secrets.shared.nvidiaBaseURL.appendingPathComponent("chat/completions")
        logger.info("Sending Magic Frame request to NVIDIA model '\(Secrets.shared.nvidiaModel)' (includeImage: \(includeImage))")
        let prompt = buildMagicFramePrompt(payload: payload)
        
        var userContent: Any = prompt
        if includeImage,
           let image = payload.image,
           !image.isEmpty {
            userContent = [
                [
                    "type": "text",
                    "text": prompt
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(image)"
                    ]
                ]
            ]
        }
        
        let requestBody: [String: Any] = [
            "model": Secrets.shared.nvidiaModel,
            "temperature": 0.1,
            "messages": [
                [
                    "role": "system",
                    "content": "You convert UI wireframes into HTML with inline CSS. Return only HTML. No markdown."
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.shared.nvidiaAPIKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NvidiaMagicFrameError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = Self.extractServerMessage(data: data)
            throw NvidiaMagicFrameError.serverError(status: httpResponse.statusCode, message: message)
        }
        
        let assistantOutput = try Self.extractAssistantContent(from: data)
        let html = Self.extractHTML(from: assistantOutput)
        guard !html.isEmpty else {
            throw NvidiaMagicFrameError.emptyResponse
        }
        logger.info("NVIDIA Magic Frame generation succeeded.")
        return html
    }
    
    fileprivate func buildMagicFramePrompt(payload: NvidiaDiagramToCodeRequest) -> String {
        let theme = payload.theme?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? payload.theme!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "light"
        let texts = payload.texts?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? payload.texts!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "(none)"
        
        return """
Create production-ready HTML with inline CSS from this wireframe context.

Requirements:
- Return only HTML markup (no Markdown code fences).
- Include a full responsive layout using semantic elements.
- Match this color theme preference: \(theme).
- Keep visible labels/texts from the wireframe if provided.
- If information is missing, infer sensible UI structure.

Wireframe text extracted from frame elements:
\(texts)
"""
    }
    
    // MARK: - Text-to-Diagram Generation
    
    fileprivate func generateTextToDiagramMermaid(requestBody: String?) async throws -> String {
        guard let requestBody,
              let data = requestBody.data(using: .utf8) else {
            throw NvidiaMagicFrameError.invalidRequest
        }
        
        if Secrets.shared.nvidiaAPIKey.isEmpty {
            throw NvidiaMagicFrameError.missingAPIKey
        }
        
        let requestPayload = try JSONDecoder().decode(TextToDiagramRequest.self, from: data)
        
        // Build messages for NVIDIA API
        var nvidiaMessages: [[String: Any]] = [
            [
                "role": "system",
                "content": """
                You are a diagram expert that generates Mermaid diagram syntax from text descriptions.
                
                Rules:
                - Return ONLY valid Mermaid diagram code. No explanations, no markdown code fences.
                - Use flowchart (graph TD/LR), sequence, class, state, er, or gantt diagrams as appropriate.
                - Keep node labels concise and clear.
                - Use proper Mermaid syntax with correct indentation.
                """
            ]
        ]
        
        if let prompt = requestPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            nvidiaMessages.append([
                "role": "user",
                "content": prompt
            ])
        } else if let messages = requestPayload.messages {
            for msg in messages {
                if let role = msg["role"], let content = msg["content"] {
                    nvidiaMessages.append([
                        "role": role == "assistant" ? "assistant" : "user",
                        "content": content
                    ])
                }
            }
        }
        
        guard nvidiaMessages.count > 1 else {
            throw NvidiaMagicFrameError.invalidRequest
        }
        
        let requestBodyDict: [String: Any] = [
            "model": Secrets.shared.nvidiaModel,
            "temperature": 0.2,
            "messages": nvidiaMessages
        ]
        
        let endpoint = Secrets.shared.nvidiaBaseURL.appendingPathComponent("chat/completions")
        logger.info("Sending Text-to-Diagram request to NVIDIA model '\(Secrets.shared.nvidiaModel)'")
        
        let body = try JSONSerialization.data(withJSONObject: requestBodyDict, options: [])
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.shared.nvidiaAPIKey)", forHTTPHeaderField: "Authorization")
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NvidiaMagicFrameError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = Self.extractServerMessage(data: responseData)
            throw NvidiaMagicFrameError.serverError(status: httpResponse.statusCode, message: message)
        }
        
        let assistantOutput = try Self.extractAssistantContent(from: responseData)
        let mermaid = Self.extractMermaid(from: assistantOutput)
        guard !mermaid.isEmpty else {
            throw NvidiaMagicFrameError.emptyResponse
        }
        logger.info("NVIDIA Text-to-Diagram generation succeeded. Mermaid length: \(mermaid.count)")
        return mermaid
    }
    
    /// Extract clean Mermaid code from LLM output (strip code fences etc.)
    fileprivate static func extractMermaid(from rawContent: String) -> String {
        var trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // Strip markdown code fences
        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: "\n")
            // Remove opening fence (e.g. ```mermaid or ```)
            if !lines.isEmpty {
                lines.removeFirst()
            }
            // Remove closing fence
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
                lines.removeLast()
            }
            trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return trimmed
    }
    
    /// Build an SSE-formatted response body that Excalidraw's TTDStreamFetch expects.
    /// Excalidraw reads chunks from `data:` lines and accumulates text.
    fileprivate static func buildSSEResponse(content: String) -> String {
        // Send the entire Mermaid content as a single SSE data event,
        // formatted the way Excalidraw's streaming parser expects.
        // The parser reads `data: <json>` lines and extracts `choices[0].delta.content`.
        var sseChunks: [String] = []
        
        // Split into reasonable chunks to simulate streaming
        let chunkSize = 80
        var index = content.startIndex
        while index < content.endIndex {
            let end = content.index(index, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
            let chunk = String(content[index..<end])
            let escaped = chunk
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            let jsonChunk = "{\"choices\":[{\"delta\":{\"content\":\"\(escaped)\"}}]}"
            sseChunks.append("data: \(jsonChunk)\n\n")
            index = end
        }
        
        sseChunks.append("data: [DONE]\n\n")
        return sseChunks.joined()
    }
    
    @MainActor
    fileprivate func resolveNvidiaMagicFrameBridgeRequest(
        id: String,
        ok: Bool,
        status: Int,
        body: String,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) async {
        let safeStatus = (100...599).contains(status) ? status : 500
        let response = NvidiaMagicFrameBridgeResponse(
            id: id,
            ok: ok,
            status: safeStatus,
            body: body,
            headers: headers
        )
        
        guard let data = try? JSONEncoder().encode(response),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to encode NVIDIA bridge response.")
            return
        }
        
        do {
            try await webView.evaluateJavaScript("window.__excalidrawZNvidiaBridgeResolve(\(json)); 0;")
        } catch {
            logger.error("Failed to deliver NVIDIA bridge response to webview: \(error)")
        }
    }
    
    fileprivate static func extractAssistantContent(from data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw NvidiaMagicFrameError.invalidResponse
        }
        
        if let content = message["content"] as? String {
            return content
        }
        
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty {
                return text
            }
        }
        
        throw NvidiaMagicFrameError.emptyResponse
    }
    
    fileprivate static func extractHTML(from rawContent: String) -> String {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let html = obj["html"] as? String {
            let clean = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return clean
            }
        }
        
        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: "\n")
            if !lines.isEmpty {
                lines.removeFirst()
            }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
                lines.removeLast()
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let range = trimmed.range(of: "<!doctype", options: [.caseInsensitive]) {
            return String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = trimmed.range(of: "<html", options: [.caseInsensitive]) {
            return String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return trimmed
    }
    
    fileprivate static func extractServerMessage(data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["message"] as? String,
           !message.isEmpty {
            return message
        }
        
        if let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        
        return "Unknown server error."
    }
    
    fileprivate static func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}
