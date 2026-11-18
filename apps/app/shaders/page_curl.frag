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
// - **圆筒永远不透明**：纸是有厚度的白纸，采样越界时就是纸背（白色），
//   不能返回透明去露出下层，否则卷边看起来像一层玻璃。
// - 倾角/半径都来自 Dart 侧（komga_reader_engine 的 curlGeometry），
//   这里只做几何与明暗，不掺手感参数。
//
// 注意：fragColor 用**预乘 alpha**，Flutter 的 blend 按预乘解释。

uniform vec2 uSize;     // 画布尺寸（逻辑像素）
uniform vec4 uRect;     // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uFold;     // 折线经过的点
uniform vec2 uNormal;   // 折线法线，指向"还没翻走"的一侧（书脊方向）
uniform float uRadius;  // 圆柱半径（像素）
uniform float uProgress; // 0..1，收尾时要淡出阴影，避免"啪"一下消失
uniform sampler2D uSheet;

out vec4 fragColor;

// 纸背的颜色（偏暖的白，和纸张质感一致）。
const vec3 kPaper = vec3(0.965, 0.958, 0.940);

void main() {
    vec2 p = FlutterFragCoord().xy;
    float s = dot(p - uFold, uNormal);

    // 收尾淡出：进度接近 1 时接触阴影/投影都要收掉，
    // 否则最后一帧会"啪"地闪一下（前后页尺寸不同时更明显）。
    float tailFade = 1.0 - smoothstep(0.80, 1.0, uProgress);

    vec4 color = vec4(0.0);

    if (s >= 0.0) {
        // 平铺：直接采样。靠近折线处压一点暗，做出"纸压弯了"的接触感。
        vec2 uv = (p - uRect.xy) / uRect.zw;
        bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
        color = inside ? texture(uSheet, uv) : vec4(0.0);
        float contact =
            (1.0 - smoothstep(0.0, uRadius * 0.55, s)) * tailFade;
        color.rgb *= mix(1.0, 0.82, contact);
    } else if (s > -uRadius) {
        // 圆筒：弧长回采样。越靠外沿越是"纸背"，但**始终不透明**。
        float t = -s / uRadius;
        float m = uRadius * asin(clamp(t, 0.0, 1.0));
        vec2 q = uFold - uNormal * m;
        vec2 uv = (q - uRect.xy) / uRect.zw;
        bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
        // 越界就是纸的边缘：直接给纸背颜色，不要回退成透明。
        vec3 ink = inside ? texture(uSheet, uv).rgb : kPaper;

        // 起手时整段都是"刚翘起来的纸背"，翻起来之后才逐渐露出印的那一面。
        float back = smoothstep(0.15, 0.85, t);
        color = vec4(mix(ink, kPaper, back), 1.0);

        // 圆柱明暗：越靠近折线越暗（背光），外沿略亮。
        float curve = sqrt(max(0.0, 1.0 - t * t));
        color.rgb *= mix(0.62, 1.04, curve);
    } else {
        // 已经翻走：只画投在下层页面上的影子，收尾淡出。
        float d = -s - uRadius;
        float shadow =
            (1.0 - smoothstep(0.0, uRadius * 1.9, d)) * tailFade;
        color = vec4(0.0, 0.0, 0.0, 0.42 * shadow);
    }

    fragColor = vec4(color.rgb * color.a, color.a);
}
