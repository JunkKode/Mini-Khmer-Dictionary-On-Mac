//
//  GridCalculatorView.swift
//  Mini Khmer Dictionary
//

import AppKit
import SwiftUI

/// The Grid mode: a formula bar over a small sheet of cells, with sheet tabs
/// along the bottom. Kept deliberately plain — fixed columns, no formatting —
/// so it stays a calculator.
struct GridCalculatorView: View {
    @ObservedObject var grid: GridModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Measured from the column headers, to tell which cell a drag is over.
    @State private var columnWidth: CGFloat = 90

    private static let barHeight: CGFloat = 36
    private static let cellSpace = "gridCells"
    private static let rowHeaderWidth: CGFloat = 34
    private static let rowHeight: CGFloat = 24
    /// Cells round for width; the hint bar and ⌘C keep full precision.
    private static let cellFractionDigits = 6

    var body: some View {
        VStack(spacing: 0) {
            formulaBar
            Divider()
            hintBar
            Divider()
            cells
            Divider()
            SheetTabBar(grid: grid)
        }
        .overlay(alignment: .topLeading) { completionList }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: grid.completion)
    }

    // MARK: - Formula bar

    private var formulaBar: some View {
        HStack(spacing: 0) {
            Text(grid.nameBoxText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 60)
                .accessibilityLabel("Selection \(grid.nameBoxText)")

            Divider()

            Image(systemName: "function")
                .font(.system(size: 12))
                .foregroundStyle(grid.isEditing ? Color.accentColor : Color.secondary.opacity(0.6))
                .padding(.horizontal, 6)
                .accessibilityHidden(true)

            FormulaEditor(
                text: grid.formulaBarText,
                caretRequest: grid.caretRequest,
                focusRequest: grid.focusRequest,
                errorRange: errorRange,
                functions: grid.functions,
                onChange: { grid.editorDidChange(text: $0, selection: $1) },
                onCommand: { grid.handle($0) },
                blurRequest: grid.blurRequest,
                compact: true,
                // Back from another tab mid-edit, the bar takes the keyboard again.
                focusOnAppear: grid.isEditing
            )
            .overlay(alignment: .leading) { placeholder }

            Divider()

            HStack(spacing: 2) {
                Button {
                    grid.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!grid.canUndo)
                .help("Undo (⌘Z)")
                .accessibilityLabel("Undo")

                Button {
                    grid.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!grid.canRedo)
                .help("Redo (⌘Y or ⇧⌘Z)")
                .accessibilityLabel("Redo")

                Button {
                    grid.clearAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(grid.sheet.isEmpty)
                .help(grid.workbook.isGrouped ? "Clear every cell on the grouped sheets (⌘Z brings them back)" : "Clear every cell on this sheet (⌘Z brings them back)")
                .accessibilityLabel("Clear all cells")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        }
        .frame(height: Self.barHeight)
    }

    /// Underlines the faulty part of the active cell's formula.
    private var errorRange: Range<Int>? {
        let result = grid.isEditing ? grid.editPreview : grid.selectedResult
        guard let error = result.error, error.kind != .incomplete,
              Spreadsheet.isFormula(grid.formulaBarText) else { return nil }
        return error.range
    }

    @ViewBuilder
    private var placeholder: some View {
        if grid.formulaBarText.isEmpty, !grid.isEditing {
            Text("Type a number, text or =formula")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Hint bar

    private var hintBar: some View {
        HStack(spacing: 8) {
            hintContent
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder
    private var hintContent: some View {
        if let target = grid.fillTarget {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Release to fill \(target.name)")
                .fontWeight(.medium)
            Text("· hold ⌥ to count up from a single number  · drag back inside to cancel")
                .foregroundStyle(.secondary)
        } else if grid.completion != nil {
            EmptyView()  // the suggestion list covers this line
        } else if grid.isEditing, let hint = grid.signature, let function = grid.functions.function(named: hint.functionName) {
            function.signatureText(activeArgument: hint.argumentIndex)
                .font(.system(size: 12, design: .monospaced))
                .layoutPriority(1)
            Spacer(minLength: 4)
            previewText(grid.editPreview)
        } else if grid.isEditing, Spreadsheet.isFormula(grid.editText) {
            switch grid.editPreview {
            case .value, .empty:
                previewText(grid.editPreview)
                Text("· click or drag across cells to use them")
                    .foregroundStyle(.tertiary)
            case .failure(let error) where error.kind == .incomplete:
                Text("Click a cell, or drag across a range, to put it in the formula")
                    .foregroundStyle(.secondary)
            case .failure(let error):
                errorText(error)
            }
        } else if grid.isEditing {
            Text("⏎ enters · ⇥ moves right · start with = for a formula")
                .foregroundStyle(.secondary)
        } else if let summary = grid.selectionSummary {
            selectionSummaryText(summary)
        } else {
            switch grid.selectedResult {
            case .failure(let error):
                errorText(error)
            case .value(let value, _) where grid.sheet.isFormula(at: grid.activeCell):
                Text("\(grid.activeCell.name) =")
                    .foregroundStyle(.secondary)
                Text(FormulaFormatter.display(value))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            case .value(let value, _):
                Text("\(grid.activeCell.name) · \(value.typeName) · F2 or double-click to edit")
                    .foregroundStyle(.secondary)
            case .empty:
                Image(systemName: "lightbulb")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Type to fill \(grid.activeCell.name) · drag to select · ⇧ or ⌘-click to add")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectionSummaryText(_ summary: (cells: Int, numbers: Int, sum: Double, average: Double?)) -> some View {
        HStack(spacing: 12) {
            Text(grid.selection.ranges.count > 1 ? "\(grid.selection.ranges.count) ranges" : grid.selection.current.name)
                .foregroundStyle(.secondary)
            if summary.numbers > 0 {
                statistic("Sum", FormulaFormatter.display(.number(summary.sum)))
                if let average = summary.average {
                    statistic("Average", FormulaFormatter.display(.number(average), fractionDigits: 4))
                }
            }
            statistic("Count", "\(summary.cells)")
        }
    }

    private func statistic(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }

    @ViewBuilder
    private func previewText(_ result: FormulaCalculation) -> some View {
        if case .value(let value, _) = result {
            Text("= " + FormulaFormatter.display(value))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func errorText(_ error: FormulaError) -> some View {
        HStack(spacing: 6) {
            Text(error.code)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.red)
            Text(error.message)
                .foregroundStyle(.primary)
                .truncationMode(.tail)
        }
    }

    // MARK: - Completions

    @ViewBuilder
    private var completionList: some View {
        if let completion = grid.completion {
            FormulaCompletionList(
                completion: completion,
                selectedIndex: grid.completionIndex,
                functions: grid.functions,
                onChoose: { grid.acceptCompletion($0) }
            )
            .padding(.leading, 68)
            .padding(.top, Self.barHeight + 2)
            .transition(.opacity)
        }
    }

    // MARK: - Cells

    /// Columns share whatever width the scroll view leaves, so they stay
    /// equal whether or not a scroll bar takes room.
    private var cells: some View {
        let referenced = grid.referencedCells
        let selection = grid.selection
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(0..<grid.sheet.rows, id: \.self) { row in
                                rowView(row, selection: selection, referenced: referenced)
                                    .id(row)
                            }
                        }
                        // One layer draws the selection and the copy border,
                        // so they glide between cells instead of jumping.
                        .overlay(alignment: .topLeading) {
                            SelectionLayer(
                                selection: selection,
                                isEditing: grid.isEditing,
                                copied: grid.copiedRange,
                                isCut: grid.clipboard?.isCut == true,
                                fillTarget: grid.fillTarget,
                                fillLabel: grid.fillEndText,
                                columnWidth: columnWidth,
                                rowHeight: Self.rowHeight,
                                leading: Self.rowHeaderWidth,
                                animated: !reduceMotion
                            )
                        }
                        .overlay(alignment: .topLeading) { fillHandle(selection: selection) }
                        .coordinateSpace(name: Self.cellSpace)
                    } header: {
                        columnHeaders(selection: selection)
                    }
                }
            }
            .task(id: selection.current.end) {
                // Keep the moving corner in view while extending with the keyboard.
                guard !grid.isPointerDown else { return }
                proxy.scrollTo(selection.current.end.row)
            }
        }
        .onPreferenceChange(ColumnWidthKey.self) { width in
            if width > 0 { columnWidth = width }
        }
    }

    private func columnHeaders(selection: GridSelection) -> some View {
        let highlighted = selection.columns
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.rowHeaderWidth, height: 22)
                .gridLines()
            ForEach(0..<grid.sheet.columns, id: \.self) { column in
                let isSelected = highlighted.contains(column)
                Text(CellAddress.columnName(column))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                    .background {
                        if column == 0 {
                            GeometryReader { proxy in
                                Color.clear.preference(key: ColumnWidthKey.self, value: proxy.size.width)
                            }
                        }
                    }
                    .gridLines()
            }
        }
        .background(.bar)
        .accessibilityHidden(true)
    }

    private func rowView(_ row: Int, selection: GridSelection, referenced: Set<CellAddress>) -> some View {
        HStack(spacing: 0) {
            let isSelectedRow = selection.rows.contains(row)
            Text("\(row + 1)")
                .font(.system(size: 11, weight: isSelectedRow ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelectedRow ? Color.accentColor : Color.secondary)
                .frame(width: Self.rowHeaderWidth, height: Self.rowHeight)
                .background(isSelectedRow ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
                .gridLines()
                .accessibilityHidden(true)

            ForEach(0..<grid.sheet.columns, id: \.self) { column in
                let address = CellAddress(column: column, row: row)
                let content = content(at: address)
                GridCellView(
                    content: content,
                    isActive: address == selection.active,
                    // A lone cell shows only the active border; ranges get a tint.
                    isInRange: !selection.isSingleCell && selection.contains(address),
                    isReferenced: referenced.contains(address),
                    height: Self.rowHeight
                )
                .gesture(cellGesture(for: address))
                .contextMenu { cellMenu(for: address) }
                .accessibilityLabel("\(address.name), \(content.text.isEmpty ? "empty" : content.text)")
                .accessibilityAddTraits(selection.contains(address) ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { grid.pointerDown(at: address, shift: false, command: false, clickCount: 1); grid.pointerUp() }
            }
        }
    }

    /// Press, drag and release on the cells. A drag's location is relative to
    /// the cell where it began, so the cell under the pointer is found from
    /// the column width and row height.
    private func cellGesture(for origin: CellAddress) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !grid.isPointerDown {
                    let modifiers = NSEvent.modifierFlags
                    grid.pointerDown(
                        at: origin,
                        shift: modifiers.contains(.shift),
                        command: modifiers.contains(.command),
                        clickCount: NSApp.currentEvent?.clickCount ?? 1
                    )
                }
                let column = origin.column + Int((value.location.x / max(columnWidth, 1)).rounded(.down))
                let row = origin.row + Int((value.location.y / Self.rowHeight).rounded(.down))
                grid.pointerDragged(to: CellAddress(column: column, row: row))
            }
            .onEnded { _ in
                grid.pointerUp()
            }
    }

    /// The dot at the selection's bottom-right corner. Drag it to continue
    /// the selected cells — a series, a pattern or copies — into the cells
    /// dragged over; hold ⌥ to make a single number count up.
    @ViewBuilder
    private func fillHandle(selection: GridSelection) -> some View {
        if !grid.isEditing, selection.ranges.count == 1 {
            let corner = selection.current.bottomRight
            FillHandle()
                .offset(
                    x: Self.rowHeaderWidth + CGFloat(corner.column + 1) * columnWidth - FillHandle.hitSize / 2,
                    y: CGFloat(corner.row + 1) * Self.rowHeight - FillHandle.hitSize / 2
                )
                .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.92), value: corner)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.cellSpace))
                        .onChanged { value in
                            let column = Int(((value.location.x - Self.rowHeaderWidth) / max(columnWidth, 1)).rounded(.down))
                            let row = Int((value.location.y / Self.rowHeight).rounded(.down))
                            grid.fillDragged(
                                to: CellAddress(column: max(0, column), row: max(0, row)),
                                series: NSEvent.modifierFlags.contains(.option)
                            )
                        }
                        .onEnded { _ in
                            grid.fillEnded(series: NSEvent.modifierFlags.contains(.option))
                        }
                )
                .help("Drag to fill: continues a series (1, 2, 3…; Item 1, Item 2…; months) or copies. ⌥ makes a single number count up.")
                .accessibilityLabel("Fill handle")
        }
    }

    /// Right-click: acts on the selection when the cell is in it, otherwise
    /// on that cell.
    @ViewBuilder
    private func cellMenu(for address: CellAddress) -> some View {
        Button("Cut") { grid.prepareContextAction(at: address); grid.cutSelection() }
        Button("Copy") { grid.prepareContextAction(at: address); grid.copySelection() }
        Divider()
        Button("Paste") { grid.prepareContextAction(at: address); grid.paste(.normal) }
            .disabled(!grid.canPaste)
        Button("Paste Values Only") { grid.prepareContextAction(at: address); grid.paste(.values) }
            .disabled(!grid.canPaste)
        Divider()
        Button("Clear Contents") { grid.prepareContextAction(at: address); grid.clearSelection() }
    }

    private func content(at address: CellAddress) -> GridCellView.Content {
        if grid.isEditing, address == grid.activeCell {
            return .init(text: grid.editText, alignment: .leading, style: .editing)
        }
        if let preview = grid.fillPreview[address] {
            // What the fill would write, shown faintly while dragging.
            let shown = content(for: preview)
            return .init(text: shown.text, alignment: shown.alignment, style: .preview)
        }
        return content(for: grid.sheet.result(at: address))
    }

    private func content(for result: FormulaCalculation) -> GridCellView.Content {
        switch result {
        case .empty:
            return .init(text: "", alignment: .leading, style: .plain)
        case .failure(let error):
            return .init(text: error.code, alignment: .center, style: .error)
        case .value(let value, _):
            let text = FormulaFormatter.display(value, fractionDigits: Self.cellFractionDigits)
            switch value {
            case .number, .percent, .date: return .init(text: text, alignment: .trailing, style: .plain)
            case .boolean: return .init(text: text, alignment: .center, style: .plain)
            case .text: return .init(text: text, alignment: .leading, style: .plain)
            }
        }
    }
}

