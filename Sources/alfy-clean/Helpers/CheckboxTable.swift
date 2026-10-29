//
//  CheckboxTable.swift
//
//  Rows and layout for the cleanup menu (`Prompt.checkboxTable`): a list on the left and an inspector
//  for the focused row on the right.
//

import Foundation

struct CheckboxTableRow {
    enum Risk {
        case bulk, safe, pick, slow, final, look

        /// One glyph for the list. Shapes differ, so the risk doesn't rely on color alone.
        var dot: String {
            switch self {
            case .safe: return "●"
            case .bulk, .pick: return "◆"
            case .final, .slow: return "▲"
            case .look: return "○"
            }
        }

        var label: String {
            switch self {
            case .bulk: return "Bulk · runs several cleanups"
            case .safe: return "Safe · rebuilds itself"
            case .pick: return "Pick which · you choose items next"
            case .slow: return "Careful · signs you out"
            case .final: return "Can't undo · gone for good"
            case .look: return "Look only · deletes nothing by itself"
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
    /// Section heading shown above the first row of each run of rows with the same group.
    var group = ""
    /// What choosing the row frees, for the running total.
    var bytes: UInt64
    /// Text for the size column, e.g. "62.2 GB", "~0 MB" or "scan".
    var size: String
    var risk: Risk
    /// Destructive enough to show in red, so the user notices it before ticking.
    var isWarning = false
    /// The size is partly estimated: the total shows "~".
    var isApproximate = false
    /// The size is a ceiling because the user picks items next: the total shows "up to".
    var isUpperBound = false
    var summary: String
    var facts: [(label: String, value: String)]
}

/// Draws one frame: question, hint, the list (left) beside the inspector for the focused row (right), and the total.
/// On a narrow terminal the inspector goes under the list. If the frame is taller than the terminal it drops the
/// storage banner, then the section headings, and shrinks the inspector, because the redraw moves the cursor up
/// by the frame's line count.
struct CheckboxTableLayout {
    let rows: [CheckboxTableRow]
    let question: String?
    let size: (rows: Int, columns: Int)

    private enum InspectorStyle { case roomy, compact, minimal }
    private typealias Level = (fullQuestion: Bool, headings: Bool, inspector: InspectorStyle)
    private static let levels: [Level] = [
        (true, true, .roomy), (false, true, .roomy), (false, true, .compact), (false, false, .compact), (false, false, .minimal)
    ]

    private typealias C = Print.Color
    private typealias Cell = (text: String, visible: Int)

    /// The list column fits its longest row, so names are not cut short. The inspector keeps at least 43 columns.
    private var listWidth: Int {
        let outer = max(min(size.columns, 124) - 1, 44)
        let width = outer - 4
        let sizeWidth = max(rows.map { $0.size.count }.max() ?? 0, 6)
        let longestName = rows.map { $0.name.count }.max() ?? 0
        let needed = 4 + 2 + longestName + 2 + sizeWidth + 2 + 1     // "❯ ☐ " + name + gap + size + gap + dot
        return min(max(44, needed), max(width - 44, 44))
    }
    private let separator = " │ "
    /// Below this width the inspector is stacked under the list instead of beside it.
    private let sideBySideMinimum = 88

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
        // The frame takes 4 columns: border + one space of padding on each side.
        let outer = max(min(size.columns, 124) - 1, 44)
        let width = outer - 4
        let sideBySide = width >= sideBySideMinimum
        var out: [String] = []
        if level.fullQuestion { out.append("") }

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

        let list = listCells(focused: focused, selected: selected, showHeadings: level.headings)
        let row = rows[focused]

        if sideBySide {
            let inspectorWidth = width - listWidth - separator.count
            let inspector = inspectorLines(row, width: inspectorWidth, style: level.inspector)
            for index in 0..<max(list.count, inspector.count) {
                let left: Cell = index < list.count ? list[index] : ("", 0)
                let padding = String(repeating: " ", count: listWidth - left.visible)
                let right = index < inspector.count ? inspector[index] : ""
                out.append(left.text + padding + dim(separator) + right)
            }
        } else {
            out += list.map { $0.text }
            out.append("")
            out += inspectorLines(row, width: width - 2, style: level.inspector == .minimal ? .minimal : .compact).map { "  " + $0 }
        }

        if level.fullQuestion { out.append("") }
        out.append(dim(String(repeating: "─", count: width)))
        out.append(footer(selected, width: width))
        if level.fullQuestion { out.append("") }
        return framed(out, inner: width)
    }

    /// Wraps the content in a rounded border with a title in the top edge.
    private func framed(_ content: [String], inner: Int) -> [String] {
        let title = " alfy-clean clean "
        let top = dim("╭─") + paint(title, .cyan) + dim(String(repeating: "─", count: max(inner + 1 - title.count, 0)) + "╮")
        let bottom = dim("╰" + String(repeating: "─", count: inner + 2) + "╯")
        let body = content.map { line -> String in
            let padding = String(repeating: " ", count: max(inner - visibleCount(line), 0))
            return dim("│") + " " + line + padding + " " + dim("│")
        }
        return [top] + body + [bottom]
    }

    private func visibleCount(_ text: String) -> Int {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression).count
    }

