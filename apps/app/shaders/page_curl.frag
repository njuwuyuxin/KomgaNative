#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页卷页（折页模型）。
//
// 沿折线法线把屏幕分成五段（`s` = 像素到折线的有符号距离，正方向是"还没翻走"的一侧）：
//
//   s < -r           已经掀空：露出下层页面（透明）
//   -r ≤ s < 0       卷筒：纸绕折线卷成的圆柱（白色纸背、带明暗）
//   0 ≤ s < flapEnd  折回来的那一半纸：盖在页面上，看到的是白色纸背
//   flapEnd 附近     纸背的自由边：薄薄一条暗边 + 投在页面上的影子
//   s ≥ flapEnd      还没翻走的平铺页面
//
// 关键点：
// - 折回来的那半（flap）**必须画出来**。只画一根卷筒的话，看起来像"一个细柱在滚"，
//   而不是"整页纸被翻起来盖住"——参考图里最显眼的就是那一大片白色纸背。
// - 卷筒半径从"被捏住的角"往外逐渐变粗，所以起手是一个尖的页脚。
// - 全部只画在纸面矩形内，收尾时整页从右侧退出去。
// - **只有一个出口**：带 sampler 的 main 里多个 return 在 Windows 上可能编不过
//   （flutter issue 190809），这里统一算完再写 fragColor。

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
const vec3 kPaperShadow = vec3(0.80, 0.79, 0.77);

vec3 sheetAt(vec2 p) {
    vec2 uv = (p - uRect.xy) / uRect.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return kPaper;
    }
    return texture(uSheet, uv).rgb;
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    // 纸只会出现在自己的矩形里。
    bool outside = p.x < uRect.x || p.x > uRect.x + uRect.z ||
                   p.y < uRect.y || p.y > uRect.y + uRect.w;

    // 局部卷筒半径：角上很细（页脚），离角越远越粗。
    float cornerDist = distance(p, uCorner);
    float cone = smoothstep(0.0, max(1.0, uConeLen), cornerDist);
    float r = max(1.0, uRadius * mix(0.18, 1.0, cone));

    float s = dot(p - uFold, uNormal);

    // 已经掀起来的长度 = 折点到被捏住的角的距离；折回来的那半从折线量同样远。
    // 角上折回来的少一些（`cone`），自由边就成了一条曲线，而不是笔直的一刀。
    float peel = clamp(-dot(uCorner - uFold, uNormal), 0.0, uRect.z * 2.5);
    float flapEnd = peel * mix(0.62, 1.0, cone);

    float tailFade = 1.0 - smoothstep(0.82, 1.0, uProgress);

    vec3 rgb = vec3(0.0);
    float alpha = 0.0;

    if (!outside && s > -r) {
        if (s < 0.0) {
            // 卷筒：弧长回采样，白色纸背为主，保留圆柱明暗。
            float t = -s / r;
            float m = r * asin(clamp(t, 0.0, 1.0));
            vec3 ink = sheetAt(uFold - uNormal * m);
            float back = smoothstep(0.10, 0.75, t);
            rgb = mix(ink, kPaper, back);
            float curve = sqrt(max(0.0, 1.0 - t * t));
            rgb *= mix(0.60, 1.03, curve);
            alpha = 1.0;
        } else if (s < flapEnd) {
            // 折回来的那半：白色纸背（带一点点透印），越靠自由边越亮。
            vec3 ink = sheetAt(uFold - uNormal * s);
            float lift = s / max(flapEnd, 1.0);
            vec3 paper =
                mix(kPaper * 0.94, kPaper, smoothstep(0.0, 0.75, lift));
            rgb = mix(paper, ink, 0.10);

            // 自由边：薄薄一条暗边（纸的厚度）。
            float edge = smoothstep(flapEnd - 5.0, flapEnd, s);
            rgb = mix(rgb, kPaperShadow, edge * 0.85);

            // 折线附近压一点暗，做出"纸是从这儿折起来的"。
            float crease = 1.0 - smoothstep(0.0, r * 0.9, s);
            rgb *= mix(1.0, 0.86, crease * tailFade);
            alpha = 1.0;
        } else {
            // 平铺页面 + 折页边投下的影子。
            vec3 ink = sheetAt(p);
            float shadow =
                (1.0 - smoothstep(0.0, r * 1.6, s - flapEnd)) * 0.35 * tailFade;
            rgb = ink * (1.0 - shadow);
            alpha = 1.0;
        }
    }

    fragColor = vec4(rgb * alpha, alpha);
}