private struct ColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Cell

/// One cell. Equatable so SwiftUI only redraws the cells that changed.
private struct GridCellView: View, Equatable {
    struct Content: Equatable {
        enum Style: Equatable { case plain, error, editing, preview }
        let text: String
        let alignment: Alignment
        let style: Style

        static func == (lhs: Content, rhs: Content) -> Bool {
            lhs.text == rhs.text && lhs.style == rhs.style
                && lhs.alignment.horizontal == rhs.alignment.horizontal
        }
    }

    let content: Content
    let isActive: Bool
    let isInRange: Bool
    let isReferenced: Bool
    let height: CGFloat

    var body: some View {
        Text(content.text)
            .font(.system(size: 12, weight: content.style == .error ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(content.style == .error ? Color.red : content.style == .preview ? Color.secondary : Color.primary)
            .italic(content.style == .preview)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 5)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: content.alignment)
            .background(fill)
            .gridLines()
            .contentShape(Rectangle())
    }

    private var fill: Color {
        if content.style == .preview { return Color.accentColor.opacity(0.06) }
        if isReferenced { return Color.teal.opacity(0.18) }
        // The active cell stays clear inside a range, as in a spreadsheet.
        if isInRange, !isActive { return Color.accentColor.opacity(0.16) }
        return .clear
    }
}

