//
//  ExcalidrawLinearElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation
import CoreGraphics

typealias Point = CGPoint
extension CGPoint : @retroactive Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(x)
    hasher.combine(y)
  }
}

struct FixedPointBinding: Codable, Hashable {
    typealias FixedPoint = [Double]
    enum BindMode: String, Codable {
        case inside, orbit, skip
    }
    
    var elementID: String

    // Represents the fixed point binding information in form of a vertical and
    // horizontal ratio (i.e. a percentage value in the 0.0-1.0 range). This ratio
    // gives the user selected fixed point by multiplying the bound element width
    // with fixedPoint[0] and the bound element height with fixedPoint[1] to get the
    // bound element-local point coordinate.
    var fixedPoint: FixedPoint

    // Determines whether the arrow remains outside the shape or is allowed to
    // go all the way inside the shape up to the exact fixed point.
    var mode: BindMode
    
    enum CodingKeys: String, CodingKey {
        case elementID = "elementId"
        case fixedPoint
        case mode
    }
}

struct LagacyPointBinding: Codable, Hashable {
    var elementID: String?
    var focus: Double?
    var gap: Double?
    
    enum CodingKeys: String, CodingKey {
        case elementID = "elementId"
        case focus
        case gap
    }
}

enum PointBinding: Codable, Hashable {
    case fixed(FixedPointBinding)
    case lagacy(LagacyPointBinding)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let pointBinding = try? container.decode(FixedPointBinding.self) {
            self = .fixed(pointBinding)
        } else {
            self = try .lagacy(LagacyPointBinding(from: decoder))
        }
    }
}

struct FixedSegment: Codable, Hashable {
    typealias Index = String

    var start: Point
    var end: Point
    var index: Index
}

enum Arrowhead: String, Codable {
    case arrow
    case bar
    case dot // legacy. Do not use for new elements.
    case circle
    case circleOutline = "circle_outline"
    case triangle
    case triangleOutline = "triangle_outline"
    case diamond
    case diamondOutline = "diamond_outline"
    case crowfootOne = "crowfoot_one"
    case crowfootMany = "crowfoot_many"
    case crowfootOneOrMany = "crowfoot_one_or_many"
}

protocol ExcalidrawLinearElementBase: ExcalidrawElementBase {
    var points: [Point] { get }
    var lastCommittedPoint: Point? { get }
    var startBinding: PointBinding? { get }
    var endBinding: PointBinding? { get }
    var startArrowhead: Arrowhead? { get }
    var endArrowhead: Arrowhead? { get }
}

struct ExcalidrawLinearElement: ExcalidrawLinearElementBase {
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
    var type: ExcalidrawElementType

    var points: [Point]
    var lastCommittedPoint: Point?
    var startBinding: PointBinding?
    var endBinding: PointBinding?
    var startArrowhead: Arrowhead?
    var endArrowhead: Arrowhead?

    enum CodingKeys: String, CodingKey {
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
        case type
        case points
        case lastCommittedPoint
        case startBinding
        case endBinding
        case startArrowhead
        case endArrowhead
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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
        try container.encode(type, forKey: .type)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(lastCommittedPoint, forKey: .lastCommittedPoint)
        if let startBinding {
            try container.encode(startBinding, forKey: .startBinding)
        } else {
            try container.encodeNil(forKey: .startBinding)
        }
        if let endBinding {
            try container.encode(endBinding, forKey: .endBinding)
        } else {
            try container.encodeNil(forKey: .endBinding)
        }
        if let startArrowhead {
            try container.encode(startArrowhead, forKey: .startArrowhead)
        } else {
            try container.encodeNil(forKey: .startArrowhead)
        }
        if let endArrowhead {
            try container.encode(endArrowhead, forKey: .endArrowhead)
        } else {
            try container.encodeNil(forKey: .endArrowhead)
        }
    }
    
