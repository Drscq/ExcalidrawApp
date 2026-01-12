//
//  DrawingSettingsPanel.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/05.
//

import SwiftUI

/// The main drawing settings panel that allows users to configure default drawing properties
/// This panel replicates excalidraw's settings interface
struct DrawingSettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var settings: UserDrawingSettings
    let onSettingsChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stroke Color
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsStrokeTitle)) {
                ColorButtonGroup(
                    colors: ColorPalette.strokeQuickPicks,
                    selectedColor: settings.currentItemStrokeColor ?? "#1e1e1e"
                ) { color in
                    settings.currentItemStrokeColor = color
                    onSettingsChange()
                }
            }
            
            // Background Color
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsBackgroundTitle)) {
                ColorButtonGroup(
                    colors: ColorPalette.backgroundQuickPicks,
                    selectedColor: settings.currentItemBackgroundColor ?? "transparent"
                ) { color in
                    settings.currentItemBackgroundColor = color
                    onSettingsChange()
                }
            }
            
            // Font Family
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsFontFamilyTitle)) {
                OptionButtonGroup(
                    options: [.handDrawn, .normal, .code],
                    selectedValue: settings.currentItemFontFamily ?? .handDrawn
                ) { value in
                    settings.currentItemFontFamily = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .handDrawn:
                            Image(systemSymbol: .pencil)
                        case .normal:
                            Image(systemSymbol: .character)
                        case .code:
                            Image(systemSymbol: .chevronLeftForwardslashChevronRight)
                    }
                }
            }

            // Font Size
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsFontSizeTitle)) {
                OptionButtonGroup(
                    options: [16.0, 20.0, 28.0, 36.0],
                    selectedValue: settings.currentItemFontSize ?? 20
                ) { value in
                    settings.currentItemFontSize = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case 16:
                            Text("S")
                        case 20:
                            Text("M")
                        case 28:
                            Text("L")
                        case 36:
                            Text("XL")
                        default:
                            Text(value.formatted())
                    }
                }
            }

            // Text Align
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsTextAlignTitle)) {
                OptionButtonGroup(
                    options: ["left", "center", "right"],
                    selectedValue: settings.currentItemTextAlign ?? "left"
                ) { value in
                    settings.currentItemTextAlign = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case "left":
                            Image(systemSymbol: .textAlignleft)
                        case "center":
                            Image(systemSymbol: .textAligncenter)
                        case "right":
                            Image(systemSymbol: .textAlignright)
                        default:
                            Text(value)
                    }
                }
            }
            
            // Fill Style
            if settings.currentItemBackgroundColor != "transparent" {
                SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsFillTitle)) {
                    OptionButtonGroup(
                        options: [ExcalidrawFillStyle.hachure, ExcalidrawFillStyle.crossHatch, ExcalidrawFillStyle.solid],
                        selectedValue: settings.currentItemFillStyle ?? .solid
                    ) { value in
                        settings.currentItemFillStyle = value
                        onSettingsChange()
                    } label: { value in
                        switch value {
                            case .hachure:
                                Image("FillHachureIcon")
                                    .apply { content in
                                        if colorScheme == .dark {
                                            content.colorInvert()
                                        } else {
                                            content
                                        }
                                    }
                            case .crossHatch:
                                Image("FillCrossHatchIcon")
                                    .apply { content in
                                        if colorScheme == .dark {
                                            content.colorInvert()
                                        } else {
                                            content
                                        }
                                    }
                            case .solid:
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.primary)
                                    .padding(1)
                                    .frame(width: 20, height: 20)
                            case .zigzag:
                                Text("ZigZag")
                        }
                    }
                }
            }
            
            // Stroke Width
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsStrokeWidthTitle)) {
                StrokeWidthPicker(
                    widths: [1, 2, 4],
                    selectedWidth: settings.currentItemStrokeWidth ?? 2
                ) { width in
                    settings.currentItemStrokeWidth = width
                    onSettingsChange()
                }
            }
            
            // Stroke Style
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsStrokeStyleTitle)) {
                OptionButtonGroup(
                    options: [
                        ExcalidrawStrokeStyle.solid,
                        ExcalidrawStrokeStyle.dashed,
                        ExcalidrawStrokeStyle.dotted
                    ],
                    selectedValue: settings.currentItemStrokeStyle ?? .solid
                ) { value in
                    settings.currentItemStrokeStyle = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .solid:
                            Text("—")
                        case .dashed:
                            Text("- -")
                        case .dotted:
                            Text("· · ·")
                    }
                }
            }

            // Sloppiness (Roughness)
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsSloppinessTitle)) {
                OptionButtonGroup(
                    options: [0.0, 1.0, 2.0],
                    selectedValue: settings.currentItemRoughness ?? 1
                ) { value in
                    settings.currentItemRoughness = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case 0.0:
                            SloppinessArchitectIcon()
                        case 1.0:
                            SloppinessArtistIcon()
                        case 2.0:
                            SloppinessCartoonistIcon()
                        default:
                            Text("\(Int(value))")
                    }
                }
            }
            
            // Edges (Roundness)
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsEdgeTitle)) {
                OptionButtonGroup(
                    options: [
                        ExcalidrawStrokeSharpness.sharp,
                        ExcalidrawStrokeSharpness.round
                    ],
                    selectedValue: settings.currentItemRoundness ?? .round
                ) { value in
                    settings.currentItemRoundness = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .sharp:
                            Image("EdgeSharpIcon")
                                .apply { content in
                                    if colorScheme == .dark {
                                        content.colorInvert()
                                    } else {
                                        content
                                    }
                                }
                        case .round:
                            Image("EdgeRoundIcon")
                                .apply { content in
                                    if colorScheme == .dark {
                                        content.colorInvert()
                                    } else {
                                        content
                                    }
                                }
                    }
                }
            }
            
            // Arrow Type
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsStartArrowTypeTitle)) {
                OptionButtonGroup(
                    options: [.sharp, .round, .elbow],
                    selectedValue: settings.currentItemArrowType ?? .sharp
                ) { value in
                    settings.currentItemArrowType = value
                    onSettingsChange()
                } label: { value in
                    switch value {
                        case .sharp:
                            Image(systemSymbol: .arrowUpRight)
                        case .round:
                            Image(systemSymbol: .arrowTurnUpRight)
                        case .elbow:
                            if #available(macOS 15.0, iOS 18.0, *) {
                                Image(systemSymbol: .arrowTriangleheadSwap)
                            } else {
                                Image(systemSymbol: .arrowTriangleSwap)
                            }
                    }
                }
            }
            
            // Arrowhead
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsStartArrowheadTitle)) {
                HStack(spacing: 8) {
                    ArrowheadPicker(
                        selectedArrowhead: Binding(
                            get: { settings.currentItemStartArrowhead },
                            set: { newValue in
                                settings.currentItemStartArrowhead = newValue
                            }
                        ),
                        direction: .start,
                        onEditingChanged: { editing in
                            if !editing {
                                onSettingsChange()
                            }
                        }
                    )
                    
                    ArrowheadPicker(
                        selectedArrowhead: Binding(
                            get: { settings.currentItemEndArrowhead },
                            set: { newValue in
                                settings.currentItemEndArrowhead = newValue
                            }
                        ),
                        direction: .end,
                        onEditingChanged: { editing in
                            if !editing {
                                onSettingsChange()
                            }
                        }
                    )
                }
            }

            
            // Opacity
            SettingSection(title: String(localizable: .settingsExcalidrawDrawingSettingsOpacityTitle)) {
                OpacitySlider(
                    opacity: Binding(
                        get: { settings.currentItemOpacity ?? 100 },
                        set: { newValue in
                            settings.currentItemOpacity = Double(Int(newValue))
                        }
                    ),
                    onEditingChanged: { editing in
                        // Only trigger settings change when user stops dragging
                        if !editing {
                            onSettingsChange()
                        }
                    }
                )
            }
        }
        .animation(
            .smooth,
            value: settings.currentItemBackgroundColor != "transparent"
        )
    }
}

// MARK: - Setting Section

/// A reusable section component for settings
private struct SettingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            content()
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var settings = UserDrawingSettings()
        
        var body: some View {
            ScrollView {
                DrawingSettingsPanel(settings: $settings) {
                    print("Settings changed: \(settings)")
                }
                .padding(12)
                .frame(width: 260)
            }
        }
    }
    
    return PreviewWrapper()
}
