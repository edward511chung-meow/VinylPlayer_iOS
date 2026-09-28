//
//  CoverFlowTesting.swift
//  VinylPlayer
//
//  Created by Edward Chung on 27/6/2026.
//

import SwiftUI

struct CoverFlowTesting: View {
    @State private var activeIndex: Int?
    @State private var elevation: CGFloat = -8
    
    var body: some View {
        VStack {
            let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .indigo, .black, .brown, .orange, .cyan]
            
            CoverFlow(config: .init(cardWidth: 224, activeElevation: elevation), activeIndex: $activeIndex) {
                ForEach(colors, id: \.self) { color in
                    Rectangle()
                        .fill(color.gradient)
                }
            }
            .frame(height: 224)
//            .onChange(of: activeIndex) { oldValue, newValue in
//                print(newValue)
//            }
            
            Group {
                Slider(value: $elevation, in: 0...50)
                Text("\(elevation)")
                
                Button("Go to 4") {
                    withAnimation(.smooth) {
                        activeIndex = 4
                    }
                }
//                .hidden()
            }
            .hidden()
        }
    }
}

#Preview {
    CoverFlowTesting()
        .preferredColorScheme(.dark)
}
