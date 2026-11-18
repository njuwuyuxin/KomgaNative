#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页卷曲 —— 圆柱模型（几何见 packages/komga_reader_engine/lib/src/page_turn.dart）。
//
// 纸沿一根半径 R 的圆柱卷过去。设 u 为从轴线指向"被卷起一侧"的单位向量，
// 屏幕点 p 到轴线的有符号距离 d = (p − A)·u。纸上一点到轴线的弧长记 s：
//
//   s <= 0          平铺在原位，屏幕上 d = s
//   0 < s < πR      绕在圆柱上，θ = s/R，屏幕上 d = R·sinθ
//   s >= πR         翻过去平压在上面（背面朝上），屏幕上 d = πR − s（< 0）
//
// 每个像素反推它可能对应的纸面点 q（逆映射），从下往上合成：
//   平铺正面 → 圆柱正面 → 圆柱背面 → 翻过去的背面
// 同一套参数化推出所有层，纸面天然连续，不会有缝。
//
// 只有一个出口：带 sampler 的 main 里多个 return 在 Windows 上可能编不过
// （flutter issue 190809）。

uniform vec2 uSize;     // 画布尺寸（逻辑像素）
uniform vec4 uRect;     // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uAxis;     // 圆柱轴线经过的点（画布坐标）
uniform vec2 uDir;      // u：单位向量，从轴线指向被卷起的一侧
uniform float uRadius;  // 圆柱半径（px），可以为 0（折痕）
uniform sampler2D uSheet;

out vec4 fragColor;

const float kPi = 3.14159265;
const vec3 kPaper = vec3(0.975, 0.970, 0.955);

// 纸背透出来的墨迹浓度：真实纸张会隐约透印，完全纯白反而像塑料片。
const float kShowThrough = 0.07;

// q 到纸面矩形边缘的有符号距离（内部为正）。
float edgeDistance(vec2 q) {
    return min(min(q.x - uRect.x, uRect.x + uRect.z - q.x),
               min(q.y - uRect.y, uRect.y + uRect.w - q.y));
}

// 1px 抗锯齿的覆盖率。
float coverage(vec2 q) {
    return clamp(edgeDistance(q) + 0.5, 0.0, 1.0);
}

vec3 sheetAt(vec2 q) {
    vec2 uv = clamp((q - uRect.xy) / uRect.zw, 0.0, 1.0);
    return texture(uSheet, uv).rgb;
}

// 纸背：白纸 + 很淡的透印（镜像的墨迹本来就在同一个 q 上）。
vec3 backAt(vec2 q) {
    return mix(kPaper, sheetAt(q), kShowThrough);
}

// 预乘 alpha 的 "over" 合成。
vec4 over(vec4 dst, vec3 rgb, float a) {
    return vec4(rgb * a, a) + dst * (1.0 - a);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec2 u = uDir;
    float r = max(uRadius, 0.0);
    float d = dot(p - uAxis, u);

    // 光源在 (u, z) 平面里略偏向被卷起的一侧：卷筒背面靠上处出现一道高光，
    // 正面越接近侧立越暗——这就是卷筒的立体感。
    vec3 light = normalize(vec3(0.42, 0.0, 0.91));
    vec3 halfVec = normalize(light + vec3(0.0, 0.0, 1.0));

    vec4 color = vec4(0.0);

    // ---- 1. 平铺在原位的正面（d <= 0）----
    // 其余位置是露出来的下一页，这里只往上叠一层投影。
    float flatCov = coverage(p) * (1.0 - smoothstep(-0.5, 0.5, d));
    vec3 flatRgb = sheetAt(p);

    // 卷筒顶端（θ = π/2）对应的纸面点：判断这条线上到底有没有纸在卷。
    vec2 qTop = p + u * (r * kPi * 0.5 - d);
    float rollHere = clamp(edgeDistance(qTop) / 6.0 + 0.5, 0.0, 1.0);

    // 贴着轴线的接触阴影：卷起的纸挡住了一部分环境光。
    float contact = exp(min(d, 0.0) / (0.6 * r + 2.0));
    flatRgb *= 1.0 - 0.16 * contact * rollHere;

    // 翻过去的那半张纸投在平铺纸面上的影子：离它的边越近越实。
    vec2 qFlip = p + u * (kPi * r - 2.0 * d);
    float outside = max(-edgeDistance(qFlip), 0.0);
    float flipShadow = 1.0 - smoothstep(0.0, 4.0 + 1.6 * r, outside);
    float flipLift = clamp(r / 6.0, 0.25, 1.0);
    flatRgb *= 1.0 - 0.26 * flipShadow * flipLift * step(d, 0.0);

    color = over(color, flatRgb, flatCov);

    // 露出来的下一页上，卷筒投下的影子（只输出半透明黑，叠在下层 widget 上）。
    float beyond = max(d - r, 0.0);
    float revealShadow = 0.38 * exp(-beyond / (3.0 + 0.9 * r)) * rollHere;
    revealShadow *= step(0.0, d) * (1.0 - flatCov);
    color = over(color, vec3(0.0), revealShadow * (1.0 - color.a));

    // ---- 2./3. 圆柱：同一个 d 对应正面（θ < π/2）和背面（θ > π/2）两层 ----
    if (r > 0.01 && d >= 0.0 && d <= r) {
        float base = asin(clamp(d / r, 0.0, 1.0));
        // 圆柱轮廓处的抗锯齿：d → r 时两层都收成一条线。
        float rim = clamp((r - d) + 0.5, 0.0, 1.0);

        float thetaF = base;
        vec2 qF = p + u * (r * thetaF - d);
        vec3 nF = vec3(-sin(thetaF), 0.0, cos(thetaF));
        float diffF = clamp(dot(nF, light), 0.0, 1.0);
        vec3 rgbF = sheetAt(qF) * mix(0.55, 1.04, diffF);
        color = over(color, rgbF, coverage(qF) * rim);

        float thetaB = kPi - base;
        vec2 qB = p + u * (r * thetaB - d);
        vec3 nB = vec3(sin(thetaB), 0.0, -cos(thetaB));
        float diffB = clamp(dot(nB, light), 0.0, 1.0);
        float specB = pow(clamp(dot(nB, halfVec), 0.0, 1.0), 24.0);
        vec3 rgbB = backAt(qB) * mix(0.62, 1.0, diffB) + vec3(0.22 * specB);
        color = over(color, rgbB, coverage(qB) * rim);
    }

    // ---- 4. 翻过去平压在上面的背面（d < 0，最高的一层）----
    if (d < 0.5) {
        float cov = coverage(qFlip) * (1.0 - smoothstep(-0.5, 0.5, d));
        // 靠近卷筒处稍亮（接着卷筒背面的高光），往外略暗，避免一整片死白。
        float fade = exp(d / (2.0 * r + 24.0));
        vec3 rgb = backAt(qFlip) * mix(0.90, 0.99, fade);
        color = over(color, rgb, cov);
    }

    fragColor = color;
}