// MARK: - Selection layer

/// The selection's outline, the active cell's border and the copy border,
/// drawn over the cells as shapes so they can animate from cell to cell the
/// way they do in Numbers or Google Sheets.
private struct SelectionLayer: View {
    let selection: GridSelection
    let isEditing: Bool
    let copied: CellRange?
    let isCut: Bool
    let fillTarget: CellRange?
    let fillLabel: String?
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let leading: CGFloat
    let animated: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !selection.isSingleCell {
                ForEach(Array(selection.ranges.enumerated()), id: \.offset) { _, range in
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: width(of: range), height: height(of: range))
                        .offset(origin(of: range))
                }
            }
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: isEditing ? 2.5 : 2)
                .frame(width: columnWidth, height: rowHeight)
                .offset(origin(of: CellRange(selection.active)))

            if let fillTarget {
                Rectangle()
                    .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: width(of: fillTarget), height: height(of: fillTarget))
                    .offset(origin(of: fillTarget))
                if let fillLabel {
                    // The value the fill ends on, just past the far corner.
                    Text(fillLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .fixedSize()
                        .offset(
                            x: origin(of: fillTarget).width + width(of: fillTarget) + 4,
                            y: origin(of: fillTarget).height + height(of: fillTarget) - rowHeight / 2 - 9
                        )
                        .transition(.opacity)
                }
            }

            if let copied {
                MarchingAnts(animated: animated, isCut: isCut)
                    .frame(width: width(of: copied) + 2, height: height(of: copied) + 2)
                    .offset(origin(of: copied))
                    .offset(x: -1, y: -1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(animated ? .spring(response: 0.16, dampingFraction: 0.92) : nil, value: selection)
        .animation(animated ? .easeOut(duration: 0.15) : nil, value: copied)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func origin(of range: CellRange) -> CGSize {
        CGSize(width: leading + CGFloat(range.topLeft.column) * columnWidth,
               height: CGFloat(range.topLeft.row) * rowHeight)
    }

    private func width(of range: CellRange) -> CGFloat { CGFloat(range.columnCount) * columnWidth }
    private func height(of range: CellRange) -> CGFloat { CGFloat(range.rowCount) * rowHeight }
}

/// The small square at a selection's corner that fills when dragged, with
/// a larger invisible target so it's easy to grab.
private struct FillHandle: View {
    static let hitSize: CGFloat = 14

    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: isHovered ? 9 : 7, height: isHovered ? 9 : 7)
            .overlay(Rectangle().strokeBorder(Color(nsColor: .textBackgroundColor), lineWidth: 1.5))
            .frame(width: Self.hitSize, height: Self.hitSize)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// The moving dashed border around copied cells. Still when Reduce Motion is
/// on.
private struct MarchingAnts: View {
    let animated: Bool
    let isCut: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                ants(phase: CGFloat(context.date.timeIntervalSinceReferenceDate * 16).truncatingRemainder(dividingBy: 8))
            }
        } else {
            ants(phase: 0)
        }
    }

    private func ants(phase: CGFloat) -> some View {
        Rectangle()
            .strokeBorder(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 1.5, dash: isCut ? [3, 3] : [4, 4], dashPhase: -phase)
            )
            .background(Rectangle().strokeBorder(Color(nsColor: .textBackgroundColor), lineWidth: 1.5))
    }
}

