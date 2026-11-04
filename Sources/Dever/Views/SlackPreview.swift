import AppKit
import PDFKit
import Quartz
import SwiftUI

/// A Slack file read here, not in Slack: Quick Look over the original, downloaded once with
/// the token and kept under Application Support. Pictures, PDFs, documents alike.
struct FilePreviewSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let file: SlackFile
    @State private var local: URL?
    @State private var error: String?

    private var detail: String {
        [file.filetype?.uppercased(), file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let screen = NSApp.keyWindow?.frame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: file.isImage ? "photo" : "doc").font(.system(size: 13)).foregroundStyle(Soot.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(Soot.muted) }
                }
                Spacer()
                if let local {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([local]) } label: { Text("Show in Finder") }
                        .buttonStyle(.plain).handCursor().font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.muted)
                        .modifier(FocusOutline(radius: 4))
                }
                if let url = file.permalink.flatMap(URL.init(string:)) {
                    Link(destination: url) { HStack(spacing: 4) { Text("Open in Slack"); Image(systemName: "arrow.up.right") } }
                        .handCursor().font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.lime)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Soot.ink)
                        .frame(width: 30, height: 30).background(Soot.surface, in: Circle())
                }
                .buttonStyle(.plain).handCursor().modifier(FocusOutline(radius: 15))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close the preview")
            }
            .padding(.horizontal, 20).frame(height: 60)
            Rectangle().fill(Soot.line).frame(height: 1)
            Group {
                if let local {
                    if file.mimetype?.hasPrefix("image/") == true {
                        ImagePreview(url: local, name: file.displayName)
                    } else if file.mimetype == "application/pdf" || file.filetype == "pdf" {
                        PDFPreview(url: local)
                    } else {
                        QuickLookPreview(url: local)
                    }
                } else if let error {
                    VStack(spacing: 6) {
                        Text("Couldn't load the file.").font(.system(size: 14, weight: .semibold)).foregroundStyle(Soot.ink)
                        Text(error).font(.system(size: 12)).foregroundStyle(Soot.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack { WaitingLine().frame(width: 160) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement().accessibilityLabel("Loading the file")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
        }
        .frame(width: min(1280, screen.width * 0.86), height: min(900, screen.height * 0.88))
        .background(Soot.ground)
        .task(id: file.id) {
            do { local = try await app.withSlack { try await SlackMediaCache.shared.localFile(for: file, client: $0) } }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// A picture at its natural size, scaled down to fit; decoded off the main thread.
struct ImagePreview: View {
    let url: URL
    let name: String
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: min(geo.size.width - 40, image.size.width), maxHeight: min(geo.size.height - 40, image.size.height))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel(name)
                } else {
                    WaitingLine().frame(width: 160)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            image = loaded
        }
    }
}

/// PDFKit for documents: pages, zoom and text selection.
struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// Quick Look's own view, as it draws any file type the system knows.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as QLPreviewItem }
    }
}
