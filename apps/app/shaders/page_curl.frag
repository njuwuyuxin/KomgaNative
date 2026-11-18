#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页卷曲。
//
// 模型：纸面绕一条（可能倾斜的）折线卷成圆柱。
// - 屏幕坐标投影到折线法线上得到 s = dot(p - fold, normal)：
//   s > 0 是还没翻走的平铺部分；-R < s <= 0 是卷起来的圆筒；
//   s <= -R 已经翻走，露出下层页面，只在边缘留一条投上去的影子。
// - 圆筒内的像素按弧长回采样原图（m = R * asin(-s / R)），
//   所以越靠折线内容被压得越扁——这就是"纸被卷起来"的拉伸感。
// - **圆筒永远不透明**：纸是有厚度的白纸，采样越界时就是纸背（白色）。
// - **卷筒半径不是常数**：从"被捏住的角"往外逐渐变粗（`uConeLen`），
//   所以起手只是角上一个尖尖的页脚，翻起来才变成完整的卷筒。
// - **只画在纸面矩形内**：纸不会跑到书页区域之外，收尾时卷筒从右边缘滑出去。
// - 倾角/半径都来自 Dart 侧（komga_reader_engine 的 curlGeometry）。
//
// 注意：fragColor 用**预乘 alpha**，Flutter 的 blend 按预乘解释。

uniform vec2 uSize;      // 画布尺寸（逻辑像素）
uniform vec4 uRect;      // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uFold;      // 折线经过的点
uniform vec2 uNormal;    // 折线法线，指向"还没翻走"的一侧（书脊方向）
uniform float uRadius;   // 卷筒最大半径（像素）
uniform float uProgress; // 0..1，收尾时要淡出阴影
uniform vec2 uCorner;    // 被捏住的角（页脚从这里翘起）
uniform float uConeLen;  // 半径从角长到满值所需的距离
uniform sampler2D uSheet;

out vec4 fragColor;

// 纸背的颜色（偏暖的白）。
const vec3 kPaper = vec3(0.965, 0.958, 0.940);

void main() {
    vec2 p = FlutterFragCoord().xy;

    // 纸只会出现在自己的矩形里：矩形外什么都不画（黑色背景/书页外不应有白条）。
    if (p.x < uRect.x || p.x > uRect.x + uRect.z ||
        p.y < uRect.y || p.y > uRect.y + uRect.w) {
        fragColor = vec4(0.0);
        return;
    }

    // 局部卷筒半径：角上很细（页脚），离角越远越粗（完整卷筒）。
    float cornerDist = distance(p, uCorner);
    float cone = smoothstep(0.0, max(1.0, uConeLen), cornerDist);
    float r = max(1.0, uRadius * mix(0.18, 1.0, cone));

    float s = dot(p - uFold, uNormal);

    // 收尾淡出：进度接近 1 时接触阴影/投影都要收掉，避免最后一帧"啪"地消失。
    float tailFade = 1.0 - smoothstep(0.80, 1.0, uProgress);

    vec4 color = vec4(0.0);

    if (s >= 0.0) {
        // 平铺：直接采样。靠近折线处压一点暗，做出"纸压弯了"的接触感。
        vec2 uv = (p - uRect.xy) / uRect.zw;
        vec4 ink = texture(uSheet, uv);
        float contact = (1.0 - smoothstep(0.0, r * 0.55, s)) * tailFade;
        color = vec4(ink.rgb * mix(1.0, 0.82, contact), ink.a);
    } else if (s > -r) {
        // 圆筒：弧长回采样。越靠外沿越是"纸背"，但**始终不透明**。
        float t = -s / r;
        float m = r * asin(clamp(t, 0.0, 1.0));
        vec2 q = uFold - uNormal * m;
        vec2 uv = (q - uRect.xy) / uRect.zw;
        bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
        // 越界就是纸的边缘：直接给纸背颜色，不要回退成透明。
        vec3 ink = inside ? texture(uSheet, uv).rgb : kPaper;

        // 越靠外沿越是纸背；起手时整段都是刚翘起来的纸背。
        float back = smoothstep(0.15, 0.85, t);
        color = vec4(mix(ink, kPaper, back), 1.0);

        // 圆柱明暗：越靠近折线越暗（背光），外沿略亮。
        float curve = sqrt(max(0.0, 1.0 - t * t));
        color.rgb *= mix(0.62, 1.04, curve);
    } else {
        // 已经翻走：只画投在下层页面上的影子，收尾淡出。
        float d = -s - r;
        float shadow = (1.0 - smoothstep(0.0, r * 1.9, d)) * tailFade;
        color = vec4(0.0, 0.0, 0.0, 0.42 * shadow);
    }

    fragColor = vec4(color.rgb * color.a, color.a);
}
