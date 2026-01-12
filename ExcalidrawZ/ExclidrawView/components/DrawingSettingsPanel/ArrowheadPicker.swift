//
//  ArrowheadPicker.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/12.
//

import SwiftUI

/// Helper function to render an arrowhead icon
@ViewBuilder
func arrowheadIcon(_ arrowhead: Nullable<Arrowhead>?) -> some View {
    let lineWidth: CGFloat = 1
    ZStack {
        if let nullable = arrowhead, case .value(let arrowheadValue) = nullable {
            
            switch arrowheadValue {
                case .arrow:
                    ArrowheadArrow()
                        .stroke(.primary, lineWidth: lineWidth)
                        .scaleEffect(x: -1)
                case .bar:
                    ArrowheadBar()
                        .stroke(.primary, lineWidth: lineWidth)
                case .dot:
                    Circle()
                        .frame(width: 6, height: 6)
                case .circle:
                    ArrowheadCircle()
                        .fill(.primary)
                    ArrowheadCircle()
                        .stroke(.primary, lineWidth: lineWidth)
                case .circleOutline:
                    ArrowheadCircle()
                        .stroke(.primary, lineWidth: lineWidth)
                case .triangle:
                    ArrowheadTriangle()
                        .fill(.primary)
                    ArrowheadTriangle()
                        .stroke(.primary, lineWidth: lineWidth)
                case .triangleOutline:
                    ArrowheadTriangle()
                        .stroke(.primary, lineWidth: lineWidth)
                case .diamond:
                    ArrowheadDiamond()
                        .fill(.primary)
                    ArrowheadDiamond()
                        .stroke(.primary, lineWidth: lineWidth)
                case .diamondOutline:
                    ArrowheadDiamond()
                        .stroke(.primary, lineWidth: lineWidth)
                case .crowfootOne:
                    ArrowheadCowsFootOne()
                        .stroke(.primary, lineWidth: lineWidth)
                case .crowfootMany:
                    ArrowheadCowsFootMany()
                        .stroke(.primary, lineWidth: lineWidth)
                case .crowfootOneOrMany:
                    ArrowheadCowsFootOneOrMany()
                        .stroke(.primary, lineWidth: lineWidth)
            }
        } else if let nullable = arrowhead, nullable.isNull {
            // Explicit null (no arrowhead)
            ArrowheadNone()
                .stroke(.primary, lineWidth: lineWidth)
                .opacity(0.5)
        } else {
            ArrowheadArrow()
                .stroke(.primary, lineWidth: lineWidth)
        }
    }
}

struct ArrowheadButtonLabel: View {
    let arrowhead: Nullable<Arrowhead>?
    
    var body: some View {
        arrowheadIcon(arrowhead)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

    }
}

/// A button for selecting an arrowhead type
struct ArrowheadButton: View {
    let arrowhead: Nullable<Arrowhead>?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ArrowheadButtonLabel(arrowhead: arrowhead)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Arrowhead picker with support for null/undefined values
struct ArrowheadPicker: View {
    @Binding var selectedArrowhead: Nullable<Arrowhead>?
    enum Direction {
        case start, end
    }
    var direction: Direction
    var onEditingChanged: (Bool) -> Void = { _ in }

    // All arrowhead options
    // nil = undefined, .null = null (no arrowhead), .value(T) = specific arrowhead
    private let allArrowheads: [Nullable<Arrowhead>?] = [
        .null, // No arrowhead (explicit null)
        .value(.arrow),
        .value(.bar),
        .value(.triangle),
        .value(.diamond),
        .value(.circle),
        .value(.circleOutline),
        .value(.triangleOutline),
        .value(.diamondOutline),
        .value(.crowfootOne),
        .value(.crowfootMany),
        .value(.crowfootOneOrMany)
    ]

    @State private var showFullPicker = false

    var body: some View {
        // Trigger button
        Button(action: {
            showFullPicker.toggle()
        }) {
            ArrowheadButtonLabel(arrowhead: selectedArrowhead ?? (direction == .end ? .value(.arrow) : .null))
                .scaleEffect(x: direction == .start ? 1 : -1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            showFullPicker ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: showFullPicker ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFullPicker) {
            ArrowheadPickerPopover(
                selectedArrowhead: $selectedArrowhead,
                reverse: direction == .end,
                allArrowheads: allArrowheads,
                onSelect: { arrowhead in
                    selectedArrowhead = arrowhead
                    showFullPicker = false
                    onEditingChanged(false)
                }
            )
        }
    }
}

// MARK: - Arrowhead Picker Popover

/// Full arrowhead picker shown in popover
private struct ArrowheadPickerPopover: View {
    @Binding var selectedArrowhead: Nullable<Arrowhead>?
    var reverse: Bool = false
    let allArrowheads: [Nullable<Arrowhead>?]
    let onSelect: (Nullable<Arrowhead>?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizable: .settingsExcalidrawDrawingSettingsStartArrowheadTitle)
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 4)
            ], spacing: 4) {
                ForEach(allArrowheads.indices, id: \.self) { index in
                    let arrowhead = allArrowheads[index]
                    ArrowheadButton(
                        arrowhead: arrowhead,
                        isSelected: arrowheadsEqual(selectedArrowhead, arrowhead)
                    ) {
                        onSelect(arrowhead)
                    }
                    .scaleEffect(x: reverse ? -1 : 1)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 220)
    }

    // Helper to compare arrowhead values
    private func arrowheadsEqual(_ lhs: Nullable<Arrowhead>?, _ rhs: Nullable<Arrowhead>?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let l), .some(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var startArrowhead: Nullable<Arrowhead>? = .value(.arrow)
        @State private var endArrowhead: Nullable<Arrowhead>? = .null

        var body: some View {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start Arrowhead (value)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ArrowheadPicker(
                        selectedArrowhead: $startArrowhead,
                        direction: .start
                    ) { editing in
                        print("Start arrowhead editing: \(editing), value: \(String(describing: startArrowhead))")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("End Arrowhead (null)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ArrowheadPicker(
                        selectedArrowhead: $endArrowhead,
                        direction: .start
                    ) { editing in
                        print("End arrowhead editing: \(editing), value: \(String(describing: endArrowhead))")
                    }
                }
            }
            .padding()
            .frame(width: 260)
        }
    }

    return PreviewWrapper()
}
