//
//  ArrowheadNone.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/12/26.
//

import SwiftUI

struct ArrowheadNone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.5*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.875*width, y: 0.5*height))
        path.move(to: CGPoint(x: 0.125*width, y: 0.375*height))
        path.addLine(to: CGPoint(x: 0.375*width, y: 0.625*height))
        path.move(to: CGPoint(x: 0.125*width, y: 0.625*height))
        path.addLine(to: CGPoint(x: 0.375*width, y: 0.375*height))
        return path
    }
}

#Preview {
    ArrowheadNone()
        .stroke(.primary, lineWidth: 2)
        .frame(width: 20, height: 20)
}
