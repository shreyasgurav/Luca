import AppKit
import QuartzCore

protocol SelectionOverlayDelegate: AnyObject {
    func selectionOverlayDidFinish(_ overlay: SelectionOverlayWindow, rectInWindow: CGRect)
    func selectionOverlayDidCancel(_ overlay: SelectionOverlayWindow)
    func selectionOverlayDidCopy(_ overlay: SelectionOverlayWindow, rectInWindow: CGRect)
}

final class SelectionOverlayWindow: NSWindow {
    weak var selectionDelegate: SelectionOverlayDelegate?

    private let selectionView = SelectionOverlayView(frame: .zero)

    init(screen: NSScreen) {
        let screenFrame = screen.frame
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screenFrame, display: true)
        isOpaque = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false

        contentView = selectionView
        selectionView.wantsLayer = true
        selectionView.onFinish = { [weak self] rect in
            guard let self else { return }
            self.selectionDelegate?.selectionOverlayDidFinish(self, rectInWindow: rect)
        }
        selectionView.onCancel = { [weak self] in
            guard let self else { return }
            self.selectionDelegate?.selectionOverlayDidCancel(self)
        }
        selectionView.onCopy = { [weak self] rect in
            guard let self else { return }
            self.selectionDelegate?.selectionOverlayDidCopy(self, rectInWindow: rect)
        }
    }
}

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: ((CGRect) -> Void)?

    private var isDragging = false
    private var isResizing = false
    private var activeHandleIndex: Int? // 0..7
    private var startPoint: CGPoint = .zero
    private var currentRect: CGRect = .zero { didSet { needsDisplay = true; layoutToolbar() } }

    private let scrimColor = NSColor.black.withAlphaComponent(0.3)
    private let borderColor = NSColor.white

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        ctx.setFillColor(scrimColor.cgColor)
        ctx.fill(bounds)

        if !currentRect.isEmpty {
            // Clear selection area
            ctx.clear(currentRect)

            // Draw border
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(currentRect)

            // Draw dimensions readout near cursor/top-left
            let pxSize = pixelSize(for: currentRect)
            let text = "\(Int(pxSize.width)) × \(Int(pxSize.height)) px"
            drawReadout(text: text, at: CGPoint(x: currentRect.minX + 6, y: currentRect.maxY + 6))

            // Draw 8 handles
            drawHandles(in: currentRect, context: ctx)
        }
    }

    private func pixelSize(for rect: CGRect) -> CGSize {
        guard let screen = window?.screen else { return rect.size }
        let scale = screen.backingScaleFactor
        return CGSize(width: rect.width * scale, height: rect.height * scale)
    }

    private func drawReadout(text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let bgRect = CGRect(x: point.x, y: point.y, width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.6).setFill()
        bgRect.fill()
        str.draw(at: CGPoint(x: point.x + 5, y: point.y + 3))
    }

    // MARK: - Handles
    private func handleRects(for rect: CGRect) -> [CGRect] {
        let s: CGFloat = 8
        let midX = rect.midX, midY = rect.midY
        let pts: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: midY)
        ]
        return pts.map { CGPoint(x: $0.x - s/2, y: $0.y - s/2) }.map { CGRect(origin: $0, size: CGSize(width: s, height: s)) }
    }

    private func drawHandles(in rect: CGRect, context ctx: CGContext) {
        NSColor.white.setFill()
        for r in handleRects(for: rect) { NSBezierPath(rect: r).fill() }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !currentRect.isEmpty {
            let handles = handleRects(for: currentRect)
            if let idx = handles.firstIndex(where: { $0.insetBy(dx: -4, dy: -4).contains(p) }) {
                isResizing = true
                activeHandleIndex = idx
                startPoint = p
                return
            }
        }
        isDragging = true
        startPoint = p
        currentRect = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if isResizing, let idx = activeHandleIndex {
            currentRect = resizeRect(currentRect, handleIndex: idx, to: p, maintainAspect: event.modifierFlags.contains(.shift))
        } else if isDragging {
            currentRect = CGRect(x: min(startPoint.x, p.x), y: min(startPoint.y, p.y), width: abs(p.x - startPoint.x), height: abs(p.y - startPoint.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            if currentRect.width < 2 || currentRect.height < 2 {
                onCancel?()
            } else {
                showToolbar()
            }
        } else if isResizing {
            isResizing = false
            activeHandleIndex = nil
            showToolbar()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc
            onCancel?()
        case 36: // return
            if !currentRect.isEmpty { onFinish?(currentRect) }
        case 123: // left
            currentRect.origin.x -= event.modifierFlags.contains(.shift) ? 10 : 1
        case 124: // right
            currentRect.origin.x += event.modifierFlags.contains(.shift) ? 10 : 1
        case 125: // down
            currentRect.origin.y -= event.modifierFlags.contains(.shift) ? 10 : 1
        case 126: // up
            currentRect.origin.y += event.modifierFlags.contains(.shift) ? 10 : 1
        case 8: // c key = copy
            if !currentRect.isEmpty { onCopy?(currentRect) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Resize logic
    private func resizeRect(_ rect: CGRect, handleIndex: Int, to point: CGPoint, maintainAspect: Bool) -> CGRect {
        var r = rect
        let originalAspect = rect.width != 0 ? rect.height / rect.width : 1
        switch handleIndex {
        case 0: // bottom-left
            r.origin.x = min(point.x, rect.maxX)
            r.origin.y = min(point.y, rect.maxY)
            r.size.width = rect.maxX - r.origin.x
            r.size.height = rect.maxY - r.origin.y
        case 1: // bottom-center
            r.origin.y = min(point.y, rect.maxY)
            r.size.height = rect.maxY - r.origin.y
        case 2: // bottom-right
            r.origin.y = min(point.y, rect.maxY)
            r.size.width = max(point.x - rect.minX, 1)
            r.size.height = rect.maxY - r.origin.y
        case 3: // mid-right
            r.size.width = max(point.x - rect.minX, 1)
        case 4: // top-right
            r.size.width = max(point.x - rect.minX, 1)
            r.size.height = max(point.y - rect.minY, 1)
        case 5: // top-center
            r.size.height = max(point.y - rect.minY, 1)
        case 6: // top-left
            r.origin.x = min(point.x, rect.maxX)
            r.size.width = rect.maxX - r.origin.x
            r.size.height = max(point.y - rect.minY, 1)
        case 7: // mid-left
            r.origin.x = min(point.x, rect.maxX)
            r.size.width = rect.maxX - r.origin.x
        default:
            break
        }
        if maintainAspect {
            let newAspect = r.height / max(r.width, 1)
            if newAspect > originalAspect {
                r.size.height = r.width * originalAspect
            } else {
                r.size.width = r.height / originalAspect
            }
        }
        return r.standardized
    }

    // MARK: - Toolbar
    private lazy var toolbar: NSView = makeToolbar()
    private func makeToolbar() -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        view.layer?.cornerRadius = 8

        let send = NSButton(title: "Send", target: self, action: #selector(tapSend))
        let copy = NSButton(title: "Copy", target: self, action: #selector(tapCopy))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(tapCancel))
        for (i, b) in [send, copy, cancel].enumerated() {
            b.bezelStyle = .rounded
            b.setButtonType(.momentaryPushIn)
            b.frame = CGRect(x: 8 + CGFloat(i) * 72, y: 6, width: 64, height: 24)
            view.addSubview(b)
        }
        view.frame = CGRect(x: 0, y: 0, width: 8 + 3*72, height: 36)
        return view
    }

    private func showToolbar() {
        if toolbar.superview == nil { addSubview(toolbar) }
        layoutToolbar()
    }

    private func layoutToolbar() {
        guard toolbar.superview === self, !currentRect.isEmpty else { return }
        let margin: CGFloat = 8
        var origin = CGPoint(x: currentRect.maxX - toolbar.frame.width, y: currentRect.minY - toolbar.frame.height - margin)
        if origin.y < 0 { origin.y = currentRect.maxY + margin }
        if origin.x < 0 { origin.x = currentRect.minX }
        toolbar.setFrameOrigin(origin)
    }

    @objc private func tapSend() { if !currentRect.isEmpty { onFinish?(currentRect) } }
    @objc private func tapCopy() { if !currentRect.isEmpty { onCopy?(currentRect) } }
    @objc private func tapCancel() { onCancel?() }
}


