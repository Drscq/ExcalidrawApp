//
//  ArrowheadArrow.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/12/26.
//

import SwiftUI

struct ArrowheadArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.85*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.15*width, y: 0.5*height))
        path.move(to: CGPoint(x: 0.85*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.675*width, y: 0.25*height))
        path.move(to: CGPoint(x: 0.85*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.675*width, y: 0.75*height))
        path.move(to: CGPoint(x: 0.6875*width, y: 0.25*height))
        path.addLine(to: CGPoint(x: 0.8625*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.6875*width, y: 0.75*height))
        return path
    }
}

#Preview {
    ArrowheadArrow()
        .stroke(.primary)
}
