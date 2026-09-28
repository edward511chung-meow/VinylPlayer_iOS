  //
//  MPNPTesting.swift
//  VinylPlayer
//
//  Created by Edward Chung on 27/6/2026.
//

import SwiftUI

struct MPNPTesting: View {
    @State var current = 2
    
    // MiniPlayer Properties
    @State var expand = false
    
    @Namespace var animation
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .bottom)) {
            TabView(selection: $current) {
                Text("Library")
                    .tag(0)
                    .tabItem {
                        Image(systemName: "rectangle.stack.fill")
                        
                        Text("Library")
                    }
                
                Text("Radio")
                    .tag(0)
                    .tabItem {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        
                        Text("Radio")
                    }
            }
            
            MiniPlayer(animation: animation, expand: $expand)
        }
    }
}

#Preview {
    MPNPTesting()
}
