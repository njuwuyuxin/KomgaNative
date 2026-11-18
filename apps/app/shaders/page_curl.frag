#version 460 core
#include <flutter/runtime_effect.glsl>

// 翻页折页 —— **连续曲面**版本。
//
// 把纸看成一条一维剖面绕折线扫出来的曲面（折线法线方向记 `s`）：
//
//   s >= 0                     平铺在页面上（高度 0）
//   -R .. 0                    以折线为切点、半径 R 卷起来的一段圆弧（0..bend）
//   s <  -R sin(bend)          圆弧末端的切线延伸出去的"飞起的那半张纸"
//
// 每个像素把所有可能盖住它的那几层都算出来（平面 / 圆弧正面 / 圆弧背面 /
// 切线延伸），取**高度最大**的一层来画。这样：
// - 曲面本身连续，不会出现"两截纸 + 一道缝"；
// - 明暗和镜面高光直接由曲面法线算，卷筒上自然有一道亮边；
// - 飞起的那半张纸是切线延伸，天然和卷筒连在一起，末端还有投影。
//
// 只有一个出口：带 sampler 的 main 里多个 return 在 Windows 上可能编不过
// （flutter issue 190809）。

uniform vec2 uSize;      // 画布尺寸（逻辑像素）
uniform vec4 uRect;      // 纸面矩形：x, y, w, h（画布坐标）
uniform vec2 uFold;      // 折线经过的点（卷起的切点）
uniform vec2 uNormal;    // 折线法线，指向"还没翻走"的一侧（书脊方向）
uniform float uRadius;   // 卷曲半径（像素）
uniform float uProgress; // 0..1，收尾时淡出
uniform vec2 uCorner;    // 被捏住的角（页脚从这里翘起）
uniform float uConeLen;  // 半径从角长到满值所需的距离
uniform float uBend;     // 弯曲角（弧度）
uniform sampler2D uSheet;

out vec4 fragColor;

const vec3 kPaper = vec3(0.972, 0.966, 0.950);
// 光从上方偏左打下来，高光跟着曲面法线走。
const vec3 kLight = vec3(-0.42, 0.0, 0.91);

float rectEdgeDistance(vec2 p) {
    return min(min(p.x - uRect.x, uRect.x + uRect.z - p.x),
               min(p.y - uRect.y, uRect.y + uRect.w - p.y));
}

vec3 sheetAt(vec2 p) {
    vec2 uv = (p - uRect.xy) / uRect.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return kPaper;
    }
    return texture(uSheet, uv).rgb;
}

