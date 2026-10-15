//
//  CheckboxTable.swift
//
//  Rows and layout for the size-ranked cleanup menu (`Prompt.checkboxTable`).
//

import Foundation

struct CheckboxTableRow {
    enum Risk {
        case bulk, safe, pick, slow, final, look

        var tag: String {
            switch self {
            case .bulk: return "bulk"
            case .safe: return "safe"
            case .pick: return "pick"
            case .slow: return "slow"
            case .final: return "final"
            case .look: return "look"
            }
        }

        var color: Print.Color {
            switch self {
            case .bulk, .pick: return .cyan
            case .safe: return .green
            case .slow: return .yellow
            case .final: return .red
            case .look: return .dim
            }
        }
    }

    var name: String
    /// What choosing the row frees, for the bar and the running total.
    var bytes: UInt64
    /// Text for the "Frees" column, e.g. "62.2 GB", "~0 MB" or "scan".
    var size: String
    var risk: Risk
    /// The size is partly estimated: the total shows "~".
    var isApproximate = false
    /// The size is a ceiling because the user picks items next: the total shows "up to".
    var isUpperBound = false
    var summary: String
    var facts: [(label: String, value: String)]
}

/// Draws one frame of the table: question, hint, rows, detail box for the focused row, and the total.
/// If the full frame is taller than the terminal it drops the storage frame and shrinks the detail box,
/// because the redraw moves the cursor up by the frame's line count.
struct CheckboxTableLayout {
    let rows: [CheckboxTableRow]
    let question: String?
    let size: (rows: Int, columns: Int)

    private enum BoxStyle { case full, compact, line }
    private typealias Level = (fullQuestion: Bool, box: BoxStyle)
    private static let levels: [Level] = [(true, .full), (true, .compact), (false, .compact), (false, .line)]

    private typealias C = Print.Color
    private let tagWidth = 5
    private let factLabelWidth = 11

    func lines(focused: Int, selected: Set<Int>) -> [String] {
        var frame: [String] = []
        for (index, level) in Self.levels.enumerated() {
            frame = build(level, focused: focused, selected: selected)
            if frame.count < size.rows || index == Self.levels.count - 1 { break }
        }
        return frame
    }

    // MARK: Frame

    private func build(_ level: Level, focused: Int, selected: Set<Int>) -> [String] {
        let width = max(min(size.columns, 100) - 1, 40)
        let columns = Columns(rows: rows, width: width, tagWidth: tagWidth)
        var out: [String] = []

        if let question = question {
            let questionLines = question.components(separatedBy: .newlines)
            if level.fullQuestion {
                out += questionLines
            } else if let last = questionLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                out.append(last)
            }
        }
        out.append(dim("↑/↓ move  •  space select  •  enter confirm  •  q cancel"))
        if level.fullQuestion { out.append("") }
        out.append(dim(header(columns)))
        for index in rows.indices {
            out.append(rowLine(index, focused: index == focused, selected: selected.contains(index), columns))
        }

        let row = rows[focused]
        switch level.box {
        case .full:
            out.append("")
            out += box(row, width: width, withFacts: true)
        case .compact:
            out += box(row, width: width, withFacts: false)
        case .line:
            out.append(dim("  " + fit(row.summary, width - 2)))
        }