    /// ignore `version`, `versionNounce`, `updated`
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id &&
            lhs.x == rhs.x &&
            lhs.y == rhs.y &&
            lhs.strokeColor == rhs.strokeColor &&
            lhs.backgroundColor == rhs.backgroundColor &&
            lhs.fillStyle == rhs.fillStyle &&
            lhs.strokeWidth == rhs.strokeWidth &&
            lhs.strokeStyle == rhs.strokeStyle &&
            lhs.roundness == rhs.roundness &&
            lhs.roughness == rhs.roughness &&
            lhs.opacity == rhs.opacity &&
            lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.angle == rhs.angle &&
            lhs.seed == rhs.seed &&
            lhs.isDeleted == rhs.isDeleted &&
            lhs.groupIds == rhs.groupIds &&
            lhs.frameId == rhs.frameId &&
            lhs.boundElements == rhs.boundElements &&
            lhs.link == rhs.link &&
            lhs.locked == rhs.locked &&
            lhs.customData == rhs.customData &&
            lhs.type == rhs.type &&
            lhs.points == rhs.points &&
            lhs.lastCommittedPoint == rhs.lastCommittedPoint &&
            lhs.startBinding == rhs.startBinding &&
            lhs.endBinding == rhs.endBinding &&
            lhs.startArrowhead == rhs.startArrowhead &&
            lhs.endArrowhead == rhs.endArrowhead
    }
}

struct ExcalidrawArrowElement: ExcalidrawLinearElementBase {
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
    var type: ExcalidrawElementType

    var points: [Point]
    var lastCommittedPoint: Point?
    var startBinding: PointBinding?
    var endBinding: PointBinding?
    var startArrowhead: Arrowhead?
    var endArrowhead: Arrowhead?
    var elbowed: Bool

    // Elbow arrow specific fields
    var fixedSegments: [FixedSegment]?
    var startIsSpecial: Bool?
    var endIsSpecial: Bool?

