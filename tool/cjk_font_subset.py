"""重新生成黄金图用的中文字体子集（ADR 0004）。

用法（需要 fonttools：pip install fonttools）：

    python tool/cjk_font_subset.py [源字体路径]

源字体默认取 Windows 自带的 Noto Sans SC 可变字体；没有的话从
https://github.com/notofonts/noto-cjk 下载 NotoSansSC-VF.ttf 再传路径。

字符集 = app_zh.arb 全部文案 + 测试源码里出现的汉字 + ASCII + 常用中文标点。
新增中文文案后重跑一次，再更新中文黄金图。
"""

import glob
import json
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = sys.argv[1] if len(sys.argv) > 1 else r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
OUT = os.path.join(ROOT, "apps", "app", "test", "fonts", "NotoSansSC-Regular-subset.ttf")


def is_cjk(ch: str) -> bool:
    return "\u3000" <= ch <= "\u9fff" or "\uff00" <= ch <= "\uffef"


def collect() -> str:
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars.update("，。、；：？！“”‘’（）《》【】…—·「」")
    with open(os.path.join(ROOT, "apps", "app", "lib", "l10n", "app_zh.arb"), encoding="utf-8") as f:
        for key, value in json.load(f).items():
            if not key.startswith("@") and isinstance(value, str):
                chars.update(value)
    for path in glob.glob(os.path.join(ROOT, "apps", "app", "test", "**", "*.dart"), recursive=True):
        with open(path, encoding="utf-8") as f:
            chars.update(c for c in f.read() if is_cjk(c))
    return "".join(sorted(chars))


def main() -> None:
    text = collect()
    font = TTFont(SOURCE)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": 400})
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    font.save(OUT)
    print(f"{OUT}: {len(text)} chars, {os.path.getsize(OUT)} bytes")


if __name__ == "__main__":
    main()
