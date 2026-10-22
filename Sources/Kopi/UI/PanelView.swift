import SwiftUI
import AppKit
import KopiKit

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var prefs = Prefs.shared
    @FocusState private var searchFocused: Bool
    @State private var hoverID: Int64?

    var t: Theme { prefs.theme }

    var body: some View {
        ZStack {
            VisualEffect(material: t.dark ? .hudWindow : .popover)
            t.tint.opacity(t.tintOpacity)
            VStack(spacing: 0) {
                searchBar
                FilterChips(model: model, theme: t)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(t.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    list
                        .frame(width: model.showPreview ? 330 : nil)
                    if model.showPreview {
                        Rectangle().fill(t.hairline).frame(width: 1)
                        PreviewPane(clip: model.selected, model: model, theme: t)
                            .frame(maxWidth: .infinity)
                    }
                }
                Rectangle().fill(t.hairline).frame(height: 1)
                footer
            }
            if model.quickLook, let c = model.selected {
                QuickLookOverlay(clip: c, theme: t).onTapGesture { model.quickLook = false }
            }
            if let c = model.editing {
                EditOverlay(clip: c, model: model, theme: t).transition(.opacity)
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(t.text)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(t.dark ? Color.black.opacity(0.55) : Color.white.opacity(0.9)))
                        .overlay(Capsule().strokeBorder(t.hairline))
                        .padding(.bottom, 36)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(t.dark ? 0.10 : 0.0), lineWidth: 1))
        .environment(\.colorScheme, t.dark ? .dark : .light)
        .animation(.easeOut(duration: 0.12), value: model.toast)
        .animation(.easeOut(duration: 0.12), value: model.editing?.id)
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.tertiary)
            TextField("", text: $model.query, prompt: Text("Search \(model.totalCount) clips").foregroundStyle(t.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(t.text)
                .focused($searchFocused)
            if !prefs.recording {
                Label("Paused", systemImage: "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                    .help("Recording is paused — click to resume")
                    .onTapGesture { prefs.recording = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    if model.visible.isEmpty {
                        EmptyState(theme: t, searching: !model.query.isEmpty || model.filter != .all, recording: prefs.recording)
                    }
                    if !model.pinnedVisible.isEmpty {
                        SectionHeader(title: "Pinned", count: model.pinnedVisible.count, theme: t)
                        ForEach(model.pinnedVisible) { row($0) }
                    }
                    if !model.recentVisible.isEmpty {
                        SectionHeader(title: model.query.isEmpty ? "Recent" : "Results", count: model.recentVisible.count, theme: t)
                        ForEach(model.recentVisible) { row($0) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .mask(VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
            })
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }

    private func row(_ c: Clip) -> some View {
        ClipRow(clip: c, model: model, theme: t, selected: c.id == model.selectedID, hovered: c.id == hoverID,
                shortcut: model.shortcutIndex(c).map(PanelModel.shortcutLabel))
            .id(c.id)
            .onHover { inside in if inside { hoverID = c.id } else if hoverID == c.id { hoverID = nil } }
            .onTapGesture(count: 2) { model.paste(c) }
            .simultaneousGesture(TapGesture().onEnded {
                model.selectedID = c.id
                if prefs.singleClickPaste { model.paste(c) }
            })
            .contextMenu { ClipMenu(clip: c, model: model) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            KeyHint(keys: "↩", label: prefs.pasteDirectly ? "Paste" : "Copy", theme: t)
            KeyHint(keys: "⌘P", label: model.selected?.pinned == true ? "Unpin" : "Pin", theme: t)
            KeyHint(keys: "␣", label: "Preview", theme: t)
            Spacer()
            Button { model.showPreview.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.showPreview ? t.secondary : t.tertiary)
            }
            .buttonStyle(.plain)
            .help("Toggle preview (⌘\\)")
            Button { model.settingsHandler?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.tertiary)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}

// MARK: - Pieces

struct FilterChips: View {
    @ObservedObject var model: PanelModel
    let theme: Theme
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Filter.allCases) { f in
                Text(f.label)
                    .font(.system(size: 10.5, weight: model.filter == f ? .semibold : .regular))
                    .foregroundStyle(model.filter == f ? theme.text : theme.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(model.filter == f ? theme.field : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { model.filter = f }
            }
        }
        .help("⇥ / ⇧⇥ to switch")
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    let theme: Theme
    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.tertiary)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.tertiary.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 2)
    }
}

struct ClipRow: View {
    let clip: Clip
    @ObservedObject var model: PanelModel
    let theme: Theme
    let selected: Bool
    let hovered: Bool
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            leading
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(text: clip.title, query: model.query, theme: theme)
                    .font(.system(size: 13, weight: clip.name != nil ? .medium : .regular,
                                  design: clip.kind == .code && clip.name == nil ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if clip.name != nil {
                    Text(Clip.oneLine(clip.content, limit: 120))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent.opacity(0.85))
                    .rotationEffect(.degrees(35))
            }
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(selected ? theme.secondary : theme.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
            } else {
                Text(RelativeTime.short(clip.lastUsed))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(theme.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: clip.name != nil ? 38 : 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? theme.selection : (hovered ? theme.hover : .clear))
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        if clip.kind == .color, let c = ColorParse.color(clip.content) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.2)))
                .frame(width: 13, height: 13)
        } else if let icon = model.icon(for: clip.sourceBundle) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                .opacity(selected ? 1 : 0.9)
        } else {
            Image(systemName: clip.kind.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiary)
        }
    }
}

