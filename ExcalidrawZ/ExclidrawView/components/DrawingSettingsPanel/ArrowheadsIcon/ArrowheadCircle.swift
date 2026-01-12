//
//  ArrowheadCircle.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/12/26.
//

import SwiftUI

struct ArrowheadCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        let midY = width * 0.5

        path.move(to: CGPoint(x: 0.55*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.15*width, y: 0.5*height))
        // ---- Circle Arrowhead ----
        let radius = min(width, height) * 0.2   // ~= 4 / 20
        let center = CGPoint(
            x: width * 0.75,               // ~= 30 / 40
            y: midY
        )
        
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return path
    }
}

#Preview {
    ArrowheadCircle()
        .stroke(.primary, lineWidth: 2)
        .frame(width: 40, height: 40)
}
