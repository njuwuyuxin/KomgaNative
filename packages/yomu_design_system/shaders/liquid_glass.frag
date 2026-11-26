#version 460 core
// 液态玻璃（iOS 26 Liquid Glass）背景着色器。
//
// 用法：BackdropFilter(ImageFilter.shader(本着色器))，单层、不组合其他滤镜，
// 外面再按玻璃外形裁剪。坐标约定（模拟器 Impeller/GLES 实测）：
// - FlutterFragCoord() 是屏幕物理像素坐标（与所在图层无关）；
// - 输入纹理按 FlutterFragCoord() / u_size 采样即对齐屏幕像素，可越出裁剪框。
//
// 一块玻璃从下往上：背后（已轻模糊）→ 外缘斜面折射（向内采样 + RGB 色散）
// → 提饱和 / 提亮 / 底色 → 斜面内的柔光 → 沿轮廓的方向性镜面高光。
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;      // 引擎写入：输入纹理尺寸
uniform vec4 u_rect;      // 玻璃在屏幕上的物理像素矩形：left, top, width, height
uniform float u_radius;   // 圆角半径（物理像素）
uniform float u_bezel;    // 斜面宽度（物理像素）：折射只发生在这一圈
uniform float u_refract;  // 外缘处的最大折射位移（物理像素）
uniform float u_chroma;   // 色散强度（相对位移的比例）
uniform float u_saturation;
uniform float u_brightness;
uniform vec4 u_tint;      // 底色（rgb + 混合比例）
uniform float u_specular; // 镜面高光强度
uniform float u_rimWidth; // 镜面高光线宽（物理像素）
uniform float u_glow;     // 斜面柔光强度
uniform float u_blur;     // 着色器内轻模糊半径（物理像素）
uniform float u_opacity;  // 玻璃可见度（0..1）：在着色器内与原背景混合，避免外层 OpacityLayer 隔断背景采样
uniform sampler2D u_texture;

out vec4 frag_color;

float sdRoundBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 sampleAt(vec2 p) {
  return texture(u_texture, p / u_size).rgb;
}

// 轻模糊：以 p 为圆心、半径 u_blur 的 12 点黄金角圆盘采样 + 中心点。
// 不用 ImageFilter.blur 组合：真机上嵌套/组合的背景滤镜会改变输入纹理的坐标系，
// 只有"单层着色器"的采样坐标是实测对齐屏幕的。
vec3 sampleBlur(vec2 p) {
  if (u_blur < 0.5) return sampleAt(p);
  vec3 acc = sampleAt(p);
  float wsum = 1.0;
  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    float rr = u_blur * sqrt((fi + 0.5) / 12.0);
    float a = fi * 2.39996323;
    float w = 1.0 - 0.5 * (rr / u_blur);
    acc += sampleAt(p + vec2(cos(a), sin(a)) * rr) * w;
    wsum += w;
  }
  return acc / wsum;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  if (u_opacity <= 0.001) {
    frag_color = vec4(sampleAt(p), 1.0);
  } else {
    vec2 halfSize = u_rect.zw * 0.5;
    vec2 center = u_rect.xy + halfSize;
    vec2 local = p - center;
    float r = min(u_radius, min(halfSize.x, halfSize.y));

    float d = sdRoundBox(local, halfSize, r);
    // 外法线：SDF 梯度。
    vec2 e = vec2(1.0, 0.0);
    vec2 grad = vec2(
      sdRoundBox(local + e.xy, halfSize, r) - sdRoundBox(local - e.xy, halfSize, r),
      sdRoundBox(local + e.yx, halfSize, r) - sdRoundBox(local - e.yx, halfSize, r)
    );
    vec2 n = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0, -1.0);

    float depth = max(-d, 0.0);                 // 离外缘多深
    float x = clamp(depth / u_bezel, 0.0, 1.0); // 0 = 外缘，1 = 斜面内沿
    float edge = 1.0 - x;

    // 斜面是凸的：越靠外缘越陡，光线越往里折——向内采样，外缘位移最大。
    // 曲线取 squircle 斜面的近似（外缘陡、向内很快变平）。
    float disp = u_refract * u_opacity * edge * edge * (3.0 - 2.0 * edge) * edge;
    vec2 dir = -n;
    vec3 col;
    if (u_chroma > 0.0 && disp > 0.25) {
      col.r = sampleBlur(p + dir * disp * (1.0 + u_chroma)).r;
      col.g = sampleBlur(p + dir * disp).g;
      col.b = sampleBlur(p + dir * disp * (1.0 - u_chroma)).b;
    } else {
      col = sampleBlur(p + dir * disp);
    }

    // 背后颜色"透"出来：提饱和、提亮，再压一层底色。
    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(luma), col, u_saturation);
    col = clamp(col + u_brightness, 0.0, 1.0);
    col = mix(col, u_tint.rgb, u_tint.a);

    // 光从左上来（屏幕 y 向下）。
    vec2 light = normalize(vec2(-0.55, -1.0));
    float facing = dot(n, light);
    float lit = pow(max(facing, 0.0), 1.5);           // 迎光面
    float reflected = pow(max(-facing, 0.0), 2.0);    // 背光面的内反射

    // 斜面柔光：厚玻璃把光聚在边上。
    float glow = u_glow * pow(edge, 3.0) * (0.35 + 0.65 * lit + 0.4 * reflected);
    col = mix(col, vec3(1.0), clamp(glow, 0.0, 1.0));

    // 镜面高光：贴着轮廓的一条细亮线，亮度随方向变。
    float rim = 1.0 - smoothstep(0.0, u_rimWidth, depth);
    float spec = u_specular * rim * (0.18 + 0.82 * lit + 0.55 * reflected);
    col = mix(col, vec3(1.0), clamp(spec, 0.0, 1.0));

    if (u_opacity < 0.999) {
      col = mix(sampleAt(p), col, u_opacity);
    }
    frag_color = vec4(col, 1.0);
  }
}