struct HighlightedText: View {
    let text: String
    let query: String
    let theme: Theme
    var body: some View {
        Text(attributed).foregroundStyle(theme.text)
    }
    var attributed: AttributedString {
        var a = AttributedString(text)
        guard !query.isEmpty else { return a }
        for r in ClipSearch.highlightRanges(in: text, query: query) {
            guard let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
            a[lo..<hi].foregroundColor = theme.accent
            a[lo..<hi].font = .system(size: 13, weight: .semibold)
        }
        return a
    }
}

struct KeyHint: View {
    let keys: String
    let label: String
    let theme: Theme
    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.secondary)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.tertiary)
        }
    }
}

struct EmptyState: View {
    let theme: Theme
    let searching: Bool
    let recording: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(theme.tertiary)
            Text(searching ? "No matches" : "Nothing copied yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondary)
            Text(searching ? "Try fewer words, or app:chrome / type:link" : (recording ? "Copy something and it shows up here" : "Recording is paused"))
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
}

struct ClipMenu: View {
    let clip: Clip
    @ObservedObject var model: PanelModel
    var body: some View {
        Button("Paste") { model.paste(clip) }
        Button("Paste as Plain Text") { model.paste(clip, plain: true) }
        Button("Copy") { model.copy(clip) }
        Divider()
        Button(clip.pinned ? "Unpin" : "Pin") { model.togglePin(clip) }
        if clip.pinned {
            Button("Move Up") { model.movePinned(clip, by: -1) }
            Button("Move Down") { model.movePinned(clip, by: 1) }
        }
        Button("Edit…") { model.beginEdit(clip) }
        if clip.rtf != nil { Button("Make Plain Text") { model.makePlain(clip) } }
        if clip.kind == .link, let url = URL(string: clip.content.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            Button("Open Link") { NSWorkspace.shared.open(url); model.closeHandler?() }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(clip) }
    }
}

enum ColorParse {
    static func color(_ s: String) -> Color? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        var hex = String(t.dropFirst())
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        let hasA = hex.count == 8
        let r = Double((v >> (hasA ? 24 : 16)) & 0xFF) / 255
        let g = Double((v >> (hasA ? 16 : 8)) & 0xFF) / 255
        let b = Double((v >> (hasA ? 8 : 0)) & 0xFF) / 255
        let a = hasA ? Double(v & 0xFF) / 255 : 1
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
