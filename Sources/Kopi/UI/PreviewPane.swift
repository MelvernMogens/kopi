import SwiftUI
import AppKit
import KopiKit

struct PreviewPane: View {
    let clip: Clip?
    @ObservedObject var model: PanelModel
    let theme: Theme

    var body: some View {
        if let c = clip {
            VStack(alignment: .leading, spacing: 0) {
                content(c)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(theme.hairline).frame(height: 1)
                meta(c)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder private func content(_ c: Clip) -> some View {
        switch c.kind {
        case .color:
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ColorParse.color(c.content) ?? .gray)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline))
                    .frame(height: 120)
                Text(c.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
            }
            .padding(14)
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                let s = c.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let u = URL(string: s), let host = u.host {
                    HStack(spacing: 6) {
                        Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(theme.accent)
                        Text(host).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                    }
                }
                ScrollView {
                    Text(s)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        default:
            ScrollView([.vertical]) {
                Text(previewText(c))
                    .font(mono(c) ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5))
                    .lineSpacing(mono(c) ? 2 : 3)
                    .foregroundStyle(theme.text.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .scrollIndicators(.automatic)
            .mask(VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 20)
            })
        }
    }

    private func mono(_ c: Clip) -> Bool { c.kind == .code || c.kind == .path || ClipKind.looksLikeTerminal(c.content) }

    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM, HH:mm"; return f
    }()

    private func previewText(_ c: Clip) -> String {
        c.content.count > 20_000 ? String(c.content.prefix(20_000)) + "\n\n… (\(c.content.count - 20_000) more characters)" : c.content
    }

    private func meta(_ c: Clip) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Source") {
                HStack(spacing: 5) {
                    if let i = model.icon(for: c.sourceBundle) { Image(nsImage: i).resizable().frame(width: 12, height: 12) }
                    Text(c.sourceName ?? "Unknown")
                }
            }
            row("Type") { Text(c.rtf != nil ? "\(c.kind.label) · rich text" : c.kind.label) }
            row("Size") { Text(c.lineCount > 1 ? "\(c.content.count) chars · \(c.lineCount) lines" : "\(c.content.count) chars · \(c.wordCount) words") }
            row("Copied") { Text(Self.stamp.string(from: c.created) + " · " + RelativeTime.short(c.created) + (RelativeTime.short(c.created) == "now" ? "" : " ago")) }
            if c.pasteCount > 0 { row("Pasted") { Text("\(c.pasteCount)×") } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row<V: View>(_ k: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(spacing: 0) {
            Text(k).foregroundStyle(theme.tertiary).frame(width: 56, alignment: .leading)
            v().foregroundStyle(theme.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }
}

/// Full-panel preview (Space), like Quick Look in CopyClip.
struct QuickLookOverlay: View {
    let clip: Clip
    let theme: Theme
    var body: some View {
        ZStack {
            (theme.dark ? Color.black.opacity(0.35) : Color.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(clip.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                    Spacer()
                    Text("Space to close").font(.system(size: 10.5)).foregroundStyle(theme.tertiary)
                }
                .padding(.horizontal, 14).frame(height: 34)
                Rectangle().fill(theme.hairline).frame(height: 1)
                ScrollView {
                    Text(clip.content.count > 100_000 ? String(clip.content.prefix(100_000)) : clip.content)
                        .font(clip.kind == .code || clip.kind == .path ? .system(size: 12, design: .monospaced) : .system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tint.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline))
            .padding(8)
        }
    }
}

struct EditOverlay: View {
    let clip: Clip
    @ObservedObject var model: PanelModel
    let theme: Theme
    @State private var name: String
    @State private var content: String
    @FocusState private var focus: Field?
    enum Field { case name, content }

    init(clip: Clip, model: PanelModel, theme: Theme) {
        self.clip = clip
        self.model = model
        self.theme = theme
        _name = State(initialValue: clip.name ?? "")
        _content = State(initialValue: clip.content)
    }

    var body: some View {
        ZStack {
            (theme.dark ? Color.black.opacity(0.4) : Color.white.opacity(0.45))
                .onTapGesture { model.cancelEdit() }
            VStack(alignment: .leading, spacing: 10) {
                Text("Edit clip").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                TextField("", text: $name, prompt: Text("Name (optional)").foregroundStyle(theme.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.field))
                    .focused($focus, equals: .name)
                    .onSubmit { save() }
                TextEditor(text: $content)
                    .font(.system(size: 12, design: clip.kind == .code ? .monospaced : .default))
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.field))
                    .focused($focus, equals: .content)
                HStack(spacing: 10) {
                    Text("⌘↩ save · ⎋ cancel").font(.system(size: 10.5)).foregroundStyle(theme.tertiary)
                    Spacer()
                    Button("Cancel") { model.cancelEdit() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.secondary)
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.tint.opacity(0.98)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline))
            .padding(10)
        }
        .onAppear { focus = .name }
    }

    private func save() { model.saveEdit(id: clip.id, name: name, content: content) }
}