    enum CodingKeys: String, CodingKey {
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
        case type
        case points
        case lastCommittedPoint
        case startBinding
        case endBinding
        case startArrowhead
        case endArrowhead
        case elbowed
        case fixedSegments
        case startIsSpecial
        case endIsSpecial
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.x = try container.decode(Double.self, forKey: .x)
        self.y = try container.decode(Double.self, forKey: .y)
        self.strokeColor = try container.decode(String.self, forKey: .strokeColor)
        self.backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        self.fillStyle = try container.decode(ExcalidrawFillStyle.self, forKey: .fillStyle)
        self.strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
        self.strokeStyle = try container.decode(ExcalidrawStrokeStyle.self, forKey: .strokeStyle)
        self.roundness = try container.decodeIfPresent(ExcalidrawRoundness.self, forKey: .roundness)
        self.roughness = try container.decode(Double.self, forKey: .roughness)
        self.opacity = try container.decode(Double.self, forKey: .opacity)
        self.width = try container.decode(Double.self, forKey: .width)
        self.height = try container.decode(Double.self, forKey: .height)
        self.angle = try container.decode(Double.self, forKey: .angle)
        self.seed = try container.decode(Int.self, forKey: .seed)
        self.version = try container.decode(Int.self, forKey: .version)
        self.versionNonce = try container.decode(Int.self, forKey: .versionNonce)
        self.index = try container.decodeIfPresent(String.self, forKey: .index)
        self.isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        self.groupIds = try container.decode([String].self, forKey: .groupIds)
        self.frameId = try container.decodeIfPresent(String.self, forKey: .frameId)
        self.boundElements = try container.decodeIfPresent([ExcalidrawBoundElement].self, forKey: .boundElements)
        self.updated = try container.decodeIfPresent(Double.self, forKey: .updated)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
        self.locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
        self.customData = try container.decodeIfPresent([String : AnyCodable].self, forKey: .customData)
        self.type = try container.decode(ExcalidrawElementType.self, forKey: .type)
        self.points = try container.decode([Point].self, forKey: .points)
        self.lastCommittedPoint = try container.decodeIfPresent(Point.self, forKey: .lastCommittedPoint)
        self.startBinding = try container.decodeIfPresent(PointBinding.self, forKey: .startBinding)
        self.endBinding = try container.decodeIfPresent(PointBinding.self, forKey: .endBinding)
        self.startArrowhead = try container.decodeIfPresent(Arrowhead.self, forKey: .startArrowhead)
        self.endArrowhead = try container.decodeIfPresent(Arrowhead.self, forKey: .endArrowhead)
        self.elbowed = try container.decodeIfPresent(Bool.self, forKey: .elbowed) ?? false
        self.fixedSegments = try container.decodeIfPresent([FixedSegment].self, forKey: .fixedSegments)
        self.startIsSpecial = try container.decodeIfPresent(Bool.self, forKey: .startIsSpecial)
        self.endIsSpecial = try container.decodeIfPresent(Bool.self, forKey: .endIsSpecial)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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
        try container.encode(type, forKey: .type)
        try container.encode(points, forKey: .points)
        if let lastCommittedPoint {
            try container.encode(lastCommittedPoint, forKey: .lastCommittedPoint)
        } else {
            try container.encodeNil(forKey: .lastCommittedPoint)
        }
        if let startBinding {
            try container.encode(startBinding, forKey: .startBinding)
        } else {
            try container.encodeNil(forKey: .startBinding)
        }
        if let endBinding {
            try container.encode(endBinding, forKey: .endBinding)
        } else {
            try container.encodeNil(forKey: .endBinding)
        }
        if let startArrowhead {
            try container.encode(startArrowhead, forKey: .startArrowhead)
        } else {
            try container.encodeNil(forKey: .startArrowhead)
        }
        if let endArrowhead {
            try container.encode(endArrowhead, forKey: .endArrowhead)
        } else {
            try container.encodeNil(forKey: .endArrowhead)
        }
        try container.encode(elbowed, forKey: .elbowed)
        if let fixedSegments {
            try container.encode(fixedSegments, forKey: .fixedSegments)
        } else {
            try container.encodeNil(forKey: .fixedSegments)
        }
        if let startIsSpecial {
            try container.encode(startIsSpecial, forKey: .startIsSpecial)
        } else {
            try container.encodeNil(forKey: .startIsSpecial)
        }
        if let endIsSpecial {
            try container.encode(endIsSpecial, forKey: .endIsSpecial)
        } else {
            try container.encodeNil(forKey: .endIsSpecial)
        }
    }
    
    /// ignore `version`, `versionNounce`, `updated`
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id &&
            lhs.x == rhs.x &&
            lhs.y == rhs.y &&
            lhs.strokeColor == rhs.strokeColor &&
            lhs.backgroundColor == rhs.backgroundColor &&
            lhs.fillStyle == rhs.fillStyle &&
            lhs.strokeWidth == rhs.strokeWidth &&
            lhs.strokeStyle == rhs.strokeStyle &&
            lhs.roundness == rhs.roundness &&
            lhs.roughness == rhs.roughness &&
            lhs.opacity == rhs.opacity &&
            lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.angle == rhs.angle &&
            lhs.seed == rhs.seed &&
            lhs.isDeleted == rhs.isDeleted &&
            lhs.groupIds == rhs.groupIds &&
            lhs.frameId == rhs.frameId &&
            lhs.boundElements == rhs.boundElements &&
            lhs.link == rhs.link &&
            lhs.locked == rhs.locked &&
            lhs.customData == rhs.customData &&
            lhs.type == rhs.type &&
            lhs.points == rhs.points &&
            lhs.lastCommittedPoint == rhs.lastCommittedPoint &&
            lhs.startBinding == rhs.startBinding &&
            lhs.endBinding == rhs.endBinding &&
            lhs.startArrowhead == rhs.startArrowhead &&
            lhs.endArrowhead == rhs.endArrowhead &&
            lhs.elbowed == rhs.elbowed &&
            lhs.fixedSegments == rhs.fixedSegments &&
            lhs.startIsSpecial == rhs.startIsSpecial &&
            lhs.endIsSpecial == rhs.endIsSpecial
    }
}
