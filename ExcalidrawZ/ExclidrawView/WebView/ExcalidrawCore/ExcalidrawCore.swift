//
//  WebViewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import SwiftUI
import WebKit
import Logging
import Combine
import CoreData

typealias CollaborationInfo = ExcalidrawCore.CollaborationInfo

actor ExportImageManager {
    var flyingRequests: [String : (String) -> Void] = [:]
    
    public func requestExport(id: String) async -> String {
        await withCheckedContinuation { continuation in
            self.flyingRequests[id] = { data in
                continuation.resume(returning: data)
            }
        }
    }
    
    public func responseExport(id: String, blobString: String) {
        self.flyingRequests[id]?(blobString)
    }
}
actor AllMediaTransferManager {
    var flyingRequests: [String : ([ExcalidrawFile.ResourceFile]) -> Void] = [:]
    
    public func requestExport(id: String) async -> [ExcalidrawFile.ResourceFile] {
        await withCheckedContinuation { continuation in
            self.flyingRequests[id] = { data in
                continuation.resume(returning: data)
            }
        }
    }
    
    public func responseExport(id: String, resourceFiles: [ExcalidrawFile.ResourceFile]) {
        self.flyingRequests[id]?(resourceFiles)
    }
}

class ExcalidrawCore: NSObject, ObservableObject {
#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    
    let logger = Logger(label: "ExcalidrawCore")
    
    var parent: ExcalidrawView?
    lazy var errorStream: AsyncStream<Error> = {
        AsyncStream { continuation in
            publishError = {
                continuation.yield($0)
            }
        }
    }()
    internal var publishError: (_ error: Error) -> Void
    var webView: ExcalidrawWebView = .init(frame: .zero, configuration: .init()) { _ in }
    lazy var webActor = ExcalidrawWebActor(coordinator: self)
    
    override init() {
        self.publishError = { error in }
        super.init()
        self.configWebView()
    }
    
    @Published var isNavigating = true
    @Published var isDocumentLoaded = false
    @Published var isCollabEnabled = false
    @Published private(set) var isLoading: Bool = false
    
    var downloadCache: [String : Data] = [:]
    var downloads: [URLRequest : URL] = [:]
    
    let blobRequestQueue = DispatchQueue(label: "BlobRequestQueue", qos: .background)
    var exportImageManager = ExportImageManager()
    var allMediaTransferManager = AllMediaTransferManager()
    
    @Published var canUndo = false
    @Published var canRedo = false
    
    var previousFileID: UUID? = nil
    private var lastVersion: Int = 0

    var hasInjectIndexedDBData = false

    // Track loaded MediaItem IDs for re-injection detection
    private var loadedMediaItemIDs: Set<String> = []

    internal var lastTool: ExcalidrawTool?
    
    @MainActor
    func setup(parent: ExcalidrawView) {
        self.parent = parent
        switch parent.type {
            case .normal:
                Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                    .map { isNavigating, isDocumentLoaded in
                        isNavigating || !isDocumentLoaded
                    }
                    .assign(to: &$isLoading)
            case .collaboration:
                Publishers.CombineLatest(
                    Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                        .map { isNavigating, isDocumentLoaded in
                            isNavigating || !isDocumentLoaded
                        },
                    $isCollabEnabled
                )
                .map { $0 || !$1 }
                .assign(to: &$isLoading)
        }
    }
    
