//
//  Nullable.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 2026/01/12.
//

import Foundation

/// A type that distinguishes between null and a value
/// Combined with Swift's Optional, this provides three states:
/// - nil (Swift Optional) = undefined (field not present)
/// - .null (Nullable) = null (field explicitly set to null)
/// - .value(T) (Nullable) = concrete value
enum Nullable<T: Codable>: Codable, Equatable where T: Equatable {
    case null       // Explicit null value
    case value(T)   // Concrete value

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else {
            let value = try container.decode(T.self)
            self = .value(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .value(let value):
            try container.encode(value)
        }
    }

    /// Get the wrapped value if present
    var value: T? {
        switch self {
        case .value(let v):
            return v
        case .null:
            return nil
        }
    }

    /// Check if the value is null
    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    /// Check if the value has a concrete value
    var hasValue: Bool {
        if case .value = self {
            return true
        }
        return false
    }
}

// MARK: - Convenience Initializers

extension Nullable {
    /// Create from an optional value
    /// - Parameter optional: The optional value to wrap
    /// - Returns: `.value(wrapped)` if non-nil, `.null` if nil
    init(_ optional: T?) {
        if let value = optional {
            self = .value(value)
        } else {
            self = .null
        }
    }
}

// MARK: - CustomStringConvertible

extension Nullable: CustomStringConvertible {
    var description: String {
        switch self {
        case .null:
            return "null"
        case .value(let value):
            return "\(value)"
        }
    }
}
