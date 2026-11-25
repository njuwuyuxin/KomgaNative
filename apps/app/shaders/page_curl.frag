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
//   接收面（平铺正面 / 露出的下层）+ 阴影 → 圆柱正面 → 圆柱背面 → 翻过去的背面
//
// **明暗一律相对平铺纸面**：θ = 0 与 θ = π 处亮度都恰好是 1，所以各层在轴线
// （d = 0）处硬切也看不出缝。早先用绝对光照 + 半像素过渡，轴线上会透出
// 一条细亮线（"高亮虚影"），斜向翻页时最明显。
//
// **纸背**：单页模式是"白纸 + 透印"；双页模式（uHasBack = 1）纸背就是下一屏
// 落在另一半的那页——纸沿书脊（x = uSpineX）镜像平落，所以纸面点 q 的背面
// 取 uBack 在镜像点 (2·spine − q.x, q.y) 处的像素，落地那一帧和真实页面严丝合缝。
//
// 只有一个出口：带 sampler 的 main 里多个 return 在 Windows 上可能编不过
// （flutter issue 190809）。

uniform vec2 uSize;        // 画布尺寸（逻辑像素）
uniform vec4 uRect;        // 被卷纸面的几何矩形：x, y, w, h（画布坐标）
uniform vec4 uSheetUvRect; // 纸面完整纹理矩形（宽页对半裁切时为整张宽页矩形）
uniform vec2 uAxis;        // 圆柱轴线经过的点（画布坐标）
uniform vec2 uDir;         // u：单位向量，从轴线指向被卷起的一侧
uniform float uRadius;     // 圆柱半径（px），可以为 0（折痕）
uniform vec4 uBackRect;    // 纸背落地后的裁剪矩形（画布坐标），uHasBack = 0 时不用
uniform vec4 uBackUvRect;  // 纸背完整纹理矩形（宽页对半裁切时为整张宽页矩形）
uniform float uSpineX;     // 书脊 x（画布坐标），纸背沿它镜像
uniform float uHasBack;    // 0..1：纸背真实页面混合权重（0 = 纸底色，1 = 真实页图，途中加载完平滑渐显）
uniform float uHasSheet;   // 0..1：纸面真实页面混合权重（0 = 纸底色，1 = 真实页图）
uniform float uHinged;     // 1 = 双页铰接书脊（落地帧 R=0 仍须绘制平压背面），0 = 单页
uniform vec3 uPaper;       // 缺省纸张底色（默认暖白纸色；深色模式冷页用深色哑光纸面防刺眼闪白）
uniform sampler2D uSheet;
uniform sampler2D uBack;

out vec4 fragColor;

const float kPi = 3.14159265;

// 纸背透出来的墨迹浓度：真实纸张会隐约透印，完全纯白反而像塑料片。
const float kShowThrough = 0.07;

// 光照：(u, z) 平面里的方向光 + 环境光。只用来算"相对平铺纸面"的明暗比。
const vec2 kLight = vec2(0.42, 0.91);
const float kAmbient = 0.45;

// 卷筒投在下层的影子、翻过去的纸投在页面上的影子（最深处的遮光比例）。
const float kRollShadow = 0.42;
const float kFlapShadow = 0.24;

// q 到纸面矩形的有符号距离：内部为正（到最近边），外部为负（欧氏距离）。
float edgeDistance(vec2 q) {
    vec2 lo = q - uRect.xy;
    vec2 hi = uRect.xy + uRect.zw - q;
    vec2 inside = min(lo, hi);
    float inner = min(inside.x, inside.y);
    vec2 outside = max(-inside, vec2(0.0));
    return inner > 0.0 ? inner : -length(outside);
}

// 1px 抗锯齿的覆盖率。
float coverage(vec2 q) {
    return clamp(edgeDistance(q) + 0.5, 0.0, 1.0);
}

// 双页铰接时忽略书脊那条边的 1px 边缘淡出：书脊是连续铰链而非悬空切边，
// 若在书脊处把覆盖率淡到 0.5，落地前中缝会透出底层旧页。
float hingedCoverage(vec2 q, bool spineOnRight) {
    vec2 lo = q - uRect.xy;
    vec2 hi = uRect.xy + uRect.zw - q;
    if (spineOnRight) {
        if (hi.x < 0.0) return 0.0;
        hi.x = 1e6;
    } else {
        if (lo.x < 0.0) return 0.0;
        lo.x = 1e6;
    }
    vec2 inside = min(lo, hi);
    float inner = min(inside.x, inside.y);
    vec2 outside = max(-inside, vec2(0.0));
    float d = inner > 0.0 ? inner : -length(outside);
    return clamp(d + 0.5, 0.0, 1.0);
}

