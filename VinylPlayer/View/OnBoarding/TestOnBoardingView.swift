//
//  TestOnBoardingView.swift
//  VinylPlayer
//
//  Created by Edward Chung on 2/8/2026.
//

import SwiftUI

struct TestOnBoardingView: View {
    var body: some View {
        let image = UIImage(named: "Screen")
        let title = "Welcome to iOS26"
        let subtitle = "Introducing a new design with\nLiquid Glass."
        
        OnBoarding(items: [
            .init(id: 0, title: title, subtitle: subtitle, screenshot: image),
            .init(id: 1, title: title, subtitle: subtitle, screenshot: image),
            .init(id: 2, title: title, subtitle: subtitle, screenshot: image, zoomScale: 1.3, zoomAnchor: .bottom),
            .init(id: 3, title: title, subtitle: subtitle, screenshot: image, zoomScale: 1.2, zoomAnchor: .init(x: 0.5, y: -0.1)),
            .init(id: 4, title: title, subtitle: subtitle, screenshot: image)
        ]) {
            print("Completed")
        }
    }
}

#Preview {
    TestOnBoardingView()
}
