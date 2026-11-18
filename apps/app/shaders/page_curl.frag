#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页卷曲。
//
// 模型：纸面绕一条（可能倾斜的）折线卷成半径为 uRadius 的圆柱。
// - 屏幕坐标投影到折线法线上得到 s = dot(p - fold, normal)：
//   s > 0 是还没翻走的平铺部分；-R < s <= 0 是卷起来的圆筒；
//   s <= -R 已经翻走，露出下层页面，只在边缘留一条投上去的影子。
// - 圆筒内的像素按弧长回采样原图（m = R * asin(-s / R)），
//   所以越靠折线内容被压得越扁——这就是"纸被卷起来"的拉伸感。
// - 倾角来自 Dart 侧（komga_reader_engine 的 curlGeometry），
//   起手过书页角，临近书脊时立直；这里只做几何，不掺手感参数。
//
// 注意：fragColor 用**预乘 alpha**，Flutter 的 blend 按预乘解释。

uniform vec2 uSize;     // 画布尺寸（逻辑像素）
uniform vec4 uRect;     // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uFold;     // 折线经过的点
uniform vec2 uNormal;   // 折线法线，指向"还没翻走"的一侧（书脊方向）
uniform float uRadius;  // 圆柱半径（像素）
uniform sampler2D uSheet;

out vec4 fragColor;

vec4 sheetAt(vec2 p) {
    vec2 uv = (p - uRect.xy) / uRect.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0);
    }
    return texture(uSheet, uv);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float s = dot(p - uFold, uNormal);

    vec4 color = vec4(0.0);

    if (s >= 0.0) {
        // 平铺：直接采样。靠近折线处压一点暗，做出"纸压弯了"的接触感。
        color = sheetAt(p);
        float contact = 1.0 - smoothstep(0.0, uRadius * 0.55, s);
        color.rgb *= mix(1.0, 0.80, contact);
    } else if (s > -uRadius) {
        // 圆筒：弧长回采样 + 明暗 + 背面反光。
        float t = -s / uRadius;
        float m = uRadius * asin(clamp(t, 0.0, 1.0));
        color = sheetAt(uFold - uNormal * m);
        float curve = sqrt(max(0.0, 1.0 - t * t));
        color.rgb *= mix(0.62, 1.10, curve);
        float back = smoothstep(0.68, 0.98, t);
        color.rgb = mix(color.rgb, vec3(0.95, 0.94, 0.92), back * 0.42);
    } else {
        // 已经翻走：只画投在下层页面上的影子。
        float d = -s - uRadius;
        float shadow = 1.0 - smoothstep(0.0, uRadius * 1.9, d);
        color = vec4(0.0, 0.0, 0.0, 0.40 * shadow);
    }

    fragColor = vec4(color.rgb * color.a, color.a);
}
