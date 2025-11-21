// MessageRendering.swift
// Replacement file — drop-in for your project.
//
// Features:
// - Robust fenced-code parsing (```lang filename) and CRLF/LF support
// - SegmentKind includes filename metadata
// - JSON fenced blocks decode into MessageBlock(s)
// - ListRendererView reused in MessageRenderer for correct bullets
// - CodeBlockView shows filename + language + copy button + context menu
// - TableGridView, RemoteImageView, CalloutView, CardView included

import SwiftUI
import AppKit

// ----------------------
// 1) Segment model + ChatMessage helper types
// ----------------------
enum SegmentKind: Equatable {
    case markdown
    case code(language: String?, filename: String?)
    case json // json block (string) - will be decoded to structured blocks
}

struct MessageSegment: Identifiable, Equatable {
    let id = UUID()
    let kind: SegmentKind
    let content: String
}

// ----------------------
// 2) Structured block model (JSON-decoded form from assistant)
// ----------------------
struct MessageBlock: Codable, Identifiable {
    let id: UUID
    let type: String
    let text: String?
    let language: String?
    let headers: [String]?
    let rows: [[String]]?
    let url: String?
    let alt: String?
    let items: [MessageBlock]?

    init(id: UUID = UUID(), type: String, text: String? = nil, language: String? = nil, headers: [String]? = nil, rows: [[String]]? = nil, url: String? = nil, alt: String? = nil, items: [MessageBlock]? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.language = language
        self.headers = headers
        self.rows = rows
        self.url = url
        self.alt = alt
        self.items = items
    }

    // custom decoder to accept optional id string
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawId = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: rawId) {
            id = uuid
        } else {
            id = UUID()
        }
        type = try container.decode(String.self, forKey: .type)
        text = try? container.decode(String.self, forKey: .text)
        language = try? container.decode(String.self, forKey: .language)
        headers = try? container.decode([String].self, forKey: .headers)
        rows = try? container.decode([[String]].self, forKey: .rows)
        url = try? container.decode(String.self, forKey: .url)
        alt = try? container.decode(String.self, forKey: .alt)
        items = try? container.decode([MessageBlock].self, forKey: .items)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, language, headers, rows, url, alt, items
    }
}

// ----------------------
// 3) MessageParser
//    - robust fenced-code detection (handles CRLF/LF)
//    - extracts language + optional filename metadata
//    - normalizes plain-list markers into Markdown-style for consistent rendering
// ----------------------
enum MessageParser {
    static func parseSegments(from raw: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Robust fenced code pattern: capture metadata (group1) and code (group2)
        // Accepts both \n and \r\n
        let pattern = "```([^\\r\\n]*)\\r?\\n([\\s\\S]*?)\\r?\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [MessageSegment(kind: .markdown, content: raw)]
        }

        let matches = regex.matches(in: raw, options: [], range: fullRange)
        var cursor = 0

        for m in matches {
            let matchRange = m.range(at: 0)

            // prefix markdown before this code block
            if matchRange.location > cursor {
                let prefixRange = NSRange(location: cursor, length: matchRange.location - cursor)
                var prefix = ns.substring(with: prefixRange)
                if containsPlainTextLists(prefix) {
                    prefix = formatPlainTextLists(prefix)
                }
                if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(MessageSegment(kind: .markdown, content: prefix))
                }
            }

            // metadata & code
            let metaRange = m.range(at: 1)
            let codeRange = m.range(at: 2)
            let meta = metaRange.location != NSNotFound ? ns.substring(with: metaRange).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let code = ns.substring(with: codeRange)

            // parse metadata: e.g. "swift App.swift" => language=swift filename=App.swift
            var language: String? = nil
            var filename: String? = nil
            if !meta.isEmpty {
                let parts = meta.split(separator: " ", maxSplits: 1).map { String($0) }
                if parts.count > 0 { language = parts[0] }
                if parts.count > 1 { filename = parts[1] }
            }

