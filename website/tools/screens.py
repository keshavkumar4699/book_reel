#!/usr/bin/env python3
"""Turn the app's screenshots into the website's images and hero video.

The screenshots come from app/test/marketing/screenshots_test.dart (see
website/README.md). For each screen this script:

- draws the emoji the test renderer can't (it never falls back to system
  fonts the way a phone does), from the positions the test recorded;
- writes WebP at 2x (786 px wide) and 1x (393 px wide).

The Night desk frames become a seamless six-second WebM loop for the hero
(the last second cross-faded into the first), with a WebP poster.

Needs Pillow, ffmpeg with libvpx (or Playwright's ffmpeg) and, for emoji,
Noto Color Emoji.

    python3 tools/screens.py /path/to/screenshots
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SITE = Path(__file__).resolve().parent.parent / "public" / "assets"
WIDTHS = (786, 393)
EMOJI_FONT = os.environ.get("EMOJI_FONT", "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf")


def ffmpeg() -> str:
    found = os.environ.get("FFMPEG") or shutil.which("ffmpeg")
    if found:
        return found
    for p in sorted(Path("/opt/pw-browsers").glob("ffmpeg-*/ffmpeg-linux"), reverse=True):
        return str(p)
    sys.exit("ffmpeg not found: set FFMPEG")


def draw_emoji(image: Image.Image, marks: list[dict]) -> None:
    """Covers each placeholder box and draws the emoji in the room it had."""
    font = ImageFont.truetype(EMOJI_FONT, 109)  # the one size the colour font has
    draw = ImageDraw.Draw(image)
    for m in marks:
        x, y, w, h = m["x"], m["y"], m["w"], m["h"]
        if y + h < 0 or y > image.height:
            continue  # scrolled off the screen
        # The background just before the box (or after it, at a line's start).
        sx = int(x - 3) if x > 6 else int(x + w + 3)
        bg = image.getpixel((max(0, min(image.width - 1, sx)), int(y + h / 2)))
        draw.rectangle([x - 1, y + h * 0.12, x + w + 1, y + h * 0.88], fill=bg)
        glyph = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text((0, 0), chr(m["codepoint"]), font=font, embedded_color=True)
        if glyph.getbbox() is None:
            continue  # not an emoji the font has
        glyph = glyph.crop(glyph.getbbox())
        size = int(min(h * 0.62, m["room"] - h * 0.08))
        glyph = glyph.resize((size, round(glyph.height * size / glyph.width)), Image.LANCZOS)
        image.paste(glyph, (round(x), round(y + (h - glyph.height) / 2)), glyph)


def write_sizes(image: Image.Image, folder: Path, name: str) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for width in WIDTHS:
        height = round(image.height * width / image.width)
        image.resize((width, height), Image.LANCZOS).save(folder / f"{name}-{width}.webp", "WEBP", quality=82, method=6)


def screens(src: Path) -> None:
    for png in sorted(src.glob("*.png")):
        name = png.stem
        image = Image.open(png).convert("RGB")
        marks = src / f"{name}.emoji.json"
        if marks.exists():
            draw_emoji(image, json.loads(marks.read_text()))
        folder = SITE / "img" / ("scenes" if name.startswith("scene-") else "app")
        write_sizes(image, folder, name.removeprefix("scene-"))
        print("image", name)


def loop(src: Path, name: str, seconds: int = 6, fade: int = 1, fps: int = 24) -> None:
    frames = sorted((src / f"frames-{name}").glob("*.png"))
    total, blend = seconds * fps, fade * fps
    if len(frames) < total + blend:
        sys.exit(f"{name}: {len(frames)} frames, need {total + blend}")
    out = SITE / "video" / f"{name}.webm"
    out.parent.mkdir(parents=True, exist_ok=True)
    encoder = subprocess.Popen(
        [ffmpeg(), "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", str(fps), "-c:v", "png", "-i", "-",
         "-c:v", "libvpx", "-b:v", "1400k", "-crf", "8", "-qmin", "4", "-qmax", "40", "-deadline", "good", "-cpu-used", "0",
         "-auto-alt-ref", "0", "-pix_fmt", "yuv420p", "-an", str(out)],
        stdin=subprocess.PIPE,
    )
    import io

    for k in range(total):
        frame = Image.open(frames[k]).convert("RGB")
        if k < blend:
            # The second after the loop, faded into the loop's own first
            # second: the last frame runs on into the first without a cut.
            after = Image.open(frames[total + k]).convert("RGB")
            frame = Image.blend(after, frame, k / blend)
        if k == 0:
            frame.save(SITE / "img" / "scenes" / f"{name}-poster.webp", "WEBP", quality=80, method=6)
        buffer = io.BytesIO()
        frame.save(buffer, "PNG", compress_level=1)
        encoder.stdin.write(buffer.getvalue())
    encoder.stdin.close()
    if encoder.wait() != 0:
        sys.exit("ffmpeg failed")
    print("video", out.name, f"{out.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    screens(source)
    loop(source, "studyNight")
