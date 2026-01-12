//
//  ExcalidrawFrameLikeElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/19/25.
//

import Foundation

struct ExcalidrawFrameLikeElement: ExcalidrawElementBase {
    var type: ExcalidrawElementType
    
    var id: String
    var x: Double
    var y: Double
    var strokeColor: String
    var backgroundColor: String
    var fillStyle: ExcalidrawFillStyle
    var strokeWidth: Double
    var strokeStyle: ExcalidrawStrokeStyle
    var roundness: ExcalidrawRoundness?
    var roughness: Double
    var opacity: Double
    var width: Double
    var height: Double
    var angle: Double
    var seed: Int
    var version: Int
    var versionNonce: Int
    var index: String?
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
    
    var name: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case x
        case y
        case strokeColor
        case backgroundColor
        case fillStyle
        case strokeWidth
        case strokeStyle
        case roundness
        case roughness
        case opacity
        case width
        case height
        case angle
        case seed
        case version
        case versionNonce
        case index
        case isDeleted
        case groupIds
        case frameId
        case boundElements
        case updated
        case link
        case locked
        case customData
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(fillStyle, forKey: .fillStyle)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(strokeStyle, forKey: .strokeStyle)
        if let roundness {
            try container.encode(roundness, forKey: .roundness)
        } else {
            try container.encodeNil(forKey: .roundness)
        }
        try container.encode(roughness, forKey: .roughness)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(angle, forKey: .angle)
        try container.encode(seed, forKey: .seed)
        try container.encode(version, forKey: .version)
        try container.encode(versionNonce, forKey: .versionNonce)
        if let index {
            try container.encode(index, forKey: .index)
        } else {
            try container.encodeNil(forKey: .index)
        }
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(groupIds, forKey: .groupIds)
        if let frameId {
            try container.encode(frameId, forKey: .frameId)
        } else {
            try container.encodeNil(forKey: .frameId)
        }
        if let boundElements {
            try container.encode(boundElements, forKey: .boundElements)
        } else {
            try container.encodeNil(forKey: .boundElements)
        }
        try container.encodeIfPresent(updated, forKey: .updated)
        if let link {
            try container.encode(link, forKey: .link)
        } else {
            try container.encodeNil(forKey: .link)
        }
        try container.encodeIfPresent(locked, forKey: .locked)
        try container.encodeIfPresent(customData, forKey: .customData)
        if let name {
            try container.encode(name, forKey: .name)
        } else {
            try container.encodeNil(forKey: .name)
        }
    }
}