            if let langLower = language?.lowercased(), langLower == "json" {
                // treat valid JSON code as structured json block
                if let data = code.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data, options: [])) != nil {
                    segments.append(MessageSegment(kind: .json, content: code))
                } else {
                    segments.append(MessageSegment(kind: .code(language: language, filename: filename), content: code))
                }
            } else {
                segments.append(MessageSegment(kind: .code(language: language, filename: filename), content: code))
            }

            cursor = matchRange.location + matchRange.length
        }

        // suffix after last code block
        if cursor < ns.length {
            var suffix = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            if containsPlainTextLists(suffix) {
                suffix = formatPlainTextLists(suffix)
            }
            if !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(MessageSegment(kind: .markdown, content: suffix))
            }
        }

        // if still empty, check whole message for raw JSON, else markdown
        if segments.isEmpty {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
               let data = trimmed.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [])) != nil {
                return [MessageSegment(kind: .json, content: trimmed)]
            } else {
                return [MessageSegment(kind: .markdown, content: raw)]
            }
        }

        return segments
    }

    // Detect many bullet glyphs or numbered lists in plain text (before conversion)
    private static func containsPlainTextLists(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ||
               trimmed.hasPrefix("◦") || trimmed.hasPrefix("‣") || trimmed.hasPrefix("⁃") {
                return true
            }
            if let _ = trimmed.range(of: #"^\d+\."#, options: .regularExpression) {
                return true
            }
        }
        return false
    }

    // Convert plain bullet glyphs into markdown-style bullets for consistent parsing
    private static func formatPlainTextLists(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        for var line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("•") {
                line = line.replacingOccurrences(of: "•", with: "-", options: .anchored)
            } else if trimmed.hasPrefix("◦") {
                line = line.replacingOccurrences(of: "◦", with: "-", options: .anchored)
            } else if trimmed.hasPrefix("‣") {
                line = line.replacingOccurrences(of: "‣", with: "-", options: .anchored)
            } else if trimmed.hasPrefix("⁃") {
                line = line.replacingOccurrences(of: "⁃", with: "-", options: .anchored)
            } // -, * remain as-is
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    // Decode json string into MessageBlock array if possible
    static func decodeMessageBlocks(from jsonString: String) -> [MessageBlock]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let arr = try? decoder.decode([MessageBlock].self, from: data) {
            return arr
        }
        if let single = try? decoder.decode(MessageBlock.self, from: data) {
            return [single]
        }
        // last attempt: wrapper with "blocks" key
        if let wrapper = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let rawBlocks = wrapper["blocks"] as? [[String: Any]],
           let d2 = try? JSONSerialization.data(withJSONObject: rawBlocks, options: []) {
            return try? decoder.decode([MessageBlock].self, from: d2)
        }
        return nil
    }
}

