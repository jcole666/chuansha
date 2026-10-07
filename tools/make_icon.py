"""生成「穿啥」应用图标（矢量风格衣架 + 品牌紫渐变）。

用代码绘制而非 AI 生成：结果确定、可复现、不消耗积分。
用法：python tools/make_icon.py
"""
import os
import re
import glob
from PIL import Image, ImageDraw

SIZE = 1024
BRAND_TOP = (124, 116, 255)   # #7C74FF
BRAND_BOTTOM = (91, 82, 232)  # #5B52E8
WHITE = (255, 255, 255, 255)


def rounded_gradient(size=SIZE, radius=228):
    """圆角方形 + 竖直渐变背景"""
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        grad.putpixel((0, y), tuple(
            round(BRAND_TOP[i] + (BRAND_BOTTOM[i] - BRAND_TOP[i]) * t)
            for i in range(3)
        ))
    grad = grad.resize((size, size))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out


def draw_hanger(img):
    """白色衣架：挂钩 + 三角架身"""
    d = ImageDraw.Draw(img)
    s = SIZE
    cx = s // 2
    lw = int(s * 0.062)          # 线宽

    # 挂钩：上方开口的圆环
    hook_r = int(s * 0.072)
    hook_cy = int(s * 0.295)
    d.arc(
        [cx - hook_r, hook_cy - hook_r, cx + hook_r, hook_cy + hook_r],
        start=160, end=20, fill=WHITE, width=lw,
    )

    # 挂钩到架身的短颈
    neck_top = hook_cy + hook_r - int(lw * 0.4)
    neck_bottom = int(s * 0.455)
    d.line([(cx, neck_top), (cx, neck_bottom)], fill=WHITE, width=lw)

    # 三角架身
    apex = (cx, neck_bottom)
    left = (int(s * 0.225), int(s * 0.705))
    right = (int(s * 0.775), int(s * 0.705))
    d.line([left, apex], fill=WHITE, width=lw)
    d.line([apex, right], fill=WHITE, width=lw)
    d.line([left, right], fill=WHITE, width=lw)

    # 圆角端点，避免尖角
    r = lw // 2
    for p in (left, right, apex):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=WHITE)
    return img


def build_master():
    img = rounded_gradient()
    draw_hanger(img)
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    master = build_master()

    written = []

    # Android
    android = {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }
    for dpi, px in android.items():
        p = os.path.join(root, "android/app/src/main/res",
                         f"mipmap-{dpi}", "ic_launcher.png")
        if os.path.isdir(os.path.dirname(p)):
            master.resize((px, px), Image.LANCZOS).save(p, "PNG")
            written.append(p)

    # iOS
    ios_dir = os.path.join(root, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    if os.path.isdir(ios_dir):
        for p in glob.glob(os.path.join(ios_dir, "Icon-App-*.png")):
            m = re.search(r"Icon-App-([\d.]+)x([\d.]+)@(\d+)x", os.path.basename(p))
            if not m:
                continue
            base, scale = float(m.group(1)), int(m.group(3))
            px = int(round(base * scale))
            img = master.resize((px, px), Image.LANCZOS)
            # iOS 图标不能带 alpha
            img.convert("RGB").save(p, "PNG")
            written.append(p)

    # 源图留一份，方便以后改
    src = os.path.join(root, "assets/app_icon.png")
    os.makedirs(os.path.dirname(src), exist_ok=True)
    master.save(src, "PNG")
    written.append(src)

    print(f"生成 {len(written)} 个文件：")
    for w in written:
        print("  " + os.path.relpath(w, root).replace("\\", "/"))


if __name__ == "__main__":
    main()
