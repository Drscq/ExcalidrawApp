//
//  WebView+Download.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif


extension ExcalidrawCore: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        switch suggestedFilename.components(separatedBy: ".").last {
            case .some("excalidraw"):
                return nil
                
            case .some("png"):
                return onExportPNG(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename)

            case .some("webm"):
#if os(macOS)
                return await onExportWebM(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename)
#else
                return nil
#endif
                
            default:
                return nil
        }
    }

    @MainActor
    func downloadDidFinish(_ download: WKDownload) {
        guard let request = download.originalRequest,
              let url = downloads[request] else { return }
        logger.info("download did finished: \(url)")
        self.parent?.exportState.finishExport(download: download)
        downloads.removeValue(forKey: request)

        Task { @MainActor in
            // Recovery guard: blob downloads should not leave the main board in a loading state.
            let isBridgeReady = ((try? await self.webView.evaluateJavaScript(
                "typeof window.excalidrawZHelper !== 'undefined' && typeof window.excalidrawZHelper.loadFileBuffer === 'function';"
            ) as? Bool) == true)
            if isBridgeReady {
                self.isNavigating = false
                self.isDocumentLoaded = true
                if self.parent?.loadingState == .loading {
                    self.parent?.loadingState = .loaded
                }
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        logger.warning("download failed: \(error.localizedDescription)")
        Task { @MainActor in
            let isBridgeReady = ((try? await self.webView.evaluateJavaScript(
                "typeof window.excalidrawZHelper !== 'undefined' && typeof window.excalidrawZHelper.loadFileBuffer === 'function';"
            ) as? Bool) == true)
            if isBridgeReady {
                self.isNavigating = false
                self.isDocumentLoaded = true
                if self.parent?.loadingState == .loading {
                    self.parent?.loadingState = .loaded
                }
            }
        }
    }
    
    func onExportPNG(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) -> URL? {
        self.logger.info("on export png.")
        let fileManager: FileManager = FileManager.default
        do {
            let directory: URL = try getTempDirectory()
            let fileExtension = suggestedFilename.components(separatedBy: ".").last ?? "png"
            let fileName = self.parent?.fileState.currentActiveFile?.name?.appending(".\(fileExtension)") ?? suggestedFilename
            let url = directory.appendingPathComponent(fileName, conformingTo: .image)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            
            if let request = download.originalRequest {
                self.downloads[request] = url;
            }
            
            self.parent?.exportState.beginExport(url: url, download: download)
            return url;
        } catch {
            self.parent?.onError(error)
            return nil
        }
    }

#if os(macOS)
    @MainActor
    func onExportWebM(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        self.logger.info("on export webm.")

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        if let webmType = UTType(filenameExtension: "webm") {
            panel.allowedContentTypes = [webmType]
        }

        let result = panel.runModal()
        guard result == .OK, let selectedURL = panel.url else {
            return nil
        }

        if let request = download.originalRequest {
            self.downloads[request] = selectedURL
        }
        self.parent?.exportState.beginExport(url: selectedURL, download: download)
        return selectedURL
    }
#endif
}