// ----------------------
// 4) UI: MessageRenderer — turns a ChatMessage into rendered segments
// ----------------------
struct MessageRenderer: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let segments = message.segments {
                ForEach(segments, id: \.id) { seg in
                    switch seg.kind {
                    case .markdown:
                        if containsLists(seg.content) {
                            ListRendererView(text: seg.content)
                        } else if #available(macOS 12.0, *) {
                            if let attr = try? AttributedString(markdown: seg.content) {
                                Text(attr)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            } else {
                                Text(seg.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text(seg.content)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                        }

                    case .code(let language, let filename):
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                if let filename, !filename.isEmpty {
                                    Text(filename)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let lang = language, !lang.isEmpty {
                                    Text(lang.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Button(action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(seg.content, forType: .string) }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 6)
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(seg.content)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    case .json:
                        if let blocks = MessageParser.decodeMessageBlocks(from: seg.content) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(blocks) { block in
                                    StructuredBlockView(block: block)
                                }
                            }
                        } else {
                            // fallback: try to render as markdown or raw text
                            if #available(macOS 12.0, *) {
                                if let attr = try? AttributedString(markdown: seg.content) {
                                    Text(attr)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                } else {
                                    Text(seg.content)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                            } else {
                                Text(seg.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                // Fallback for older messages without parsed segments
                if #available(macOS 12.0, *) {
                    if let attr = try? AttributedString(markdown: message.content) {
                        Text(attr)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    } else {
                        Text(message.content)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // Local duplicate of containsLists for renderer-level detection (keeps it in same file)
    private func containsLists(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ||
               trimmed.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}

// ----------------------
// Table parsing helpers — detect Markdown tables (| ... |) and CSV/TSV
// ----------------------
private func parseTable(from text: String) -> (headers: [String], rows: [[String]])? {
    let lines = text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard lines.count >= 2 else { return nil }

    // 1) Markdown pipe table
    if lines[0].contains("|") {
        let headerCells = splitPipes(lines[0])
        if lines.count >= 2 && isMarkdownSeparatorLine(lines[1]) {
            var rows: [[String]] = []
            for i in 2..<lines.count {
                let cells = splitPipes(lines[i])
                if !cells.isEmpty { rows.append(padOrTrim(cells, to: headerCells.count)) }
            }
            if !headerCells.isEmpty && !rows.isEmpty { return (headerCells, rows) }
        }
    }

    // 2) CSV
    if let csv = parseSeparated(lines: lines, separator: ",") { return csv }
    // 3) TSV
    if let tsv = parseSeparated(lines: lines, separator: "\t") { return tsv }

    return nil
}

private func splitPipes(_ line: String) -> [String] {
    var s = line
    if s.hasPrefix("|") { s.removeFirst() }
    if s.hasSuffix("|") { s.removeLast() }
    return s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
}

private func isMarkdownSeparatorLine(_ line: String) -> Bool {
    let stripped = line.replacingOccurrences(of: "|", with: "").trimmingCharacters(in: .whitespaces)
    guard !stripped.isEmpty else { return false }
    return stripped.allSatisfy { c in c == "-" || c == ":" }
}

private func parseSeparated(lines: [String], separator: String) -> (headers: [String], rows: [[String]])? {
    let parts = lines.map { $0.components(separatedBy: separator) }
    guard let firstCount = parts.first?.count, firstCount >= 2 else { return nil }
    guard parts.dropFirst().allSatisfy({ $0.count == firstCount }) else { return nil }
    let headers = parts[0].map { $0.trimmingCharacters(in: .whitespaces) }
    let rows = parts.dropFirst().map { row in row.map { $0.trimmingCharacters(in: .whitespaces) } }
    if rows.isEmpty { return nil }
    return (headers, rows)
}

private func padOrTrim(_ arr: [String], to n: Int) -> [String] {
    if arr.count == n { return arr }
    if arr.count > n { return Array(arr.prefix(n)) }
    var out = arr
    while out.count < n { out.append("") }
    return out
}

// ----------------------
// 5) StructuredBlockView — render MessageBlock types (table, code, image, paragraph, list, card, callout)
// ----------------------
struct StructuredBlockView: View {
    let block: MessageBlock

    var body: some View {
        switch block.type.lowercased() {
        case "paragraph":
            if let txt = block.text {
                if #available(macOS 12.0, *) {
                    if let attr = try? AttributedString(markdown: txt) {
                        Text(attr).textSelection(.enabled).font(.system(size: 14)).multilineTextAlignment(.leading)
                    } else {
                        Text(txt).textSelection(.enabled).font(.system(size: 14))
                    }
                } else {
                    Text(txt).textSelection(.enabled).font(.system(size: 14))
                }
            }

        case "code":
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.text ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

        case "table":
            // Render tables as simple bullet lines instead of grid
            if let headers = block.headers, let rows = block.rows {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.indices, id: \.self) { r in
                        let items = rows[r].enumerated().map { (idx, val) in
                            let key = idx < headers.count ? headers[idx] : "Col \(idx+1)"
                            return "\(key): \(val)"
                        }
                        Text("• " + items.joined(separator: " · "))
                            .font(.system(size: 14))
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
            } else if let txt = block.text {
                Text(txt).font(.system(size: 14)).textSelection(.enabled)
            }

        case "image":
            if let urlS = block.url {
                RemoteImageView(urlString: urlS, alt: block.alt)
            }

        case "callout", "admonition", "warning", "info":
            CalloutView(text: block.text ?? "", kind: block.type)

        case "list":
            if let items = block.items {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .top) {
                            Text("•").font(.system(size: 14))
                            StructuredBlockView(block: item)
                        }
                    }
                }
            }

        case "card":
            CardView(block: block)

        default:
            if let txt = block.text {
                if #available(macOS 12.0, *) {
                    if let attr = try? AttributedString(markdown: txt) {
                        Text(attr).textSelection(.enabled).font(.system(size: 14))
                    } else {
                        Text(txt)
                    }
                } else {
                    Text(txt)
                }
            }
        }
    }
}

// Note: CodeBlockView is defined in MarkdownRenderer.swift with enhanced features

// ----------------------
// 7) TableGridView (simple responsive table + Copy CSV)
// ----------------------
struct TableGridView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var copied = false
    @State private var rowHover: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Table").font(.headline).foregroundColor(.primary)
                Spacer()
                Button(action: {
                    copyCSV()
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        if copied { Text("Copied!") }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    HStack {
                        ForEach(headers.indices, id: \.self) { i in
                            Text(headers[i])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(rows.indices, id: \.self) { r in
                        HStack {
                            ForEach(rows[r].indices, id: \.self) { c in
                                Text(rows[r][c])
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(rowHover == r ? Color.blue.opacity(0.08) : (r % 2 == 0 ? Color.gray.opacity(0.04) : Color.clear))
                        .onHover { hovering in rowHover = hovering ? r : nil }
                    }
                }
            }
            .frame(maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
    }

    private func copyCSV() {
        var csv = headers.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        for r in rows {
            csv += r.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(csv, forType: .string)
    }

    private func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }
}

// ----------------------
// 8) RemoteImageView (AsyncImage + tap to open Lightbox)
// ----------------------
struct RemoteImageView: View {
    let urlString: String
    let alt: String?

    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(height: 120)
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .cornerRadius(8)
                            .onTapGesture { showFull.toggle() }
                            .contextMenu { Button("Open in Browser") { NSWorkspace.shared.open(url) } }
                    case .failure:
                        Color.gray.frame(height: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                if let alt = alt {
                    Text(alt).font(.subheadline)
                }
            }

            if let alt = alt {
                Text(alt).font(.caption).foregroundColor(.white.opacity(0.6))
            }
        }
        .sheet(isPresented: $showFull) {
            if let url = URL(string: urlString) {
                VStack { Spacer()
                    AsyncImage(url: url) { ph in
                        if case .success(let img) = ph { img.resizable().scaledToFit() }
                        else { ProgressView() }
                    }
                    Spacer()
                }
                .frame(minWidth: 600, minHeight: 400)
            } else {
                Text("No image")
            }
        }
    }
}

// ----------------------
// 9) CalloutView, CardView simple implementations
// ----------------------
struct CalloutView: View {
    let text: String
    let kind: String // "info","warning","tip"

    var color: Color {
        switch kind.lowercased() {
        case "warning": return Color.yellow.opacity(0.2)
        case "success": return Color.green.opacity(0.14)
        default: return Color.blue.opacity(0.12)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading) {
                if #available(macOS 12.0, *) {
                    if let attr = try? AttributedString(markdown: text) {
                        Text(attr).textSelection(.enabled)
                    } else { Text(text).textSelection(.enabled) }
                } else { Text(text) }
            }
            .padding(8)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct CardView: View {
    let block: MessageBlock

    var body: some View {
        HStack {
            if let url = block.url, let u = URL(string: url) {
                AsyncImage(url: u) { ph in
                    if case .success(let img) = ph { img.resizable().aspectRatio(contentMode: .fill).frame(width: 56, height: 56).clipped().cornerRadius(6) }
                    else { Color.gray.frame(width:56,height:56) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let t = block.text { Text(t).font(.system(size: 13, weight: .semibold)) }
                if let url = block.url, let u = URL(string: url) {
                    Button(action: { NSWorkspace.shared.open(u) }) {
                        Text(u.host ?? url).font(.caption).foregroundColor(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// ----------------------
// 10) ListRendererView (supports bullets & numbered lists; single-level)
// ----------------------
private struct ListRendererView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                switch line {
                case .bullet(let content):
                    HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 12, alignment: .leading)
                        if #available(macOS 12.0, *) {
                            if let attr = try? AttributedString(markdown: content) {
                                Text(attr)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text(content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            }
                        } else {
                            Text(content)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                case .numbered(let number, let content):
                    HStack(alignment: .top, spacing: 8) {
                            Text("\(number).")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 20, alignment: .leading)
                        if #available(macOS 12.0, *) {
                            if let attr = try? AttributedString(markdown: content) {
                                Text(attr)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text(content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            }
                        } else {
                            Text(content)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                case .text(let content):
                    Text(content)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private enum LineType {
        case bullet(String)
        case numbered(Int, String)
        case text(String)
    }

    private func parseLines() -> [LineType] {
        let lines = text.components(separatedBy: .newlines)
        var result: [LineType] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                result.append(.bullet(content))
            } else if let match = trimmed.range(of: #"^(\d+)\."#, options: .regularExpression) {
                let numberStr = String(trimmed[match])
                let number = Int(numberStr.dropLast()) ?? 1
                let content = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                result.append(.numbered(number, content))
            } else {
                result.append(.text(line))
            }
        }
        return result
    }
}
