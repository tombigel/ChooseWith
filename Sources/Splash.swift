// Splash screen shown briefly when the app is opened directly (not at login and not
// when opening a file, so the popup itself is never delayed).

import AppKit
import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            Text("Open With Popup")
                .font(.system(size: 26, weight: .bold))
            Text("Choose which app opens a file, every time.")
                .foregroundStyle(.secondary)
            Text("Made by \(Credits.author) · \(Credits.websiteName) · Version \(Credits.version)")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(.horizontal, 48).padding(.vertical, 36)
        .frame(width: 420)
        .background(
            VisualEffect().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class SplashController {
    private var panel: NSPanel?
    private var finished = false
    private var completion: (() -> Void)?

    /// Shows the splash, then calls `completion` once it has faded out.
    func show(hold: TimeInterval = 1.5, completion: @escaping () -> Void) {
        self.completion = completion
        let host = NSHostingView(rootView: SplashView())
        host.frame.size = host.fittingSize

        let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentView = host
        panel.center()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        // A click dismisses it early.
        let click = NSClickGestureRecognizer(target: self, action: #selector(dismiss))
        host.addGestureRecognizer(click)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + hold) { [weak self] in self?.dismiss() }
    }

    @objc private func dismiss() {
        guard !finished, let panel else { return }
        finished = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
            self?.completion?()
            self?.completion = nil
        })
    }
}
