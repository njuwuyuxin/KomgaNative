#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页折页（镜像模型 + 连续拼接）。
//
// 把像素 `p` 关于折线做镜像得到 `pm = p - 2*s*n`（`s` = 到折线的有符号距离），
// 折回来的那半张纸就是被掀起来区域的镜像：
//
//   s < -r           掀空了：露出下层页面（透明）
//   |s| < r          卷筒：折线附近的圆柱
//   s >= r 且 pm 在纸面内   折回来的那半张纸（白色纸背）
//   s >= r 且 pm 在纸面外   还没翻走的平铺页面（+ 折页边投下的影子）
//
// 三处必须"连成一张纸"：
// - 卷筒和折页在 s = r 处颜色必须相同（都是纸色），中间不能压暗，
//   否则看起来是"两截白的 + 一道缝"（真机上被指出来过）；
// - 自由边只用极淡的暗线表达纸的厚度，不做硬黑边；
// - 影子要贴着自由边、很软，不能留出"缝"。
//
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

const vec3 kPaper = vec3(0.972, 0.966, 0.950);
const vec3 kPaperEdge = vec3(0.86, 0.85, 0.83);

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

    float s = dot(p - uFold, uNormal);
    // 局部卷筒半径：角上细一些，离角越远越粗；下限别太小，否则接缝看得见。
    float cornerDist = distance(p, uCorner);
    float cone = smoothstep(0.0, max(1.0, uConeLen), cornerDist);
    float r = max(1.0, uRadius * mix(0.30, 1.0, cone));

    // 镜像再按局部半径偏一点：自由边因此是一条曲线，而不是一条笔直的镜像线。
    vec2 pm = p - 2.0 * s * uNormal + uNormal * (r * 0.5);
    float mirrorEdge = rectEdgeDistance(pm);

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
            // 卷筒：折线两侧各 r 是一段圆弧。s = ±r 处正好回到纸色，
            // 和两边的平面无缝接上。
            float t = abs(s) / r;
            float m = r * asin(clamp(t, 0.0, 1.0)) * 0.85;
            vec3 ink = sheetAt(uFold - uNormal * m);
            float backAmt = smoothstep(0.15, 0.95, t);
            vec3 paper = mix(ink, kPaper, backAmt);
            // 明暗：折缝处最暗、两侧回到中性；两端都为 1.0，不产生台阶。
            float shade = mix(0.86, 1.0, sqrt(max(0.0, 1.0 - t * t)));
            rgb = paper * shade;
            alpha = 1.0;
        } else if (s > 0.0 && mirrorEdge >= 0.0) {
            // 折回来的那半张纸：形状由镜像后的页边决定（起手是三角形）。
            vec3 ink = sheetAt(pm);
            float lift = clamp(s / peel, 0.0, 1.0);
            // 从折缝处的 0.97 平滑过渡到纸色，接缝处与卷筒一致。
            vec3 paper = mix(kPaper * 0.97, kPaper, smoothstep(0.0, 0.9, lift));
            rgb = mix(paper, ink, 0.04);
            alpha = 1.0;
        } else {
            // 平铺页面；自由边外侧投一道很软的影子（贴着边，不留缝）。
            vec3 ink = sheetAt(p);
            float shadow = 0.0;
            if (s > 0.0 && mirrorEdge < 0.0) {
                shadow = (1.0 - smoothstep(0.0, r * 2.2, -mirrorEdge)) * 0.28 *
                         tailFade;
            }
            rgb = ink * (1.0 - shadow);
            alpha = 1.0;
        }
    }

    fragColor = vec4(rgb * alpha, alpha);
}