vec3 sheetAt(vec2 q) {
    vec2 uv = clamp((q - uSheetUvRect.xy) / uSheetUvRect.zw, 0.0, 1.0);
    vec3 page = texture(uSheet, uv).rgb;
    return uHasSheet >= 0.999
        ? page
        : (uHasSheet <= 0.001 ? uPaper : mix(uPaper, page, uHasSheet));
}

// 纸背：双页是镜像过去的真实页面（页面外或冷页渐显前用纸底色），单页是纸底色 + 很淡的透印。
// 双页时以 uBackRect 自身的书脊边为锚点镜像，相邻跨页宽度略有差异时中缝也不会露白条。
vec3 backAt(vec2 q, bool spineOnRight) {
    vec3 blank = mix(uPaper, sheetAt(q), kShowThrough);
    float backSpineX = spineOnRight ? uBackRect.x : uBackRect.x + uBackRect.z;
    float mx = backSpineX + (uSpineX - q.x);
    if (uHinged > 0.5) {
        mx = spineOnRight ? max(mx, backSpineX) : min(mx, backSpineX);
    }
    vec2 m = vec2(mx, q.y);
    vec2 clipUv = (m - uBackRect.xy) / max(uBackRect.zw, vec2(1.0));
    vec2 inside = step(vec2(0.0), clipUv) * step(clipUv, vec2(1.0));
    vec2 texUv = clamp((m - uBackUvRect.xy) / max(uBackUvRect.zw, vec2(1.0)), 0.0, 1.0);
    vec3 page = texture(uBack, texUv).rgb;
    float use = uHasBack * inside.x * inside.y;
    return mix(blank, page, use);
}

// 法线 n（(u, z) 平面）相对平铺纸面（n = (0, 1)）的亮度比。
float relShade(vec2 n) {
    float base = kAmbient + (1.0 - kAmbient) * kLight.y;
    return (kAmbient + (1.0 - kAmbient) * max(dot(n, kLight), 0.0)) / base;
}

// 直线 origin + w * dir 与纸面矩形 uRect 的交区间 [wMin, wMax]；无交时 wMin > wMax。
vec2 rectLineInterval(vec2 origin, vec2 dir) {
    vec2 lo = uRect.xy - origin;
    vec2 hi = uRect.xy + uRect.zw - origin;
    float tMin = -1e9;
    float tMax = 1e9;
    if (abs(dir.x) > 1e-5) {
        float a = lo.x / dir.x;
        float b = hi.x / dir.x;
        tMin = max(tMin, min(a, b));
        tMax = min(tMax, max(a, b));
    } else if (lo.x > 0.0 || hi.x < 0.0) {
        tMin = 1.0;
        tMax = -1.0;
    }
    if (abs(dir.y) > 1e-5) {
        float a = lo.y / dir.y;
        float b = hi.y / dir.y;
        tMin = max(tMin, min(a, b));
        tMax = min(tMax, max(a, b));
    } else if (lo.y > 0.0 || hi.y < 0.0) {
        tMin = 1.0;
        tMax = -1.0;
    }
    return vec2(tMin, tMax);
}

// 平滑阶跃：把轴向区间 [wMin, wMax] 解析软化成连续阴影。
float softStep(float x) {
    return 1.0 / (1.0 + exp(-clamp(x, -16.0, 16.0)));
}

// 若矩形角 c 落在卷筒带 0 <= s <= sMax 内，把它在轴向 t 上的投影并进区间 ext。
vec2 extendByCorner(vec2 ext, vec2 c, vec2 u, vec2 t, float sMax) {
    vec2 rel = c - uAxis;
    float s = dot(rel, u);
    float w = dot(rel, t);
    bool inBand = s >= 0.0 && s <= sMax;
    return inBand ? vec2(min(ext.x, w), max(ext.y, w)) : ext;
}

