//
//  MiniPlayer.swift
//  VinylPlayer
//
//  Created by Edward Chung on 27/6/2026.
//

import SwiftUI

struct MiniPlayer: View {
    var animation: Namespace.ID
    @Binding var expand: Bool
    
    var height = UIScreen.main.bounds.height / 3
    
    // Safe Area
    var safeArea = UIApplication.shared.windows.first?.safeAreaInsets
    
    // Gesture Offset
    @State var offset: CGFloat = 0
    
    var body: some View {
        VStack {
            Capsule()
                .fill(.gray)
                .frame(width: expand ? 64 : 0, height: expand ?  4 : 0)
                .opacity(expand ? 1 : 0)
                .padding(.top, expand ? safeArea?.top : 0)
                .padding(.vertical, expand ? 32 : 0)
            
            
            HStack(spacing: 16) {

                // Centering Image
                if expand {
                    Spacer(minLength: 0)
                }

                Image(systemName: "person")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: expand ? height : 56, height: expand ? height : 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                if !expand {
                    Text("Taylor Swift")
                        .font(.title2)
                        .fontWeight(.bold)
                        .matchedGeometryEffect(id: "Label", in: animation)
                }
                
                Spacer(minLength: 0)
                
                if !expand {
                    Button(action: {}) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 16) {
                
                HStack {
                    if expand {
                        Text("Taylor Swift")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .fontWeight(.bold)
                            .matchedGeometryEffect(id: "Label", in: animation)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }
                .padding()
                .padding(.top)
                
                
                Spacer(minLength: 0)
            }
            // this will give strech effect
            .frame(width: expand ? nil : 0, height: expand ? nil : 0)
            .opacity(expand ? 1 : 0)
        }
        .frame(maxHeight: expand ? .infinity : 80)
        .background(
            BlurView()
                .onTapGesture {
                    withAnimation(.spring) {
                        expand = true
                    }
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: expand ? 24 : 0))
        .offset(y: offset)
        .gesture(DragGesture().onEnded(onended(value:)).onChanged(onchanged(value:)))
        .ignoresSafeArea()
    }
    
    func onchanged(value: DragGesture.Value) {
        // Only allowing when its expanded...
        if value.translation.height > 0 && expand {
            offset = value.translation.height
        }
    }
    
    func onended(value: DragGesture.Value) {
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.95, blendDuration: 0.95)) {
            // if value is > than height / 3 then closing view...
            if value.translation.height > height {
                expand = false
            }
            offset = 0
        }
    }
}

#Preview {
    MPNPTesting()
}