        out.append(footer(selected, width: width))
        return out
    }

    private struct Columns {
        let nameWidth: Int
        let barWidth: Int
        let sizeWidth: Int

        init(rows: [CheckboxTableRow], width: Int, tagWidth: Int) {
            sizeWidth = max(rows.map { $0.size.count }.max() ?? 0, "FREES".count)
            let longestName = rows.map { $0.name.count }.max() ?? 0
            let fixed = 4 + 2 + sizeWidth + 2 + tagWidth     // "❯ ☐ " + gaps + size + tag
            let withBar = min(longestName, width - fixed - 2 - 16)
            if withBar >= 14 {
                nameWidth = withBar
                barWidth = 16
            } else {
                nameWidth = max(min(longestName, width - fixed), 8)
                barWidth = 0
            }
        }
    }

    private func header(_ columns: Columns) -> String {
        var line = "    " + padRight("FOLDER", columns.nameWidth)
        if columns.barWidth > 0 { line += "  " + padRight("RELATIVE SIZE", columns.barWidth) }
        return line + "  " + padLeft("FREES", columns.sizeWidth) + "  RISK"
    }

    private func rowLine(_ index: Int, focused: Bool, selected: Bool, _ columns: Columns) -> String {
        let row = rows[index]
        let cursor = focused ? paint("❯", .boldGreen) : " "
        let checkbox = selected ? paint("☑", .green) : "☐"
        let name = padRight(fit(row.name, columns.nameWidth), columns.nameWidth)
        let shownName = focused ? paint(name, .boldGreen) : (selected ? paint(name, .green) : name)

        var line = "\(cursor) \(checkbox) \(shownName)"
        if columns.barWidth > 0 { line += "  " + bar(row, width: columns.barWidth) }
        line += "  " + padLeft(row.size, columns.sizeWidth)
        line += "  " + paint(padRight(row.risk.tag, tagWidth), row.risk.color)
        return line
    }

    private func bar(_ row: CheckboxTableRow, width: Int) -> String {
        let largest = rows.map { $0.bytes }.max() ?? 0
        var filled = 0
        if row.bytes > 0, largest > 0 {
            filled = max(1, Int((Double(row.bytes) / Double(largest) * Double(width)).rounded()))
        }
        return paint(String(repeating: "█", count: filled), .cyan)
            + dim(String(repeating: "░", count: width - filled))
    }

    private func box(_ row: CheckboxTableRow, width: Int, withFacts: Bool) -> [String] {
        let inner = width - 4
        var content: [(text: String, visible: Int)] = []

        let title = fit(row.name, inner)
        content.append((paint(title, .boldGreen), title.count))

        let summaryLines = wrap(row.summary, width: inner, maxLines: withFacts ? 2 : 1)
        for line in summaryLines { content.append((line, line.count)) }
        if withFacts {
            // Constant height: pad a one-line summary so the box doesn't jump between rows.
            for _ in summaryLines.count..<2 { content.append(("", 0)) }
            for fact in row.facts {
                let label = padRight(fact.label, factLabelWidth)
                let value = fit(fact.value, max(inner - factLabelWidth, 1))
                content.append((dim(label) + value, label.count + value.count))
            }
        }

        let rule = String(repeating: "─", count: width - 2)
        var out = ["╭\(rule)╮"]
        for line in content {
            out.append("│ \(line.text)\(String(repeating: " ", count: max(inner - line.visible, 0))) │")
        }
        out.append("╰\(rule)╯")
        return out
    }

    private func footer(_ selected: Set<Int>, width: Int) -> String {
        let chosen = selected.sorted().map { rows[$0] }
        guard !chosen.isEmpty else { return dim("Nothing selected") }

        let prefix = chosen.contains { $0.isUpperBound } ? "up to " : (chosen.contains { $0.isApproximate } ? "~" : "")
        let left = "\(chosen.count) selected"
        let right = "will free \(prefix)\(DiskUsage.format(chosen.reduce(0) { $0 + $1.bytes }))"
        let gap = String(repeating: " ", count: max(width - left.count - right.count, 2))
        return left + gap + paint(right, .green)
    }

    // MARK: Text helpers (widths are in characters, so rows must not contain emoji)

    private func paint(_ text: String, _ color: C) -> String {
        "\(color.rawValue)\(text)\(C.reset.rawValue)"
    }

    private func dim(_ text: String) -> String {
        paint(text, .dim)
    }

    private func fit(_ text: String, _ width: Int) -> String {
        guard text.count > width else { return text }
        return String(text.prefix(max(width - 1, 0))) + "…"
    }

    private func padRight(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(width - text.count, 0))
    }

    private func padLeft(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(width - text.count, 0)) + text
    }

    private func wrap(_ text: String, width: Int, maxLines: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            let last = lines[maxLines - 1]
            lines[maxLines - 1] = last.count >= width ? String(last.prefix(width - 1)) + "…" : last + "…"
        }
        return lines.map { fit($0, width) }
    }
}
