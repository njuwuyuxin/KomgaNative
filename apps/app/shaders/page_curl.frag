#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页折页（精确镜像模型）。
//
// 把像素 `p` 关于折线做镜像得到 `pm = p - 2*s*n`（`s` = 到折线的有符号距离，
// 正方向是"还没翻走"的一侧）。折回来的那半张纸就是**被掀起来的区域的镜像**：
//
//   s < -r           掀空了：露出下层页面（透明）
//   |s| < r          卷筒：折线附近的圆柱（白色纸背 + 明暗）
//   s >= r 且 pm 在纸面内   折回来的那半张纸：白色纸背，边界就是镜像后的页边
//   s >= r 且 pm 在纸面外   还没翻走的平铺页面（+ 折页边投下的影子）
//
// 关键：折页的形状**由镜像决定**，不是"离折线多远"的等距带。
// 等距带会画出一条贯穿页面的带子，起手也永远没有三角形；镜像出来才是
// "掀起来的那一角"（小进度时是三角形，中段是随页边裁出的四边形）。
//
// 全部只画在纸面矩形内；收尾时整页连同纸背从右侧退出去。
// 只有一个出口：带 sampler 的 main 里多个 return 在 Windows 上可能编不过
// （flutter issue 190809）。

uniform vec2 uSize;      // 画布尺寸（逻辑像素）
uniform vec4 uRect;      // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uFold;      // 折线经过的点
uniform vec2 uNormal;    // 折线法线，指向"还没翻走"的一侧（书脊方向）
uniform float uRadius;   // 卷筒最大半径（像素）
uniform float uProgress; // 0..1，收尾时淡出阴影
uniform vec2 uCorner;    // 被捏住的角（页脚从这里翘起）
uniform float uConeLen;  // 半径从角长到满值所需的距离
uniform sampler2D uSheet;

out vec4 fragColor;

const vec3 kPaper = vec3(0.965, 0.958, 0.940);
const vec3 kPaperShadow = vec3(0.78, 0.77, 0.75);

vec3 sheetAt(vec2 p) {
    vec2 uv = (p - uRect.xy) / uRect.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return kPaper;
    }
    return texture(uSheet, uv).rgb;
}

// >0：在纸面内，离最近边的距离；<0：在纸面外。
float rectEdgeDistance(vec2 p) {
    return min(min(p.x - uRect.x, uRect.x + uRect.z - p.x),
               min(p.y - uRect.y, uRect.y + uRect.w - p.y));
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    vec2 d = p - uFold;
    float s = dot(d, uNormal);

    // 镜像点：折回来的纸在这里取材料（它就是被掀起来区域翻过去的样子）。
    vec2 pm = p - 2.0 * s * uNormal;
    float mirrorEdge = rectEdgeDistance(pm);

    // 局部卷筒半径：角上很细（页脚），离角越远越粗。
    float cornerDist = distance(p, uCorner);
    float cone = smoothstep(0.0, max(1.0, uConeLen), cornerDist);
    float r = max(1.0, uRadius * mix(0.16, 1.0, cone));

    // 已经掀起来的长度，只用来做明暗归一化。
    float peel = clamp(-dot(uCorner - uFold, uNormal), 1.0, uRect.z * 2.5);
    float tailFade = 1.0 - smoothstep(0.80, 1.0, uProgress);

    bool outside = p.x < uRect.x || p.x > uRect.x + uRect.z ||
                   p.y < uRect.y || p.y > uRect.y + uRect.w;

    vec3 rgb = vec3(0.0);
    float alpha = 0.0;

    if (!outside) {
        if (s < -r) {
            // 掀空了：透明，露出下层页面。
        } else if (abs(s) < r) {
            // 卷筒：折线两侧各 r 范围内是卷起来的那一段，按弧长回采样。
            float t = abs(s) / r;
            float m = r * asin(clamp(t, 0.0, 1.0)) * 0.85;
            vec3 ink = sheetAt(uFold - uNormal * m);
            float back = smoothstep(0.12, 0.80, t);
            rgb = mix(ink, kPaper, back);
            rgb *= mix(0.60, 1.03, sqrt(max(0.0, 1.0 - t * t)));
            alpha = 1.0;
        } else if (s > 0.0 && mirrorEdge >= 0.0) {
            // 折回来的那半张纸：形状由镜像页边决定 → 起手就是三角形。
            vec3 ink = sheetAt(pm);
            float lift = clamp(s / peel, 0.0, 1.0);
            vec3 paper = mix(kPaper * 0.95, kPaper, smoothstep(0.0, 0.85, lift));
            // 只有很淡的一层透印（4%）：纸背是白纸，不是半透明描图纸。
            rgb = mix(paper, ink, 0.04);

            // 自由边：薄薄一条暗边（纸的厚度）。
            float edge = 1.0 - smoothstep(0.0, 6.0, mirrorEdge);
            rgb = mix(rgb, kPaperShadow, edge * 0.80);

            // 折线附近压一点暗，做出"纸是从这儿折起来的"。
            float crease = 1.0 - smoothstep(0.0, r * 1.1, s);
            rgb *= mix(1.0, 0.87, crease * tailFade);
            alpha = 1.0;
        } else {
            // 平铺页面；折页自由边的外侧投一道影子。
            vec3 ink = sheetAt(p);
            float shadow = 0.0;
            if (s > 0.0 && mirrorEdge < 0.0) {
                shadow = (1.0 - smoothstep(0.0, r * 1.6, -mirrorEdge)) *
                         0.35 * tailFade;
            }
            rgb = ink * (1.0 - shadow);
            alpha = 1.0;
        }
    }

    fragColor = vec4(rgb * alpha, alpha);
}
