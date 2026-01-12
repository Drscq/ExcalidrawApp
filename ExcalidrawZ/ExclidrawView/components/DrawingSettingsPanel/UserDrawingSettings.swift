//
//  UserDrawingSettings.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import Foundation

/// User drawing settings for Excalidraw
struct UserDrawingSettings: Codable {
    var currentItemStrokeWidth: Double?
    var currentItemStrokeColor: String?
    var currentItemBackgroundColor: String?
    var currentItemStrokeStyle: ExcalidrawStrokeStyle?
    var currentItemFillStyle: ExcalidrawFillStyle?
    var currentItemRoughness: Double?
    var currentItemOpacity: Double?
    var currentItemFontFamily: FontFamily?
    var currentItemFontSize: Double?
    var currentItemTextAlign: String?
    var currentItemRoundness: ExcalidrawStrokeSharpness?
    var currentItemArrowType: ArrowType?
    var currentItemStartArrowhead: Nullable<Arrowhead>?
    var currentItemEndArrowhead: Nullable<Arrowhead>?

    /// Convert to JSON string for JavaScript
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(currentItemStrokeWidth, forKey: .currentItemStrokeWidth)
        try container.encodeIfPresent(currentItemStrokeColor, forKey: .currentItemStrokeColor)
        try container.encodeIfPresent(currentItemBackgroundColor, forKey: .currentItemBackgroundColor)
        try container.encodeIfPresent(currentItemStrokeStyle, forKey: .currentItemStrokeStyle)
        try container.encodeIfPresent(currentItemFillStyle, forKey: .currentItemFillStyle)
        try container.encodeIfPresent(currentItemRoughness, forKey: .currentItemRoughness)
        try container.encodeIfPresent(currentItemOpacity, forKey: .currentItemOpacity)
        try container.encodeIfPresent(currentItemFontFamily, forKey: .currentItemFontFamily)
        try container.encodeIfPresent(currentItemFontSize, forKey: .currentItemFontSize)
        try container.encodeIfPresent(currentItemTextAlign, forKey: .currentItemTextAlign)
        try container.encodeIfPresent(currentItemRoundness, forKey: .currentItemRoundness)
        try container.encodeIfPresent(currentItemArrowType, forKey: .currentItemArrowType)
        try container.encodeIfPresent(currentItemStartArrowhead, forKey: .currentItemStartArrowhead)
        try container.encodeIfPresent(currentItemEndArrowhead, forKey: .currentItemEndArrowhead)
    }

    enum CodingKeys: String, CodingKey {
        case currentItemStrokeWidth
        case currentItemStrokeColor
        case currentItemBackgroundColor
        case currentItemStrokeStyle
        case currentItemFillStyle
        case currentItemRoughness
        case currentItemOpacity
        case currentItemFontFamily
        case currentItemFontSize
        case currentItemTextAlign
        case currentItemRoundness
        case currentItemArrowType
        case currentItemStartArrowhead
        case currentItemEndArrowhead
    }

    /// Create from dictionary (from JavaScript message)
    static func from(dict: [String: Any]) -> UserDrawingSettings {
        var settings = UserDrawingSettings()
        settings.currentItemStrokeWidth = dict["currentItemStrokeWidth"] as? Double
        settings.currentItemStrokeColor = dict["currentItemStrokeColor"] as? String
        settings.currentItemBackgroundColor = dict["currentItemBackgroundColor"] as? String

        // Convert string to enum types
        if let strokeStyle = dict["currentItemStrokeStyle"] as? String {
            settings.currentItemStrokeStyle = ExcalidrawStrokeStyle(rawValue: strokeStyle)
        }
        if let fillStyle = dict["currentItemFillStyle"] as? String {
            settings.currentItemFillStyle = ExcalidrawFillStyle(rawValue: fillStyle)
        }

        settings.currentItemRoughness = dict["currentItemRoughness"] as? Double
        settings.currentItemOpacity = dict["currentItemOpacity"] as? Double
        if let fontFamilyValue = dict["currentItemFontFamily"] as? Int {
            settings.currentItemFontFamily = FontFamily(rawValue: fontFamilyValue)
        }
        settings.currentItemFontSize = dict["currentItemFontSize"] as? Double
        settings.currentItemTextAlign = dict["currentItemTextAlign"] as? String
        if let roundness = dict["currentItemRoundness"] as? String {
            settings.currentItemRoundness = ExcalidrawStrokeSharpness(rawValue: roundness)
        }
        if let arrowType =  dict["currentItemArrowType"] as? ArrowType {
            settings.currentItemArrowType = arrowType
        }

        // Handle arrowheads with proper null/undefined distinction
        // undefined (field not present) -> nil (Swift Optional)
        // null (field present but null) -> .null (Nullable enum)
        // value (field has value) -> .value(Arrowhead) (Nullable enum)
        if dict.keys.contains("currentItemStartArrowhead") {
            if let arrowheadStr = dict["currentItemStartArrowhead"] as? String,
               let arrowhead = Arrowhead(rawValue: arrowheadStr) {
                settings.currentItemStartArrowhead = .value(arrowhead)
            } else {
                // Explicit null from JavaScript
                settings.currentItemStartArrowhead = .null
            }
        }
        // else: field not present -> nil (undefined)

        if dict.keys.contains("currentItemEndArrowhead") {
            if let arrowheadStr = dict["currentItemEndArrowhead"] as? String,
               let arrowhead = Arrowhead(rawValue: arrowheadStr) {
                settings.currentItemEndArrowhead = .value(arrowhead)
            } else {
                // Explicit null from JavaScript
                settings.currentItemEndArrowhead = .null
            }
        }
        // else: field not present -> nil (undefined)

        return settings
    }
}

extension UserDrawingSettings {
    enum FontFamily: Int, Codable {
        case handDrawn = 5
        case normal = 6
        case code = 8
    }
    
    enum ArrowType: String, Codable {
        case sharp
        case round
        case elbow
    }
}