    func configWebView() {
        logger.info("Configure Web View...")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "excalidrawZ")
        userContentController.add(self, name: Self.nvidiaMagicFrameBridgeName)
        userContentController.addUserScript(
            WKUserScript(
                source: Self.nvidiaMagicFrameFetchProxyScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.textToDiagramCloseButtonScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
#if os(macOS)
        userContentController.addUserScript(
            WKUserScript(
                source: Self.whiteboardRecorderScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
#endif
        
        do {
            let consoleHandlerScript = try WKUserScript(
                source: String(
                    contentsOf: Bundle.main.url(forResource: "overwrite_console", withExtension: "js")!,
                    encoding: .utf8
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(consoleHandlerScript)
            userContentController.add(self, name: "consoleHandler") // it is necessary
            logger.info("Enable console handler.")
        } catch {
            logger.error("Config consoleHandler failed: \(error)")
        }
        
        config.userContentController = userContentController
        
        self.webView = ExcalidrawWebView(
            frame: .zero,
            configuration: config
        ) { key in
            switch key {
                case .number(let int):
                    Task {
                        try? await self.toggleToolbarAction(key: int)
                    }
                case .char(let character):
                    Task {
                        try? await self.toggleToolbarAction(key: character)
                    }
                case .space:
                    Task {
                        try? await self.toggleToolbarAction(key: " ")
                    }
                case .escape:
                    Task {
                        try? await self.toggleToolbarAction(key: "\u{1B}")
                    }
            }
        }
#if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) {
            self.webView.isInspectable = true
        } else {
        }
#endif
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        
#if os(iOS)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        self.webView.addInteraction(pencilInteraction)
#endif
        
        DispatchQueue.main.async {
            self.refresh()
        }
    }
    
    public func refresh() {
        self.logger.info("refreshing...")
        let request: URLRequest
        switch self.parent?.type {
            case .normal:
#if DEBUG
                request = URLRequest(url: URL(string: "http://127.0.0.1:8486/index.html")!)
#else
                request = URLRequest(url: URL(string: "http://127.0.0.1:8487/index.html")!)
#endif
                self.webView.load(request)
            case .collaboration:
                var url = Secrets.shared.collabURL
                if let roomID = self.parent?.file?.roomID,
                   !roomID.isEmpty {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    components?.fragment = "room=\(roomID)"
                    if let newURL = components?.url {
                        url = newURL
                    }
                    self.isCollabEnabled = true
                }
                request = URLRequest(url: url)
                self.logger.info("navigate to \(url), roomID: \(String(describing: self.parent?.file?.roomID))")
                self.webView.load(request)
            case nil:
                break
        }
    }
}

extension ExcalidrawCore {
    /// Adds a fallback close button for Excalidraw's Text-to-Diagram dialog.
    /// Upstream only renders the close icon in phone/fullscreen mode.
    static let textToDiagramCloseButtonScript = #"""
(() => {
  if (window.__excalidrawZTTDCloseButtonInstalled) {
    return;
  }
  window.__excalidrawZTTDCloseButtonInstalled = true;

  const buttonId = "excalidrawz-ttd-close-button";

  const isElementVisible = (element) => {
    if (!element) {
      return false;
    }
    const style = window.getComputedStyle(element);
    return style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
  };

  const findTTDDialog = () => {
    return document.querySelector(".Dialog.ttd-dialog");
  };

  const isTTDDialogOpen = () => {
    const dialog = findTTDDialog();
    if (!dialog) {
      return false;
    }
    const modal = dialog.closest(".Modal");
    return isElementVisible(dialog) && (!modal || isElementVisible(modal));
  };

  const dispatchEscape = (target) => {
    const event = new KeyboardEvent("keydown", {
      key: "Escape",
      code: "Escape",
      keyCode: 27,
      which: 27,
      bubbles: true,
      cancelable: true
    });
    target.dispatchEvent(event);
  };

  const requestClose = () => {
    const dialog = findTTDDialog();
    if (!dialog) {
      return;
    }
    const modal = dialog.closest(".Modal");
    const background = modal ? modal.querySelector(".Modal__background") : null;
    if (background) {
      background.dispatchEvent(new MouseEvent("click", {
        bubbles: true,
        cancelable: true,
        view: window
      }));
      return;
    }
    dispatchEscape(modal || dialog);
    dispatchEscape(document);
  };

  const ensureButton = () => {
    const dialog = findTTDDialog();

    if (!document.body || !dialog) {
      const existing = document.getElementById(buttonId);
      if (existing) {
        existing.style.display = "none";
      }
      return;
    }

    let button = document.getElementById(buttonId);
    if (!button) {
      button = document.createElement("button");
      button.id = buttonId;
      button.type = "button";
      button.textContent = "×";
      button.setAttribute("aria-label", "Close text-to-diagram dialog");
      button.title = "Close";

      button.style.position = "absolute";
      button.style.top = "10px";
      button.style.right = "12px";
      button.style.zIndex = "20";
      button.style.display = "none";
      button.style.width = "28px";
      button.style.height = "28px";
      button.style.border = "none";
      button.style.borderRadius = "999px";
      button.style.background = "transparent";
      button.style.color = "var(--color-text-primary, #1f1f1f)";
      button.style.font = "400 24px/1 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";
      button.style.padding = "0";
      button.style.cursor = "pointer";
      button.style.opacity = "0.72";

      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        requestClose();
      });

      button.addEventListener("mouseenter", () => {
        button.style.opacity = "1";
        button.style.background = "rgba(0, 0, 0, 0.06)";
      });
      button.addEventListener("mouseleave", () => {
        button.style.opacity = "0.72";
        button.style.background = "transparent";
      });
    }

    if (dialog.style.position !== "relative" && dialog.style.position !== "absolute") {
      dialog.style.position = "relative";
    }
    if (button.parentElement !== dialog) {
      dialog.appendChild(button);
    }

    button.style.display = isTTDDialogOpen() ? "inline-flex" : "none";
  };

  const scheduleEnsure = (() => {
    let rafId = null;
    return () => {
      if (rafId !== null) {
        return;
      }
      rafId = window.requestAnimationFrame(() => {
        rafId = null;
        try {
          ensureButton();
        } catch (_) {}
      });
    };
  })();

  const start = () => {
    ensureButton();
    if (!document.body) {
      return;
    }

    const observer = new MutationObserver(() => {
      scheduleEnsure();
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "style", "aria-hidden"]
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        window.setTimeout(scheduleEnsure, 0);
      }
    }, true);
    window.addEventListener("resize", scheduleEnsure);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
"""#

    /// Adds a lightweight macOS recorder for whiteboard + optional camera bubble.
    /// Output is WebM only for the MVP.
    static let whiteboardRecorderScript = #"""
(() => {
  if (window.__excalidrawZRecorderInstalled) {
    return;
  }
  window.__excalidrawZRecorderInstalled = true;

  const IDS = {
    launcher: "excalidrawz-rec-launcher",
    panel: "excalidrawz-rec-panel",
    close: "excalidrawz-rec-close",
    status: "excalidrawz-rec-status",
    start: "excalidrawz-rec-start",
    stop: "excalidrawz-rec-stop",
    download: "excalidrawz-rec-download",
    camera: "excalidrawz-rec-camera",
    cursor: "excalidrawz-rec-cursor",
    backdrop: "excalidrawz-rec-backdrop",
    style: "excalidrawz-rec-style"
  };

  const state = {
    isOpen: false,
    isRecording: false,
    sourceCanvas: null,
    outputCanvas: null,
    outputCtx: null,
    composedStream: null,
    cameraStream: null,
    cameraVideo: null,
    recorder: null,
    recorderMimeType: "video/webm",
    chunks: [],
    drawRAF: null,
    autoStopTimer: null,
    pointer: {
      x: 0,
      y: 0,
      visible: false,
      movedAt: 0
    },
    options: {
      showCamera: true,
      showCursor: true,
      backdrop: "soft-blue"
    },
    lastBlobURL: null,
    lastFileName: null,
    controls: null
  };

  const MIME_TYPES = [
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm;codecs=vp9",
    "video/webm;codecs=vp8",
    "video/webm"
  ];

  const backdropFill = (ctx, w, h, kind) => {
    if (kind === "none") {
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, w, h);
      return;
    }

    if (kind === "sunset") {
      const gradient = ctx.createLinearGradient(0, 0, w, h);
      gradient.addColorStop(0, "#ffe0b2");
      gradient.addColorStop(0.5, "#ffc0cb");
      gradient.addColorStop(1, "#d1c4e9");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, w, h);
      return;
    }

    if (kind === "slate") {
      const gradient = ctx.createLinearGradient(0, 0, w, h);
      gradient.addColorStop(0, "#e9eef5");
      gradient.addColorStop(1, "#cfd9e8");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, w, h);
      return;
    }

    // soft-blue default
    const gradient = ctx.createLinearGradient(0, 0, w, h);
    gradient.addColorStop(0, "#f8fbff");
    gradient.addColorStop(1, "#e8f0ff");
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);
  };

  const roundedRectPath = (ctx, x, y, width, height, radius) => {
    const r = Math.max(0, Math.min(radius, width / 2, height / 2));
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + r);
    ctx.lineTo(x + width, y + height - r);
    ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    ctx.lineTo(x + r, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  };

  const pickMimeType = () => {
    if (!window.MediaRecorder) {
      return null;
    }
    for (const mimeType of MIME_TYPES) {
      if (MediaRecorder.isTypeSupported(mimeType)) {
        return mimeType;
      }
    }
    return "video/webm";
  };

  const findSceneCanvas = () => {
    const canvases = Array.from(document.querySelectorAll("canvas"));
    if (canvases.length === 0) {
      return null;
    }

    const visibleCanvases = canvases.filter((canvas) => {
      const rect = canvas.getBoundingClientRect();
      if (!rect || rect.width < 120 || rect.height < 120) {
        return false;
      }
      const style = window.getComputedStyle(canvas);
      if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") {
        return false;
      }
      return true;
    });

    visibleCanvases.sort((a, b) => {
      const aRect = a.getBoundingClientRect();
      const bRect = b.getBoundingClientRect();
      return bRect.width * bRect.height - aRect.width * aRect.height;
    });

    return visibleCanvases[0] || null;
  };

