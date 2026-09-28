//
//  CoverFlowReflection.metal
//  VinylPlayer
//
//  Created by Edward Chung on 27/6/2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[stitchable]]
half4 coverflowReflection(float2 position, SwiftUI::Layer layer, float contentHeight,  float reflectionGap, float fade, float dim) {
    /// Original Content
    if (position.y < contentHeight) {
        return layer.sample(position);
    }
    
    /// Transparent gap between content and reflection
    float start = contentHeight + reflectionGap;
    if (position.y < start) {
        return half4(0);
    }
    
    /// Reflection (Mirror Vertically)
    float poY = position.y - start;
    float2 pos = float2(position.x, contentHeight - poY);
    
    if (pos.y < 0.0) {
        return half4(0);
    }
    
    /// Fade out Reflection
    float progress = poY / contentHeight;
    float alpha = pow(1.0 - clamp(progress, 0.0, 1.0), fade);
    
    
    half4 color = (layer.sample(pos) * alpha) * half4(dim);
    return color;
}
