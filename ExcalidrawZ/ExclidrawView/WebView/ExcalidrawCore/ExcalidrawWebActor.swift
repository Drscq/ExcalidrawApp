//
//  ExcalidrawWebActor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import Logging

actor ExcalidrawWebActor {
    let logger = Logger(label: "ExcalidrawWebActor")
    
    private struct HelperNotReadyError: LocalizedError {
        var errorDescription: String? {
            "Excalidraw web helper is not ready yet."
        }
    }
    
    var excalidrawCoordinator: ExcalidrawCore
    
    init(coordinator: ExcalidrawCore) {
        self.excalidrawCoordinator = coordinator
    }
    
    var loadedFileID: String?
    var webView: ExcalidrawWebView { excalidrawCoordinator.webView }
    
    func loadFile(id: String, data: Data, force: Bool = false) async throws {
        let webView = webView
        guard loadedFileID != id || force else { return }
        
        self.logger.info(
            "Load file<\(String(describing: id)), \(data.count.formatted(.byteCount(style: .file)))>, force: \(force), Thread: \(Thread().description)"
        )
        
        let isHelperReady = try await waitForHelperReady(maxAttempts: 60, delayNanoseconds: 100_000_000)
        guard isHelperReady else {
            throw HelperNotReadyError()
        }
        
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        _ = try await webView.evaluateJavaScript("window.excalidrawZHelper.loadFileBuffer(\(buf), '\(id)'); 0;")
        self.loadedFileID = id
    }
    
    private func waitForHelperReady(
        maxAttempts: Int,
        delayNanoseconds: UInt64
    ) async throws -> Bool {
        for _ in 0..<maxAttempts {
            let isReady = (try? await webView.evaluateJavaScript(
                "typeof window.excalidrawZHelper !== 'undefined' && typeof window.excalidrawZHelper.loadFileBuffer === 'function';"
            ) as? Bool) == true
            
            if isReady {
                return true
            }
            
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return false
    }
}