// 曲面法线（剖面内）：φ = 0 时朝屏幕外，φ 增大转到侧面。
// 返回 (亮度, 高光)。
vec2 shadeAt(float phi, float distToCorner) {
    vec3 n = vec3(sin(phi), 0.0, cos(phi));
    float diff = clamp(dot(n, kLight), 0.0, 1.0);
    vec3 h = normalize(kLight + vec3(0.0, 0.0, 1.0));
    float spec = pow(clamp(dot(n, h), 0.0, 1.0), 42.0);
    // 越靠角越软一点，避免页脚处出现一条生硬亮线。
    spec *= mix(0.5, 1.0, clamp(distToCorner / 80.0, 0.0, 1.0));
    return vec2(mix(0.72, 1.05, diff), spec * 0.55);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    float s = dot(p - uFold, uNormal);
    vec2 tangent = vec2(-uNormal.y, uNormal.x);
    float along = dot(p - uFold, tangent);

    // 半径沿折线变化：角上细、远处粗，起手才是一个尖页脚。
    float cornerDist = distance(p, uCorner);
    float cone = smoothstep(0.0, max(1.0, uConeLen), cornerDist);
    float r = max(2.0, uRadius * mix(0.45, 1.0, cone));

    float bend = clamp(uBend, 0.0, 1.62);
    float tailFade = 1.0 - smoothstep(0.86, 1.0, uProgress);

    bool outside = p.x < uRect.x || p.x > uRect.x + uRect.z ||
                   p.y < uRect.y || p.y > uRect.y + uRect.w;

    // 最高的一层：z 越大越靠上。
    float bestZ = -1.0;
    vec3 bestRgb = vec3(0.0);
    bool bestHit = false;

    if (!outside) {
        // ---- 1. 平铺页面（z = 0）----
        if (s >= 0.0) {
            bestZ = 0.0;
            bestRgb = sheetAt(p);
            bestHit = true;
        }

        // ---- 2. 圆弧：屏幕 s ∈ [-r, 0] 是圆弧的正面；弯曲角超过 90° 后，
        //         同一处屏幕位置还会落到圆弧的背面（更高，盖住正面）。----
        if (s <= 0.0 && s >= -r) {
            float phiFront = asin(clamp(-s / r, 0.0, 1.0));
            float zFront = r * (1.0 - cos(phiFront));
            if (zFront > bestZ) {
                vec2 shade = shadeAt(phiFront, cornerDist);
                vec3 ink = sheetAt(uFold - uNormal * (r * phiFront));
                vec3 rgb = mix(ink, kPaper, smoothstep(0.05, 0.55, phiFront));
                rgb = rgb * shade.x + vec3(shade.y);
                bestZ = zFront;
                bestRgb = rgb;
                bestHit = true;
            }

            // 圆弧背面：φ 从 π - asin(-s/r) 处绕回来，高度更高。
            float phiBack = 3.14159265 - asin(clamp(-s / r, 0.0, 1.0));
            if (phiBack <= bend) {
                float zBack = r * (1.0 - cos(phiBack));
                if (zBack > bestZ) {
                    vec2 shade = shadeAt(phiBack, cornerDist);
                    vec3 ink = sheetAt(uFold - uNormal * (r * phiBack));
                    // 背面：白纸为主，只留很淡的透印。
                    vec3 rgb = mix(mix(kPaper, ink, 0.04), kPaper, 0.6);
                    rgb = rgb * shade.x + vec3(shade.y * 0.7);
                    bestZ = zBack;
                    bestRgb = rgb;
                    bestHit = true;
                }
            }
        }

        // ---- 3. 切线延伸：从圆弧末端沿切线飞出去的那半张纸 ----
        if (abs(cos(bend)) > 0.02) {
            float d = r * bend + (-s - r * sin(bend)) / cos(bend);
            // d >= r*bend 才在圆弧之外；再从折点往回量不能超出纸面。
            if (d >= r * bend && (uFold - uNormal * d).x >= uRect.x - 1.0 &&
                (uFold - uNormal * d).x <= uRect.x + uRect.z + 1.0) {
                float zTail = r * (1.0 - cos(bend)) + (d - r * bend) * sin(bend);
                if (zTail > bestZ) {
                    vec2 shade = shadeAt(bend, cornerDist);
                    vec3 ink = sheetAt(uFold - uNormal * d);
                    vec3 rgb;
                    if (cos(bend) >= 0.0) {
                        // 还没折过 90°：看到的是正面。
                        rgb = mix(ink, kPaper, smoothstep(0.2, 0.9, bend));
                    } else {
                        rgb = mix(mix(kPaper, ink, 0.04), kPaper, 0.6);
                    }
                    rgb = rgb * shade.x + vec3(shade.y * 0.8);
                    bestZ = zTail;
                    bestRgb = rgb;
                    bestHit = true;
                }
            }
        }
    }

    // ---- 投影：纸面（z = 0）被上空那半张纸压出的影子 ----
    vec3 rgb = bestRgb;
    if (bestHit && bestZ > 0.0 && bestZ < 14.0 * r) {
        // 高度越低、影子越实；离折线越远越淡。
        float soft = 1.0 - smoothstep(0.0, 9.0 * r, bestZ);
        float lateral = 1.0 - smoothstep(0.0, 60.0 * r, abs(along));
        rgb *= 1.0 - 0.30 * soft * lateral * tailFade;
    }

    fragColor = vec4(rgb * (bestHit ? 1.0 : 0.0), bestHit ? 1.0 : 0.0);
}
