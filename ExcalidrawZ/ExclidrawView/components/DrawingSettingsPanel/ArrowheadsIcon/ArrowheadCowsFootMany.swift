//
//  ArrowheadCowsFootMany.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/12/26.
//

import SwiftUI

struct ArrowheadCowsFootMany: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.85*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.15*width, y: 0.5*height))
        path.move(to: CGPoint(x: 0.375*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.175*width, y: 0.25*height))
        path.move(to: CGPoint(x: 0.375*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.175*width, y: 0.75*height))
        return path
    }
}
