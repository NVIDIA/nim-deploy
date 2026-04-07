#!/usr/bin/env python3
"""Add graphical highlights to AIPerf screenshot PNGs (TTFT row + avg column).

Run against unannotated captures only (e.g. ``git checkout -- images/aiperf-kv-router-*.png``),
or overlays will stack.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


# (y_top, y_bottom, avg_col_x0, avg_col_x1) — tuned for 1024px-wide AIPerf captures.
# Both crops share the same table grid; the "enabled" shot only has extra title rows (shift y).
# avg column sits at the right end of the first green span on the TTFT number line (~318–391).
SPECS: dict[str, tuple[int, int, int, int]] = {
    "disabled": (80, 98, 348, 391),
    "enabled": (90, 106, 348, 391),
}


def try_load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        p = Path(path)
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def highlight_image(src: Path, dest: Path, key: str) -> None:
    y0, y1, ax0, ax1 = SPECS[key]
    base = Image.open(src).convert("RGBA")
    w, h = base.size
    pad = 3
    y0 = max(0, y0 - pad)
    y1 = min(h, y1 + pad)
    ax0 = max(8, ax0 - 6)
    ax1 = min(w - 8, ax1 + 6)

    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    row_fill = (255, 200, 0, 72)
    row_outline = (118, 185, 0, 255)
    avg_fill = (0, 200, 255, 55)
    avg_outline = (255, 255, 255, 230)

    # Full-width band for "Time to First Token" row
    draw.rectangle((6, y0, w - 7, y1 - 1), fill=row_fill, outline=row_outline, width=2)

    # Brighter box on the **avg** column (headline number)
    draw.rectangle((ax0, y0 + 1, ax1, y1 - 2), fill=avg_fill, outline=avg_outline, width=2)

    out = Image.alpha_composite(base, overlay)

    # Small banner above the avg column
    label = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(label)
    font = try_load_font(13)
    text = "avg TTFT"
    bbox = ldraw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    bx0 = max(8, ax0 - 2)
    bx1 = min(w - 8, bx0 + tw + 14)
    by0 = max(6, y0 - th - 14)
    by1 = by0 + th + 8
    ldraw.rounded_rectangle((bx0, by0, bx1, by1), radius=4, fill=(20, 24, 28, 235), outline=row_outline, width=1)
    ldraw.text((bx0 + 7, by0 + 4), text, font=font, fill=(255, 255, 255, 255))

    out = Image.alpha_composite(out, label)
    out.convert("RGB").save(dest, format="PNG", optimize=True)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    images = root / "images"
    highlight_image(
        images / "aiperf-kv-router-disabled.png",
        images / "aiperf-kv-router-disabled.png",
        "disabled",
    )
    highlight_image(
        images / "aiperf-kv-router-enabled.png",
        images / "aiperf-kv-router-enabled.png",
        "enabled",
    )
    print("Wrote highlighted PNGs to", images)


if __name__ == "__main__":
    main()
