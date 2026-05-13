import SwiftUI

// MARK: - Public view

/// Renders mentor/tool prose with lightweight markdown: headings, lists, fenced code, horizontal rules,
/// and inline **bold**, *italic*, and `code`. Styled for [WhetstoneTheme](WhetstoneTheme.swift).
struct MentorMarkdownView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let s):
            MentorParagraphInlineView(text: s)
        case .heading(let level, let line):
            Text(MarkdownInlineParser.attributedHeading(line, level: level))
                .padding(.top, level <= 2 ? 6 : 4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WhetstoneTheme.ember)
                            .frame(width: 10, alignment: .leading)
                        MentorParagraphInlineView(text: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(pair.index).")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(WhetstoneTheme.blade)
                            .frame(minWidth: 22, alignment: .trailing)
                        MentorParagraphInlineView(text: pair.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhetstoneTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WhetstoneTheme.blade.opacity(0.28), lineWidth: 1)
            )
        case .horizontalRule:
            Rectangle()
                .fill(WhetstoneTheme.blade.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Paragraph + inline (plain markdown + `code`)

private struct MentorParagraphInlineView: View {
    let text: String

    var body: some View {
        Text(MarkdownInlineParser.attributedParagraph(text))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Block model

private enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(items: [String])
    case numbered(items: [(index: Int, text: String)])
    case codeBlock(String)
    case horizontalRule
}

// MARK: - Block parser

private enum MarkdownBlockParser {

    /// Whitespace run immediately before an inline `N.` marker (`N` + `.` + space + non-whitespace).
    private static let inlineEnumerationWhitespace = /\s+(?=\d+\.\s\S)/

    static func parse(_ raw: String) -> [MarkdownBlock] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var blocks: [MarkdownBlock] = []
        var i = normalized.startIndex

        while i < normalized.endIndex {
            while i < normalized.endIndex && normalized[i] == "\n" {
                i = normalized.index(after: i)
            }
            guard i < normalized.endIndex else { break }

            if normalized[i...].hasPrefix("```") {
                let extracted = extractFencedCode(from: normalized, openingFenceStart: i)
                blocks.append(.codeBlock(extracted.content))
                i = extracted.endIndex
                continue
            }

            let chunkStart = i
            while i < normalized.endIndex {
                if normalized[i] == "\n" {
                    let next = normalized.index(after: i)
                    if next < normalized.endIndex && normalized[next] == "\n" {
                        break
                    }
                }
                i = normalized.index(after: i)
            }

            let chunk = String(normalized[chunkStart..<i])
            if i < normalized.endIndex && normalized[i] == "\n" {
                i = normalized.index(after: i)
                if i < normalized.endIndex && normalized[i] == "\n" {
                    i = normalized.index(after: i)
                }
            }

            blocks.append(contentsOf: classifyChunk(chunk))
        }

        return blocks
    }

    private static func extractFencedCode(from s: String, openingFenceStart: String.Index) -> (content: String, endIndex: String.Index) {
        var i = s.index(openingFenceStart, offsetBy: 3)
        while i < s.endIndex && s[i] != "\n" {
            i = s.index(after: i)
        }
        if i < s.endIndex {
            i = s.index(after: i)
        }
        let contentStart = i

        while i < s.endIndex {
            if s[i] == "`", s[i...].hasPrefix("```") {
                var content = String(s[contentStart..<i])
                if content.hasSuffix("\n") {
                    content.removeLast()
                }
                i = s.index(i, offsetBy: 3)
                while i < s.endIndex && s[i] == "\n" {
                    i = s.index(after: i)
                }
                return (content, i)
            }
            i = s.index(after: i)
        }

        var fallback = String(s[contentStart..<s.endIndex])
        if fallback.hasSuffix("\n") {
            fallback.removeLast()
        }
        return (fallback, s.endIndex)
    }

    private static func classifyChunk(_ chunk: String) -> [MarkdownBlock] {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if lines.count == 1, let rule = lines.first, isHorizontalRule(rule) {
            return [.horizontalRule]
        }

        if lines.count == 1, let line = lines.first, let heading = parseHeadingLine(line) {
            return [.heading(level: heading.level, text: heading.text)]
        }

        guard !nonEmpty.isEmpty else { return [] }

        if nonEmpty.allSatisfy(isBulletLine) {
            return [.bullet(items: nonEmpty.map(stripBulletPrefix))]
        }

        if nonEmpty.allSatisfy(isNumberedLine) {
            let pairs: [(index: Int, text: String)] = nonEmpty.compactMap(parseNumberedLine)
            return pairs.isEmpty ? paragraphBlocks(from: lines) : [.numbered(items: pairs)]
        }

        return paragraphBlocks(from: lines)
    }

    /// Joins soft line breaks into one paragraph string, then expands inline `1. … 2. …` patterns when safe.
    private static func paragraphBlocks(from lines: [String]) -> [MarkdownBlock] {
        let joined = joinedParagraph(from: lines)
        return expandedParagraph(joined)
    }

    private static func joinedParagraph(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func expandedParagraph(_ joined: String) -> [MarkdownBlock] {
        if let expanded = expandInlineNumberedList(joined) {
            return expanded
        }
        return [.paragraph(joined)]
    }

    /// If `joined` contains ≥2 inline enumeration markers at plausible boundaries, emit `.paragraph` + `.numbered` or `.numbered` only.
    private static func expandInlineNumberedList(_ joined: String) -> [MarkdownBlock]? {
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return nil }
        guard !hasUnbalancedBackticks(trimmed) else { return nil }

        let segments = enumerationSegments(from: trimmed)
        guard segments.count >= 2 else { return nil }

        if segments.allSatisfy(isNumberedLine) {
            let pairs = segments.compactMap(parseNumberedLine)
            guard pairs.count == segments.count, pairs.count >= 2 else { return nil }
            return [.numbered(items: pairs)]
        }

        guard let head = segments.first, !isNumberedLine(head) else { return nil }
        let tail = Array(segments.dropFirst())
        guard tail.count >= 2, tail.allSatisfy(isNumberedLine) else { return nil }
        let pairs = tail.compactMap(parseNumberedLine)
        guard pairs.count == tail.count else { return nil }

        var blocks: [MarkdownBlock] = []
        if !head.isEmpty {
            blocks.append(.paragraph(head))
        }
        blocks.append(.numbered(items: pairs))
        return blocks
    }

    private static func hasUnbalancedBackticks(_ s: String) -> Bool {
        s.filter { $0 == "`" }.count % 2 != 0
    }

    /// Splits `trimmed` at inline list markers using `\s+(?=\d+\.\s\S)`, suppressing **only** the first boundary when it looks like `word 1.` prose (e.g. `step 1.`) so later boundaries (`… Alpha 2. Beta`) still split.
    private static func enumerationSegments(from trimmed: String) -> [String] {
        var pieces: [String] = []
        var cursor = trimmed.startIndex
        var firstBoundary = true

        for match in trimmed.matches(of: inlineEnumerationWhitespace) {
            let wsStart = match.range.lowerBound
            guard wsStart >= cursor else { continue }

            if firstBoundary, wsStart > trimmed.startIndex {
                let before = trimmed.index(before: wsStart)
                let ch = trimmed[before]
                let looksLikeOrdinalPhrase = (ch == "_" || (ch.isASCII && (ch.isLetter || ch.isNumber)))
                if looksLikeOrdinalPhrase {
                    firstBoundary = false
                    continue
                }
            }
            firstBoundary = false

            let head = String(trimmed[cursor..<wsStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty {
                pieces.append(head)
            }
            cursor = match.range.upperBound
        }

        let tail = String(trimmed[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            pieces.append(tail)
        }

        return pieces
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.count < 3 { return false }
        let allSame = t.allSatisfy { ch in ch == "-" || ch == "*" || ch == "_" }
        return allSame
    }

    private static func parseHeadingLine(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "#" else { return nil }
        var count = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#" {
            count += 1
            idx = trimmed.index(after: idx)
            if count > 6 { return nil }
        }
        guard count >= 1, idx < trimmed.endIndex, trimmed[idx].isWhitespace else { return nil }
        var walk = trimmed.index(after: idx)
        while walk < trimmed.endIndex, trimmed[walk].isWhitespace {
            walk = trimmed.index(after: walk)
        }
        let title = String(trimmed[walk...]).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (min(count, 6), title)
    }

    private static func isBulletLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return false }
        return (first == "-" || first == "*")
            && t.count >= 2
            && t.dropFirst().first.map { $0.isWhitespace } == true
    }

    private static func stripBulletPrefix(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return line }
        let rest = t.dropFirst().drop(while: \.isWhitespace)
        return String(rest)
    }

    private static func isNumberedLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        var idx = t.startIndex
        while idx < t.endIndex, t[idx].isNumber {
            idx = t.index(after: idx)
        }
        guard idx < t.endIndex, t[idx] == "." else { return false }
        idx = t.index(after: idx)
        guard idx < t.endIndex, t[idx].isWhitespace else { return false }
        idx = t.index(after: idx)
        return idx < t.endIndex
    }

    private static func parseNumberedLine(_ line: String) -> (index: Int, text: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        var idx = t.startIndex
        let numStart = idx
        while idx < t.endIndex, t[idx].isNumber {
            idx = t.index(after: idx)
        }
        guard idx > numStart, let n = Int(String(t[numStart..<idx])) else { return nil }
        guard idx < t.endIndex, t[idx] == "." else { return nil }
        idx = t.index(after: idx)
        while idx < t.endIndex, t[idx].isWhitespace {
            idx = t.index(after: idx)
        }
        let rest = String(t[idx...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (n, rest)
    }
}

// MARK: - Inline parsing

private enum MarkdownInlineParser {

    enum InlinePiece {
        case plain(String)
        case code(String)
    }

    static func splitCodeSpans(_ s: String) -> [InlinePiece] {
        var out: [InlinePiece] = []
        var current = ""
        var i = s.startIndex
        var inCode = false

        while i < s.endIndex {
            let ch = s[i]
            if ch == "`" {
                if inCode {
                    out.append(.code(current))
                    current = ""
                    inCode = false
                } else {
                    out.append(.plain(current))
                    current = ""
                    inCode = true
                }
                i = s.index(after: i)
            } else {
                current.append(ch)
                i = s.index(after: i)
            }
        }

        out.append(inCode ? .code(current) : .plain(current))
        return out
    }

    /// Inline markdown plus `` `code` `` spans in one attributed string (single `Text`, preserves wrapping).
    static func attributedParagraph(_ string: String) -> AttributedString {
        var full = AttributedString()
        for piece in splitCodeSpans(string) {
            switch piece {
            case .plain(let str):
                full.append(attributedPlain(str))
            case .code(let code):
                var c = AttributedString(code)
                c.font = .system(size: 14, design: .monospaced)
                c.foregroundColor = WhetstoneTheme.blade
                c.backgroundColor = WhetstoneTheme.surfaceHigh
                full.append(c)
            }
        }
        return full
    }

    static func attributedHeading(_ line: String, level: Int) -> AttributedString {
        let baseSize: CGFloat
        switch level {
        case 1: baseSize = 20
        case 2: baseSize = 18
        default: baseSize = 15
        }
        guard !line.isEmpty else { return AttributedString("") }

        let parsed: AttributedString
        if let p = try? AttributedString(
            markdown: line,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            parsed = p
        } else {
            parsed = AttributedString(line)
        }

        var out = AttributedString()
        for run in parsed.runs {
            var chunk = AttributedString(parsed[run.range])
            let intents = run.inlinePresentationIntent
            let strongly = intents?.contains(.stronglyEmphasized) ?? false
            let emphasized = intents?.contains(.emphasized) ?? false

            if strongly && emphasized {
                chunk.font = .system(size: baseSize, weight: .bold).italic()
            } else if emphasized {
                chunk.font = .system(size: baseSize, weight: .semibold).italic()
            } else if strongly {
                chunk.font = .system(size: baseSize, weight: .bold)
            } else {
                chunk.font = .system(size: baseSize, weight: .semibold)
            }

            let opacity = emphasized && !strongly ? 0.92 : 1.0
            chunk.foregroundColor = Color.white.opacity(opacity)
            chunk.inlinePresentationIntent = nil
            out.append(chunk)
        }
        return out
    }

    static func attributedPlain(_ string: String) -> AttributedString {
        guard !string.isEmpty else { return AttributedString("") }

        let parsed: AttributedString
        if let p = try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            parsed = p
        } else {
            parsed = AttributedString(string)
        }

        return normalizeBodyProsody(parsed)
    }

    private static func normalizeBodyProsody(_ source: AttributedString) -> AttributedString {
        var out = AttributedString()
        for run in source.runs {
            var chunk = AttributedString(source[run.range])
            let intents = run.inlinePresentationIntent
            let strongly = intents?.contains(.stronglyEmphasized) ?? false
            let emphasized = intents?.contains(.emphasized) ?? false

            let isBold = strongly
            let isItalic = emphasized

            let weight: Font.Weight = isBold ? .semibold : .regular
            if isBold && isItalic {
                chunk.font = .system(size: 15, weight: .semibold).italic()
            } else if isItalic {
                chunk.font = .system(size: 15, weight: .regular).italic()
            } else {
                chunk.font = .system(size: 15, weight: weight)
            }

            let opacity: Double
            if isBold {
                opacity = 1.0
            } else if isItalic {
                opacity = 0.85
            } else {
                opacity = 0.9
            }
            chunk.foregroundColor = Color.white.opacity(opacity)
            chunk.inlinePresentationIntent = nil
            out.append(chunk)
        }
        return out
    }
}

// MARK: - Previews

#Preview("Markdown formatting fixtures") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                Text("Baseline list")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                MentorMarkdownView(text: "## Steps\n\n1. First\n2. Second")
            }
            Divider()
                .overlay(WhetstoneTheme.blade.opacity(0.2))
            Group {
                Text("Inline enumerated")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                MentorMarkdownView(text: "Try this. 1. Alpha 2. Beta 3. Gamma")
            }
            Divider()
                .overlay(WhetstoneTheme.blade.opacity(0.2))
            Group {
                Text("Decimal version (no split)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                MentorMarkdownView(text: "iOS 17.2 ships soon.")
            }
            Divider()
                .overlay(WhetstoneTheme.blade.opacity(0.2))
            Group {
                Text("Ordinal phrase (no split)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                MentorMarkdownView(text: "Go to step 1. Then breathe.")
            }
            Divider()
                .overlay(WhetstoneTheme.blade.opacity(0.2))
            Group {
                Text("Unbalanced backticks skip splitter")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                MentorMarkdownView(text: "Odd ` ticks 1. a 2. b")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WhetstoneTheme.obsidian)
    .preferredColorScheme(.dark)
}