// 卷在圆柱上的那段纸（0 <= s <= πR）沿轴向 t 的覆盖区间 [wMin, wMax]。
// 它是纸面矩形与带 0 <= s <= πR 的交（凸多边形）在 t 上的投影，顶点只可能是两条带边
// 与矩形的交点或落在带内的矩形角，所以端点随卷页参数与像素都连续，没有离散采样台阶。
vec2 rollExtent(vec2 u, vec2 t, float r) {
    float sMax = kPi * r;
    vec2 ext = vec2(1e9, -1e9);
    vec2 e0 = rectLineInterval(uAxis, t);
    ext = e0.y >= e0.x ? vec2(min(ext.x, e0.x), max(ext.y, e0.y)) : ext;
    vec2 e1 = rectLineInterval(uAxis + u * sMax, t);
    ext = e1.y >= e1.x ? vec2(min(ext.x, e1.x), max(ext.y, e1.y)) : ext;
    vec2 lo = uRect.xy;
    vec2 hi = uRect.xy + uRect.zw;
    ext = extendByCorner(ext, lo, u, t, sMax);
    ext = extendByCorner(ext, vec2(hi.x, lo.y), u, t, sMax);
    ext = extendByCorner(ext, vec2(lo.x, hi.y), u, t, sMax);
    ext = extendByCorner(ext, hi, u, t, sMax);
    return ext;
}

// 轴向位置 a0 那条垂直于轴线的线上，卷起的纸在屏幕上覆盖的 d 区间 [lo, hi]。
// 这条线上纸的弧长区间与 [0, πR] 求交得 [s0, sEnd]，屏幕投影是 R·sin(s/R)：
// hi 是剪影（角附近纸卷不到 π/2，剪影比 R 小），lo 是离轴线最近的那端。
vec2 rollFootprint(vec2 a0, vec2 u, float r) {
    vec2 iv = rectLineInterval(a0, u);
    float s0 = max(iv.x, 0.0);
    float sEnd = min(iv.y, kPi * r);
    float invR = 1.0 / max(r, 1e-3);
    float a = r * sin(clamp(s0 * invR, 0.0, kPi));
    float b = r * sin(clamp(sEnd * invR, 0.0, kPi));
    float top = 0.5 * kPi * r;
    float reach = (s0 <= top && sEnd >= top) ? r : max(a, b);
    return sEnd > s0 ? vec2(min(a, b), reach) : vec2(0.0);
}

// 卷筒投在下层的软阴影：卷筒在 (轴向 w, 法向 d) 平面上的投影近似为
// "w ∈ [wMin, wMax] 且 d ∈ [lo(w), hi(w)]"，影子是它的可分离模糊——
// 轴向用 softStep 解析软化区间端点，法向按到 [lo, hi] 的距离指数衰减；
// 区间外的像素取最近端点处的剪影，所以 lo/hi 全程连续。
// 早先按 θ 切片或沿轴向离散采样，每片在纸页边缘各留一级台阶，卷起尖端下方会叠出分层色块。
float rollShadowAt(vec2 p, vec2 u, vec2 t, float d, float r, float rollLift) {
    vec2 ext = rollExtent(u, t, r);
    float valid = ext.y > ext.x + 1.0 ? 1.0 : 0.0;
    float soft = 2.0 + 0.9 * r;
    float sigma = 0.5 * soft;
    float v = dot(p - uAxis, t);
    float wc = valid > 0.5
        ? clamp(v, ext.x + 0.5, ext.y - 0.5)
        : 0.5 * (ext.x + ext.y);
    vec2 fp = rollFootprint(uAxis + t * wc, u, r);
    // 剪影越低（角附近）影子越淡。
    float strength = smoothstep(0.0, 0.6 * r, fp.y);
    float axial = softStep((v - ext.x) / sigma) - softStep((v - ext.y) / sigma);
    float gap = max(fp.x - d, 0.0) + max(d - fp.y, 0.0);
    return kRollShadow * rollLift * valid * axial * strength * exp(-gap / soft);
}

// 翻过去的那片纸（平压在高度 ~2R 处）投在屏幕点 p 上的影子。
//
// clampToAxis = true 用于平铺正面与圆柱正面（d > 0 按 d = 0 求值，使影子连续越过轴线，
// 避免卷筒两端出现"灰 | 白"硬斜边）；clampToAxis = false 用于露出的下层，
// d > 0 时额外计入到轴线的距离，确保页面外跨 d = 0 连续过渡。
float flapShadowAt(vec2 p, vec2 u, float d, float r, bool clampToAxis) {
    float dc = min(d, 0.0);
    vec2 qFlip = p - u * d + u * (dc + kPi * r - 2.0 * dc);
    float outside = max(-edgeDistance(qFlip), 0.0);
    float dist = (!clampToAxis && d > 0.0) ? length(vec2(d, outside)) : outside;
    float soft = 2.0 + 0.8 * r;
    float lift = clamp(r / 8.0, 0.0, 1.0);
    return kFlapShadow * lift * exp(-dist / soft);
}

