//
//  ArrowheadTriangleOutline.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/12/26.
//

import SwiftUI

struct ArrowheadTriangleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.15*width, y: 0.475*height))
        path.addLine(to: CGPoint(x: 0.675*width, y: 0.475*height))
        path.move(to: CGPoint(x: 0.675*width, y: 0.25*height))
        path.addLine(to: CGPoint(x: 0.85*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.675*width, y: 0.7*height))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ArrowheadTriangleOutline()
        .stroke(.primary, lineWidth: 2)
        .frame(width: 20, height: 20)
}