// MARK: - Sheet tabs

/// The sheets along the bottom. Click shows one, Shift-click groups a run,
/// ⌘-click adds or removes one, double-click renames, right-click for more.
private struct SheetTabBar: View {
    @ObservedObject var grid: GridModel

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(grid.workbook.sheets.enumerated()), id: \.offset) { index, sheet in
                        SheetTab(
                            name: sheet.name,
                            isActive: index == grid.workbook.activeIndex,
                            isGrouped: grid.workbook.groupedIndices.contains(index),
                            isRenaming: grid.renamingSheet == index,
                            onRename: { grid.renameSheet(index, to: $0) },
                            onCancelRename: { grid.cancelRenaming() }
                        )
                        .onTapGesture {
                            let modifiers = NSEvent.modifierFlags
                            grid.clickSheet(
                                index,
                                shift: modifiers.contains(.shift),
                                command: modifiers.contains(.command),
                                clickCount: NSApp.currentEvent?.clickCount ?? 1
                            )
                        }
                        .contextMenu {
                            Button("Rename…") { grid.beginRenaming(index) }
                            Button("Delete Sheet", role: .destructive) { grid.deleteSheet(index) }
                                .disabled(!grid.workbook.canDeleteSheet)
                            Divider()
                            Button("Add Sheet") { grid.addSheet() }
                                .disabled(!grid.workbook.canAddSheet)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                grid.addSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!grid.workbook.canAddSheet)
            .help("Add a sheet")
            .accessibilityLabel("Add sheet")

            if grid.workbook.isGrouped {
                Label("\(grid.workbook.groupedIndices.count) sheets grouped", systemImage: "square.stack.3d.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Typing, clearing and pasting change every grouped sheet. Click one tab to ungroup.")
            }
        }
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.035))
    }
}

private struct SheetTab: View {
    let name: String
    let isActive: Bool
    let isGrouped: Bool
    let isRenaming: Bool
    let onRename: (String) -> Void
    let onCancelRename: () -> Void

    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Sheet name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 90)
                    .focused($isFieldFocused)
                    .onAppear {
                        draft = name
                        isFieldFocused = true
                    }
                    .onSubmit { onRename(draft) }
                    .onChange(of: isFieldFocused) { focused in
                        if !focused { onRename(draft) }
                    }
            } else {
                Text(name)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isGrouped ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isGrouped ? Color.accentColor.opacity(isActive ? 0.2 : 0.11) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .help(isRenaming ? "" : "Click to show · ⇧-click to group a run · ⌘-click to add · double-click to rename")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private extension View {
    /// Hairlines on the right and bottom; neighbours supply the rest.
    func gridLines() -> some View {
        overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
        }
    }
}