  const buildOutputCanvas = (sourceRect) => {
    const sourceAspect = sourceRect.width / sourceRect.height || (16 / 9);
    const baseWidth = Math.max(960, Math.round(sourceRect.width * Math.max(1, window.devicePixelRatio || 1)));
    const width = Math.min(1920, baseWidth);
    const height = Math.max(540, Math.round(width / sourceAspect));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    return canvas;
  };

  const setStatus = (message, isError = false) => {
    if (!state.controls) {
      return;
    }
    state.controls.status.textContent = message;
    state.controls.status.classList.toggle("is-error", isError);
  };

  const updateButtons = () => {
    if (!state.controls) {
      return;
    }
    state.controls.start.disabled = state.isRecording;
    state.controls.stop.disabled = !state.isRecording;
    state.controls.download.disabled = !state.lastBlobURL;
  };

  const cleanupLiveResources = () => {
    if (state.drawRAF !== null) {
      window.cancelAnimationFrame(state.drawRAF);
      state.drawRAF = null;
    }
    if (state.autoStopTimer !== null) {
      window.clearTimeout(state.autoStopTimer);
      state.autoStopTimer = null;
    }

    if (state.recorder && state.recorder.state !== "inactive") {
      try {
        state.recorder.stop();
      } catch (_) {}
    }

    if (state.composedStream) {
      state.composedStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (_) {}
      });
      state.composedStream = null;
    }

    if (state.cameraStream) {
      state.cameraStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (_) {}
      });
      state.cameraStream = null;
    }

    if (state.cameraVideo) {
      try {
        state.cameraVideo.pause();
      } catch (_) {}
      state.cameraVideo.srcObject = null;
      state.cameraVideo = null;
    }

    state.recorder = null;
    state.outputCanvas = null;
    state.outputCtx = null;
    state.sourceCanvas = null;
    state.chunks = [];
  };

  const releaseLastBlob = () => {
    if (!state.lastBlobURL) {
      return;
    }
    try {
      URL.revokeObjectURL(state.lastBlobURL);
    } catch (_) {}
    state.lastBlobURL = null;
    state.lastFileName = null;
  };

  const saveLastBlob = (blob) => {
    releaseLastBlob();
    state.lastBlobURL = URL.createObjectURL(blob);
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    state.lastFileName = `excalidraw-recording-${stamp}.webm`;
    updateButtons();
  };

  const triggerDownload = () => {
    if (!state.lastBlobURL || !state.lastFileName) {
      return;
    }
    const anchor = document.createElement("a");
    anchor.href = state.lastBlobURL;
    anchor.download = state.lastFileName;
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  };

  const drawCursorHighlight = (ctx, canvasRect, board) => {
    if (!state.options.showCursor || !state.pointer.visible) {
      return;
    }

    const freshForMs = 900;
    if (Date.now() - state.pointer.movedAt > freshForMs) {
      return;
    }

    const relX = (state.pointer.x - canvasRect.left) / canvasRect.width;
    const relY = (state.pointer.y - canvasRect.top) / canvasRect.height;
    if (relX < 0 || relX > 1 || relY < 0 || relY > 1) {
      return;
    }

    const x = board.x + relX * board.width;
    const y = board.y + relY * board.height;

    ctx.save();
    ctx.fillStyle = "rgba(76, 132, 255, 0.24)";
    ctx.beginPath();
    ctx.arc(x, y, 26, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "rgba(41, 95, 230, 0.95)";
    ctx.beginPath();
    ctx.arc(x, y, 4.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  };

  const drawCameraBubble = (ctx, boardPadding) => {
    if (!state.options.showCamera || !state.cameraVideo || state.cameraVideo.readyState < 2) {
      return;
    }
    const width = ctx.canvas.width;
    const height = ctx.canvas.height;
    const bubbleSize = Math.round(Math.min(width, height) * 0.2);
    const x = width - boardPadding - bubbleSize;
    const y = boardPadding;
    const radius = bubbleSize / 2;

    ctx.save();
    ctx.beginPath();
    ctx.arc(x + radius, y + radius, radius, 0, Math.PI * 2);
    ctx.closePath();
    ctx.clip();
    ctx.drawImage(state.cameraVideo, x, y, bubbleSize, bubbleSize);
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.94)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(x + radius, y + radius, radius - 1.5, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  };

  const renderFrame = () => {
    if (!state.isRecording || !state.outputCtx) {
      return;
    }

    let sourceCanvas = state.sourceCanvas;
    if (!sourceCanvas || !sourceCanvas.isConnected) {
      sourceCanvas = findSceneCanvas();
      state.sourceCanvas = sourceCanvas;
    }
    if (!sourceCanvas) {
      state.drawRAF = window.requestAnimationFrame(renderFrame);
      return;
    }

    const sourceRect = sourceCanvas.getBoundingClientRect();
    if (!sourceRect || sourceRect.width < 40 || sourceRect.height < 40) {
      state.drawRAF = window.requestAnimationFrame(renderFrame);
      return;
    }

    const ctx = state.outputCtx;
    const outputW = ctx.canvas.width;
    const outputH = ctx.canvas.height;
    backdropFill(ctx, outputW, outputH, state.options.backdrop);

    const pad = Math.round(Math.min(outputW, outputH) * 0.045);
    const aspect = sourceRect.width / sourceRect.height || 1;
    let boardW = outputW - pad * 2;
    let boardH = Math.round(boardW / aspect);
    if (boardH > outputH - pad * 2) {
      boardH = outputH - pad * 2;
      boardW = Math.round(boardH * aspect);
    }
    const boardX = Math.round((outputW - boardW) / 2);
    const boardY = Math.round((outputH - boardH) / 2);

    ctx.save();
    ctx.shadowColor = "rgba(40, 56, 92, 0.2)";
    ctx.shadowBlur = 34;
    ctx.shadowOffsetY = 12;
    roundedRectPath(ctx, boardX, boardY, boardW, boardH, 18);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    ctx.restore();

    ctx.save();
    roundedRectPath(ctx, boardX, boardY, boardW, boardH, 18);
    ctx.clip();
    try {
      ctx.drawImage(
        sourceCanvas,
        0,
        0,
        sourceCanvas.width,
        sourceCanvas.height,
        boardX,
        boardY,
        boardW,
        boardH
      );
    } catch (error) {
      setStatus("Frame capture failed. Check cross-origin images and retry.", true);
      state.isRecording = false;
      updateButtons();
      cleanupLiveResources();
      return;
    }
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = "rgba(31, 51, 94, 0.2)";
    ctx.lineWidth = 1.2;
    roundedRectPath(ctx, boardX, boardY, boardW, boardH, 18);
    ctx.stroke();
    ctx.restore();

    drawCursorHighlight(ctx, sourceRect, {
      x: boardX,
      y: boardY,
      width: boardW,
      height: boardH
    });
    drawCameraBubble(ctx, pad);

    state.drawRAF = window.requestAnimationFrame(renderFrame);
  };

  const prepareCamera = async () => {
    if (!state.options.showCamera) {
      return;
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus("Camera is not available in this environment.", true);
      state.options.showCamera = false;
      if (state.controls) {
        state.controls.camera.checked = false;
      }
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 1280 },
          height: { ideal: 720 },
          facingMode: "user"
        },
        audio: false
      });
      const video = document.createElement("video");
      video.autoplay = true;
      video.muted = true;
      video.playsInline = true;
      video.srcObject = stream;
      await video.play();

      state.cameraStream = stream;
      state.cameraVideo = video;
    } catch (error) {
      setStatus("Camera permission denied. Recording whiteboard only.", false);
      state.options.showCamera = false;
      if (state.controls) {
        state.controls.camera.checked = false;
      }
    }
  };

  const stopRecording = () => {
    if (!state.isRecording) {
      return;
    }
    state.isRecording = false;
    updateButtons();
    setStatus("Finalizing WebM...", false);

    if (state.recorder && state.recorder.state !== "inactive") {
      try {
        state.recorder.stop();
      } catch (_) {
        cleanupLiveResources();
        setStatus("Unable to stop recorder cleanly.", true);
      }
    } else {
      cleanupLiveResources();
    }
  };

  const startRecording = async () => {
    if (state.isRecording) {
      return;
    }
    if (!window.MediaRecorder) {
      setStatus("MediaRecorder is not supported by this runtime.", true);
      return;
    }

    const sourceCanvas = findSceneCanvas();
    if (!sourceCanvas) {
      setStatus("Could not find the whiteboard canvas.", true);
      return;
    }

    const sourceRect = sourceCanvas.getBoundingClientRect();
    if (!sourceRect || sourceRect.width < 120 || sourceRect.height < 120) {
      setStatus("Canvas is not ready yet. Try again in a moment.", true);
      return;
    }

    state.options.showCamera = !!state.controls.camera.checked;
    state.options.showCursor = !!state.controls.cursor.checked;
    state.options.backdrop = state.controls.backdrop.value || "soft-blue";

    cleanupLiveResources();

    state.sourceCanvas = sourceCanvas;
    state.outputCanvas = buildOutputCanvas(sourceRect);
    state.outputCtx = state.outputCanvas.getContext("2d", { alpha: false });
    if (!state.outputCtx) {
      setStatus("Unable to initialize recording canvas.", true);
      return;
    }

    await prepareCamera();

    const mimeType = pickMimeType();
    if (!mimeType) {
      setStatus("No supported WebM mime type was found.", true);
      cleanupLiveResources();
      return;
    }
    state.recorderMimeType = mimeType;
    state.composedStream = state.outputCanvas.captureStream(30);

    let recorder = null;
    try {
      recorder = new MediaRecorder(state.composedStream, {
        mimeType,
        videoBitsPerSecond: 7_500_000
      });
    } catch (_) {
      try {
        recorder = new MediaRecorder(state.composedStream, { mimeType });
      } catch (_) {
        recorder = new MediaRecorder(state.composedStream);
      }
    }
    state.recorder = recorder;
    state.chunks = [];

    recorder.ondataavailable = (event) => {
      if (event.data && event.data.size > 0) {
        state.chunks.push(event.data);
      }
    };
    recorder.onerror = () => {
      setStatus("Recorder runtime error.", true);
    };
    recorder.onstop = () => {
      const blob = new Blob(state.chunks, {
        type: state.recorderMimeType || "video/webm"
      });
      const mb = (blob.size / (1024 * 1024)).toFixed(1);
      if (blob.size > 0) {
        saveLastBlob(blob);
        setStatus(`Recording ready (${mb} MB). Click Download WebM.`, false);
      } else {
        setStatus("No video data was produced.", true);
      }
      cleanupLiveResources();
      updateButtons();
    };

    state.isRecording = true;
    updateButtons();
    setStatus("Recording... WebM capture is running.", false);
    recorder.start(250);
    renderFrame();

    const maxDurationMs = 30 * 60 * 1000;
    state.autoStopTimer = window.setTimeout(() => {
      if (state.isRecording) {
        setStatus("Auto-stopping at 30 minutes to avoid memory issues.", false);
        stopRecording();
      }
    }, maxDurationMs);
  };

  const setOpen = (open) => {
    state.isOpen = open;
    if (!state.controls) {
      return;
    }
    state.controls.panel.classList.toggle("is-open", open);
    state.controls.launcher.classList.toggle("is-open", open);
  };

  const installStyles = () => {
    if (document.getElementById(IDS.style)) {
      return;
    }
    const style = document.createElement("style");
    style.id = IDS.style;
    style.textContent = `
      #${IDS.launcher} {
        position: fixed;
        right: 20px;
        bottom: 20px;
        width: 46px;
        height: 46px;
        border-radius: 14px;
        border: 1px solid rgba(96, 104, 124, 0.45);
        background: rgba(255, 255, 255, 0.92);
        backdrop-filter: blur(10px);
        color: #2a3e72;
        font: 700 12px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: 0.4px;
        cursor: pointer;
        z-index: 90000;
        box-shadow: 0 10px 22px rgba(29, 49, 88, 0.15);
      }
      #${IDS.launcher}.is-open {
        opacity: 0.75;
      }
      #${IDS.panel} {
        position: fixed;
        right: 20px;
        bottom: 76px;
        width: 320px;
        border-radius: 14px;
        border: 1px solid rgba(110, 118, 138, 0.35);
        background: rgba(255, 255, 255, 0.94);
        backdrop-filter: blur(14px);
        color: #1d2436;
        font: 500 13px/1.35 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        box-shadow: 0 18px 36px rgba(29, 49, 88, 0.22);
        display: none;
        z-index: 90001;
      }
      #${IDS.panel}.is-open {
        display: block;
      }
      #${IDS.panel} .rec-head {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 12px;
        border-bottom: 1px solid rgba(96, 104, 124, 0.2);
      }
      #${IDS.panel} .rec-title {
        font: 700 14px/1.2 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      #${IDS.close} {
        border: none;
        background: transparent;
        color: #3b4256;
        font: 500 22px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        width: 28px;
        height: 28px;
        border-radius: 999px;
        cursor: pointer;
      }
      #${IDS.close}:hover {
        background: rgba(0, 0, 0, 0.08);
      }
      #${IDS.panel} .rec-body {
        padding: 11px 12px 12px 12px;
      }
      #${IDS.panel} .rec-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 9px;
      }
      #${IDS.panel} .rec-row input[type="checkbox"] {
        transform: scale(1.02);
      }
      #${IDS.panel} select {
        border: 1px solid rgba(102, 112, 136, 0.35);
        border-radius: 8px;
        padding: 5px 8px;
        min-width: 134px;
        background: #fff;
      }
      #${IDS.status} {
        border-radius: 8px;
        background: rgba(66, 88, 141, 0.08);
        color: #2e4475;
        padding: 8px 9px;
        min-height: 36px;
        margin-bottom: 10px;
      }
      #${IDS.status}.is-error {
        background: rgba(196, 53, 53, 0.1);
        color: #8f2323;
      }
      #${IDS.panel} .rec-actions {
        display: flex;
        gap: 8px;
      }
      #${IDS.panel} .rec-actions button {
        border: none;
        border-radius: 10px;
        padding: 8px 10px;
        font: 600 13px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        cursor: pointer;
      }
      #${IDS.start} {
        background: #3d63dd;
        color: #fff;
        flex: 1;
      }
      #${IDS.stop} {
        background: #f4f6fb;
        color: #2d3654;
      }
      #${IDS.download} {
        background: #f4f6fb;
        color: #2d3654;
        flex: 1;
      }
      #${IDS.panel} .rec-actions button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
      #${IDS.panel} .rec-note {
        margin-top: 9px;
        font-size: 11.5px;
        color: #5a6581;
      }
    `;
    document.head.appendChild(style);
  };

  const installPointerTracking = () => {
    window.addEventListener(
      "pointermove",
      (event) => {
        state.pointer.x = event.clientX;
        state.pointer.y = event.clientY;
        state.pointer.visible = true;
        state.pointer.movedAt = Date.now();
      },
      { passive: true, capture: true }
    );
    window.addEventListener(
      "pointerleave",
      () => {
        state.pointer.visible = false;
      },
      { passive: true, capture: true }
    );
  };

  const mountUI = () => {
    if (!document.body) {
      return;
    }
    if (document.getElementById(IDS.launcher)) {
      return;
    }

    installStyles();

    const launcher = document.createElement("button");
    launcher.id = IDS.launcher;
    launcher.type = "button";
    launcher.textContent = "REC";
    launcher.title = "Open recorder";
    launcher.setAttribute("aria-label", "Open recorder");

    const panel = document.createElement("section");
    panel.id = IDS.panel;
    panel.setAttribute("aria-label", "Whiteboard recorder");
    panel.innerHTML = `
      <div class="rec-head">
        <div class="rec-title">Whiteboard Recorder</div>
        <button id="${IDS.close}" type="button" aria-label="Close recorder panel">×</button>
      </div>
      <div class="rec-body">
        <div class="rec-row">
          <label for="${IDS.camera}">Show camera bubble</label>
          <input id="${IDS.camera}" type="checkbox" checked />
        </div>
        <div class="rec-row">
          <label for="${IDS.cursor}">Show cursor highlight</label>
          <input id="${IDS.cursor}" type="checkbox" checked />
        </div>
        <div class="rec-row">
          <label for="${IDS.backdrop}">Backdrop</label>
          <select id="${IDS.backdrop}">
            <option value="soft-blue">Soft Blue</option>
            <option value="sunset">Sunset</option>
            <option value="slate">Slate</option>
            <option value="none">None</option>
          </select>
        </div>
        <div id="${IDS.status}">Ready. Output format: WebM.</div>
        <div class="rec-actions">
          <button id="${IDS.start}" type="button">Start Recording</button>
          <button id="${IDS.stop}" type="button" disabled>Stop</button>
        </div>
        <div class="rec-actions" style="margin-top: 8px;">
          <button id="${IDS.download}" type="button" disabled>Download WebM</button>
        </div>
        <div class="rec-note">MVP: macOS only, WebM only. Long sessions auto-stop at 30 minutes.</div>
      </div>
    `;

    document.body.appendChild(panel);
    document.body.appendChild(launcher);

    const controls = {
      launcher,
      panel,
      close: panel.querySelector(`#${IDS.close}`),
      status: panel.querySelector(`#${IDS.status}`),
      start: panel.querySelector(`#${IDS.start}`),
      stop: panel.querySelector(`#${IDS.stop}`),
      download: panel.querySelector(`#${IDS.download}`),
      camera: panel.querySelector(`#${IDS.camera}`),
      cursor: panel.querySelector(`#${IDS.cursor}`),
      backdrop: panel.querySelector(`#${IDS.backdrop}`)
    };
    state.controls = controls;

    launcher.addEventListener("click", () => {
      setOpen(!state.isOpen);
    });
    controls.close.addEventListener("click", () => {
      setOpen(false);
    });
    controls.start.addEventListener("click", () => {
      startRecording();
    });
    controls.stop.addEventListener("click", () => {
      stopRecording();
    });
    controls.download.addEventListener("click", () => {
      triggerDownload();
    });

    updateButtons();
  };

  const start = () => {
    mountUI();
    installPointerTracking();
    window.addEventListener("beforeunload", () => {
      stopRecording();
      cleanupLiveResources();
      releaseLastBlob();
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
"""#
}

/// Keep stateless
extension ExcalidrawCore {
    func loadFile(from file: ExcalidrawFile?, force: Bool = false) {
        guard !self.isLoading, !self.webView.isLoading else { return }
        guard let file = file,
              let data = file.content else { return }
        Task.detached {
            do {
                try await self.webActor.loadFile(id: file.id, data: data, force: force)
                
                if await self.parent?.appPreference.useCustomDrawingSettings == true {
                    try await self.applyUserSettings()
                }
            } catch {
                self.publishError(error)
            }
        }
    }
    
    /// Save `currentFile` or creating if neccessary.
    ///
    /// This function will get the local storage of `excalidraw.com`.
    /// Then it will set the data got from local storage to `currentFile`.
    @MainActor
    func saveCurrentFile() async throws {
        let _ = try await self.webView.evaluateJavaScript("window.excalidrawZHelper.saveFile(); 0;")
    }
    
    /// `true` if is dark mode.
    @MainActor
    func getIsDark() async throws -> Bool {
        if self.webView.isLoading { return false }
        let res = try await self.webView.evaluateJavaScript("window.excalidrawZHelper.getIsDark()")
        if let isDark = res as? Bool {
            return isDark
        } else {
            return false
        }
    }
    
    @MainActor
    func changeColorMode(dark: Bool) async throws {
        if self.webView.isLoading { return }
        let isDark = try await getIsDark()
        guard isDark != dark else { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleColorTheme(\"\(dark ? "dark" : "light")\"); 0;")
    }
    
    /// Make Image be the same as light mode.
    /// autoInvert: Invert the current inverted image in dark mode.
    @available(*, deprecated, message: "Excalidraw now support natively")
    @MainActor
    func toggleInvertImageSwitch(autoInvert: Bool) async throws {
        if self.webView.isLoading { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleImageInvertSwitch(\(autoInvert)); 0;")
    }
    @available(*, deprecated, message: "Excalidraw now support natively")
    @MainActor
    func applyAntiInvertImageSettings(payload: AntiInvertImageSettings) async throws {
        if self.webView.isLoading { return }
        let payload = try payload.jsonStringified()
        // print("[applyAntiInvertImageSettings] payload: ", payload)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleAntiInvertImageSettings(\(payload)); 0;")
    }
    
    @MainActor
    func loadLibraryItem(item: ExcalidrawLibrary) async throws {
        try await self.webView.evaluateJavaScript("window.excalidrawZHelper.loadLibraryItem(\(item.jsonStringified())); 0;")
    }
    
    @MainActor
    func exportPNG() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.exportImage(); 0;")
    }
    
    func exportPNGData() async throws -> Data? {
        guard let file = await self.parent?.file else {
            return nil
        }
        let imageData = try await self.exportElementsToPNGData(elements: file.elements, colorScheme: .light)
        return imageData //NSImage(data: imageData)
    }
    
    @MainActor
    func toggleToolbarAction(key: Int) async throws {
        print(#function, key)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction(\(key)); 0;")
    }
    
    @MainActor
    func toggleToolbarAction(key: Character) async throws {
        guard !self.isLoading else { return }
        print(#function, key)
        if key == "\u{1B}" {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Escape'); 0;")
        } else if key == " " {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Space'); 0;")
        } else {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('\(key.uppercased())'); 0;")
        }
    }
    
    @MainActor
    func toggleDeleteAction() async throws {
        guard !self.isLoading else { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Backspace'); 0;")
    }
    
    enum ExtraTool: String {
        case webEmbed = "webEmbed"
        case text2Diagram = "text2diagram"
        case mermaid = "mermaid"
        case magicFrame = "wireframe"
    }
    @MainActor
    func toggleToolbarAction(tool: ExtraTool) async throws {
        guard !self.isLoading else { return }
        print(#function, tool)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('\(tool.rawValue)'); 0;")
    }
    
    func exportElementsToPNGData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let id = UUID().uuidString
        let script = try """
window.excalidrawZHelper.exportElementsToBlob(
    '\(id)', \(elements.jsonStringified()), 
    \(files?.jsonStringified() ?? "undefined"), 
    {
        exportEmbedScene: \(embedScene),
        withBackground: \(withBackground), 
        exportWithDarkMode: \(colorScheme == .dark),
        mimeType: 'image/png',
        quality: 100,
    }
); 
0;
"""
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
//        let dataString: String = await withCheckedContinuation { continuation in
//            blobRequestQueue.async {
//                self.flyingBlobsRequest[id] = { data in
//                    continuation.resume(returning: data)
//                    self.flyingBlobsRequest.removeValue(forKey: id)
//                }
//            }
//        }
        let dataString = await exportImageManager.requestExport(id: id)
        guard let data = Data(base64Encoded: dataString) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }
    
    func exportElementsToPNG(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await self.exportElementsToPNGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }
    
    func exportElementsToSVGData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let id = UUID().uuidString
        let script = try "window.excalidrawZHelper.exportElementsToSvg('\(id)', \(elements.jsonStringified()), \(files?.jsonStringified() ?? "undefined"), \(embedScene), \(withBackground), \(colorScheme == .dark)); 0;"
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let svg = await exportImageManager.requestExport(id: id)
        let minisizedSvg = removeWidthAndHeight(from: svg).trimmingCharacters(in: .whitespacesAndNewlines)
        
        func removeWidthAndHeight(from svgContent: String) -> String {
            // 正则表达式确保匹配 `<svg>` 标签上的 width 和 height 属性
            let regexPattern = #"<svg([^>]*)\s+(width="[^"]*")\s*([^>]*)>"#
            
            do {
                // 创建正则表达式
                let regex = try NSRegularExpression(pattern: regexPattern, options: [])
                
                // 替换 `width` 和 `height`，保留 `<svg>` 标签其他属性
                let tempResult = regex.stringByReplacingMatches(
                    in: svgContent,
                    options: [],
                    range: NSRange(location: 0, length: svgContent.utf16.count),
                    withTemplate: "<svg$1 $3>"
                )
                
                // 再次处理可能分开的 height
                let finalRegexPattern = #"<svg([^>]*)\s+(height="[^"]*")\s*([^>]*)>"#
                let finalResult = try NSRegularExpression(pattern: finalRegexPattern, options: []).stringByReplacingMatches(
                    in: tempResult,
                    options: [],
                    range: NSRange(location: 0, length: tempResult.utf16.count),
                    withTemplate: "<svg$1 $3>"
                )
                
                return finalResult
            } catch {
                print("Error creating regex: \(error)")
                return svgContent
            }
        }
        
        guard let data = minisizedSvg.data(using: .utf8) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
        
    }
    func exportElementsToSVG(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await exportElementsToSVGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
        
    }
    
    /// Get Excadliraw Indexed DB Data
    func getExcalidrawStore() async throws -> [ExcalidrawFile.ResourceFile] {
        print(#function)
        
        let id = UUID().uuidString
        
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript("window.excalidrawZHelper.getAllMedias('\(id)'); 0;")
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        
        let files: [ExcalidrawFile.ResourceFile] = await allMediaTransferManager.requestExport(id: id)
        return files
    }
    
    /// Insert media files to IndexedDB
    @MainActor
    func insertMediaFiles(_ files: [ExcalidrawFile.ResourceFile]) async throws {
        logger.info("insertMediaFiles: \(files.count)")
        let jsonStringified = try files.jsonStringified()
        try await webView.evaluateJavaScript("window.excalidrawZHelper.insertMedias('\(jsonStringified)'); 0;")
    }

    /// Inject all MediaItems from CoreData to IndexedDB
    /// This method fetches all MediaItems and injects them into the WebView's IndexedDB
    /// Most work (fetching, loading files) runs on background threads for better performance
    /// - Returns: The count of injected MediaItems
    func injectAllMediaItems() async throws -> Int {
        logger.info("Starting MediaItem injection...")

        // Check WebView readiness on main thread
        let isReady = await MainActor.run {
            !isNavigating && (hasInjectIndexedDBData || isDocumentLoaded)
        }

        guard isReady else {
            logger.warning("WebView not ready for MediaItem injection, skipping")
            return 0
        }

        let context = PersistenceController.shared.newTaskContext()
        let allMedias = try await context.perform {
            let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            return try context.fetch(allMediasFetch)
        }
        let allMediaIDs = allMedias.compactMap(\.id)
        
        logger.info("Fetched \(allMedias.count) MediaItems from CoreData")

        // Load media items using async method with iCloud Drive support (concurrent)
        // This can run on background threads for better performance
        let mediaFiles = await withTaskGroup(of: ExcalidrawFile.ResourceFile?.self) { group in
            var files: [ExcalidrawFile.ResourceFile] = []
            
            for id in allMedias.map({$0.objectID}) {
                group.addTask {
                    if let mediaItem = context.object(with: id) as? MediaItem {
                        return try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem)
                    }
                    return nil
                }
            }

            for await resourceFile in group {
                if let resourceFile = resourceFile {
                    files.append(resourceFile)
                }
            }

            return files
        }

        // Insert to IndexedDB and update state on main thread
        await MainActor.run {
            Task { @MainActor in
                try? await self.insertMediaFiles(mediaFiles)
            }
            // Update loaded IDs
            self.loadedMediaItemIDs = Set(allMediaIDs)
            self.hasInjectIndexedDBData = true
        }

        logger.info("Successfully injected \(mediaFiles.count) MediaItems")
        return mediaFiles.count
    }

    /// Check if MediaItems have changed and re-inject if needed
    /// This is the public method that should be called when MediaItem changes are detected
    public func refreshMediaItemsIfNeeded() async throws {
        // Get current MediaItem IDs from CoreData on main thread
        let (currentIDs, loadedIDs) = try await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            fetchRequest.propertiesToFetch = ["id"]

            let currentMedias = try context.fetch(fetchRequest)
            let currentIDs = Set(currentMedias.compactMap { $0.id })

            return (currentIDs, self.loadedMediaItemIDs)
        }

        // Check if there are changes
        let hasChanges = currentIDs != loadedIDs

        if hasChanges {
            let addedCount = currentIDs.subtracting(loadedIDs).count
            let removedCount = loadedIDs.subtracting(currentIDs).count
            logger.info("MediaItem changes detected: +\(addedCount) added, -\(removedCount) removed, re-injecting...")

            _ = try await injectAllMediaItems()
        } else {
            logger.debug("No MediaItem changes detected, skipping injection")
        }
    }

    @MainActor
    func performUndo() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.undo(); 0;")
    }
    @MainActor
    func performRedo() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.redo(); 0;")
    }
    @MainActor
    func connectPencil(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.connectPencil(\(enabled)); 0;")
    }
    @MainActor
    func togglePenMode(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.togglePenMode(\(enabled)); 0;")
    }
    @MainActor
    public func toggleActionsMenu(isPresented: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleActionsMenu(\(isPresented)); 0;")
    }
    @MainActor
    public func togglePencilInterationMode(mode: ToolState.PencilInteractionMode) async throws {
        try await webView.evaluateJavaScript(
            "window.excalidrawZHelper.togglePencilInterationMode(\(mode.rawValue)); 0;"
        )
    }
    @MainActor
    public func loadImageToExcalidrawCanvas(imageData: Data, type: String) async throws {
        var buffer = [UInt8].init(repeating: 0, count: imageData.count)
        imageData.copyBytes(to: &buffer, count: imageData.count)
        let buf = buffer
        try await webView.evaluateJavaScript("window.excalidrawZHelper.loadImageBuffer(\(buf), '\(type)'); 0;")
    }
    
    // Font
    @MainActor
    public func setAvailableFonts(fontFamilies: [String]) async throws {
        // NSFontManager.shared.availableFontFamilies.sorted()
        try await webView.evaluateJavaScript("window.excalidrawZHelper.setAvailableFonts(\(fontFamilies)); 0;")
    }
    
    
    // Collab
    @MainActor
    public func openCollabMode() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.openCollabMode(); 0;")
    }
    
    struct CollaborationInfo: Codable, Hashable {
        var username: String
    }
    
    @MainActor
    public func getCollaborationInfo() async throws -> CollaborationInfo {
        guard let res = try await webView.evaluateJavaScript("window.excalidrawZHelper.getExcalidrawCollabInfo();") else {
            return CollaborationInfo(username: "")
        }
        if JSONSerialization.isValidJSONObject(res) {
            let data = try JSONSerialization.data(withJSONObject: res)
            return try JSONDecoder().decode(CollaborationInfo.self, from: data)
        } else {
            return CollaborationInfo(username: "")
        }
    }
    
    
    @MainActor
    public func setCollaborationInfo(_ info: CollaborationInfo) async throws {
        try await webView.evaluateJavaScript(
            "window.excalidrawZHelper.setExcalidrawCollabInfo(\(info.jsonStringified())); 0;"
        )
    }
    
    @MainActor
    public func followCollborator(_ collaborator: Collaborator) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.followCollaborator(\(collaborator.jsonStringified())); 0;")
    }
    
    
    
    @MainActor
    func reload() {
         webView.evaluateJavaScript("location.reload(); 0;")
    }
    
    @MainActor
    func toggleWebPointerEvents(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("document.body.style = '\(enabled ? "" : "pointer-events: none;")'; 0;")
    }
}