    // MARK: List

    private func listCells(focused: Int, selected: Set<Int>, showHeadings: Bool) -> [Cell] {
        let sizeWidth = max(rows.map { $0.size.count }.max() ?? 0, 6)
        let nameWidth = listWidth - 4 - 2 - sizeWidth - 2 - 1     // "❯ ☐ " + gap + size + gap + dot
        var cells: [Cell] = []

        for index in rows.indices {
            let row = rows[index]
            if showHeadings, !row.group.isEmpty, index == 0 || row.group != rows[index - 1].group {
                cells.append(heading(row.group))
            }

            let isFocused = index == focused
            let isSelected = selected.contains(index)
            let cursor = isFocused ? paint("❯", .boldGreen) : " "
            let checkbox = isSelected ? paint("☑", .green) : "☐"
            let name = padRight(fit(row.name, nameWidth), nameWidth)
            let shownName: String
            if row.isWarning {
                shownName = paint(name, isFocused ? .boldRed : .red)
            } else {
                shownName = isFocused ? paint(name, .boldGreen) : (isSelected ? paint(name, .green) : name)
            }
            let dotColor = row.isWarning ? C.red : row.risk.color
            let text = "\(cursor) \(checkbox) \(shownName)  \(padLeft(row.size, sizeWidth))  \(paint(row.risk.dot, dotColor))"
            cells.append((text, listWidth))
        }
        return cells
    }

    private func heading(_ title: String) -> Cell {
        let rule = String(repeating: "─", count: max(listWidth - title.count - 3, 2))
        let shown = title.uppercased()
        return ("  " + paint(shown, .cyan) + " " + dim(rule), 2 + shown.count + 1 + rule.count)
    }

    // MARK: Inspector

    /// The row's risk line. A warning row adds the "can't undo" line in red under it.
    private func riskLines(_ row: CheckboxTableRow) -> [String] {
        var lines = [paint("\(row.risk.dot) \(row.risk.label)", row.risk.color)]
        if row.isWarning {
            lines.append(paint("\(CheckboxTableRow.Risk.final.dot) \(CheckboxTableRow.Risk.final.label)", .red))
        }
        return lines
    }

    /// The focused row: name, size, risk, what it does and the facts.
    /// `roomy` adds blank lines and small headings, `compact` puts each fact on one line,
    /// `minimal` is just name and size, the risk and one line of what it does.
    private func inspectorLines(_ row: CheckboxTableRow, width: Int, style: InspectorStyle) -> [String] {
        var out: [String] = []

        if style == .minimal {
            let size = row.size
            out.append(paint(fit(row.name, max(width - size.count - 2, 1)), .bold) + "  " + dim(size))
            out += riskLines(row)
            out += wrap(row.summary, width: width, maxLines: 1)
            return out
        }

        out.append(dim(fit(row.name, width)))
        out.append(paint(fit(row.size, width), .bold))
        out += riskLines(row)

        if style == .roomy {
            out.append("")
            out.append(dim("WHAT IT DOES"))
            out += wrap(row.summary, width: width, maxLines: 3)
            for fact in row.facts {
                out.append("")
                out.append(dim(fact.label.uppercased()))
                out += wrap(fact.value, width: width, maxLines: 2)
            }
        } else {
            out += wrap(row.summary, width: width, maxLines: 2)
            let labelWidth = 11
            for fact in row.facts {
                let value = fit(fact.value, max(width - labelWidth, 1))
                out.append(dim(padRight(fact.label, labelWidth)) + value)
            }
        }
        return out
    }

    // MARK: Footer

    private func footer(_ selected: Set<Int>, width: Int) -> String {
        let chosen = selected.sorted().map { rows[$0] }
        guard !chosen.isEmpty else { return dim("Nothing selected") }

        let prefix = chosen.contains { $0.isUpperBound } ? "up to " : (chosen.contains { $0.isApproximate } ? "~" : "")
        let right = "will free \(prefix)\(DiskUsage.format(chosen.reduce(0) { $0 + $1.bytes }))"
        let names = chosen.map { $0.name }.joined(separator: ", ")
        let left = fit("\(chosen.count) selected: \(names)", max(width - right.count - 2, 10))
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