// 预乘 alpha 的 "over" 合成。
vec4 over(vec4 dst, vec3 rgb, float a) {
    return vec4(rgb * a, a) + dst * (1.0 - a);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    vec2 u = uDir;
    vec2 t = vec2(-u.y, u.x);
    float r = max(uRadius, 0.0);
    float d = dot(p - uAxis, u);
    bool flatSide = d <= 0.0;
    bool isHinged = uHinged > 0.5;
    bool spineOnRight = uSpineX > uRect.x + uRect.z * 0.5;
    // 卷筒抬起系数：半径收拢到 0 时阴影与外沿高光平滑淡出，避免临近书脊落地瞬间突灭。
    float rollLift = smoothstep(0.0, 8.0, r);

    // ---- 1. 平铺在原位的正面（d <= 0），其余位置是露出来的下层 ----
    vec4 color;
    float flatCov = 0.0;
    if (flatSide) {
        if (isHinged) {
            bool pastSpine = spineOnRight ? (p.x > uSpineX) : (p.x < uSpineX);
            flatCov = pastSpine ? 0.0 : hingedCoverage(p, spineOnRight);
        } else {
            flatCov = coverage(p);
        }
    }
    float flatShadow = flatSide ? flapShadowAt(p, u, d, r, true) : 0.0;
    vec3 flatRgb = sheetAt(p) * (1.0 - flatShadow);
    color = vec4(flatRgb * flatCov, flatCov);
    // 下层（下一页 / 页面外的背景）只叠一层半透明黑；同时合成翻页背面与卷筒的连续软阴影，
    // 确保纸页外露区域跨 d = 0 无接缝、无阶梯带纹。
    if (flatCov < 0.999) {
        float underShadow = flapShadowAt(p, u, d, r, false);
        if (rollLift > 0.001) {
            underShadow = max(underShadow, rollShadowAt(p, u, t, d, r, rollLift));
        }
        color += vec4(0.0, 0.0, 0.0, underShadow * (1.0 - flatCov));
    }

    // ---- 2./3. 圆柱：同一个 d 对应正面（θ < π/2）和背面（θ > π/2）两层 ----
    if (r > 0.01 && !flatSide && d <= r + 0.5) {
        float base = asin(clamp(d / r, 0.0, 1.0));
        // 圆柱轮廓处的抗锯齿：d → r 时收成一条线。
        float rim = clamp((r - d) + 0.5, 0.0, 1.0);

        float thetaF = base;
        vec2 qF = p + u * (r * thetaF - d);
        vec2 nF = vec2(-sin(thetaF), cos(thetaF));
        // 正面越往上卷离那片纸越近、受光越少：影子从轴线处连续延续过来。
        vec3 rgbF = sheetAt(qF) * relShade(nF) *
                    (1.0 - flapShadowAt(p, u, d, r, true) * cos(thetaF));
        float covF = isHinged ? hingedCoverage(qF, spineOnRight) : coverage(qF);
        color = over(color, rgbF, covF * rim);

        float thetaB = kPi - base;
        vec2 qB = p + u * (r * thetaB - d);
        vec2 nB = vec2(sin(thetaB), -cos(thetaB));
        // 卷筒外沿的一道亮边（θ ≈ 110°），到 θ = π 及半径收拢为 0 时均衰减为 0。
        float sheen = 0.16 * rollLift * exp(-pow((thetaB - 1.92) / 0.38, 2.0));
        vec3 rgbB = backAt(qB, spineOnRight) * relShade(nB) + vec3(sheen);
        float covB = isHinged ? hingedCoverage(qB, spineOnRight) : coverage(qB);
        color = over(color, rgbB, covB * rim);
    }

    // ---- 4. 翻过去平压在上面的背面（d <= 0，最高的一层）----
    // 双页落地那一帧 R = 0、纸整张平压在另一半上，这一层必须照画（即使纸背还在加载）；
    // 单页 R = 0 只出现在起手（还没卷），跳过以免角上留半像素的边。
    if (flatSide && (r > 0.01 || isHinged)) {
        vec2 qFlip = p + u * (kPi * r - 2.0 * d);
        float covFlip = isHinged
            ? hingedCoverage(qFlip, spineOnRight)
            : coverage(qFlip);
        color = over(color, backAt(qFlip, spineOnRight), covFlip);
    }

    fragColor = color;
}
