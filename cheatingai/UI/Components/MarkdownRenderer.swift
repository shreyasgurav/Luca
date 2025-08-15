import SwiftUI
import AppKit

struct MarkdownRendererView: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    var body: some View {
        let blocks = parseBlocks(from: text)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let language, let code):
                    CodeBlockView(code: code, language: language)
                case .text(let md):
                    MarkdownTextView(markdown: md)
                }
            }
        }
    }

    private enum Block {
        case code(language: String?, code: String)
        case text(String)
    }

    private func parseBlocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        var inCode = false
        var codeLang: String? = nil
        var currentCode: [String] = []
        var currentText: [String] = []

        func flushText() {
            if !currentText.isEmpty {
                blocks.append(.text(currentText.joined(separator: "\n")))
                currentText.removeAll()
            }
        }

        func flushCode() {
            let code = currentCode.joined(separator: "\n")
            blocks.append(.code(language: codeLang, code: code))
            currentCode.removeAll()
            codeLang = nil
        }

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                if inCode {
                    // closing fence
                    inCode = false
                    flushCode()
                } else {
                    // opening fence
                    flushText()
                    inCode = true
                    let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
            } else if inCode {
                currentCode.append(line)
            } else {
                currentText.append(line)
            }
            index += 1
        }

        if inCode { flushCode() }
        if !currentText.isEmpty { flushText() }
        return blocks
    }
}

private struct MarkdownTextView: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .font(.system(size: 14))
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(.system(size: 14))
                .textSelection(.enabled)
        }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 200)

            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }


}


