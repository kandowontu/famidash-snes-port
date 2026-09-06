#!/usr/bin/env python3
"""Rank level/map windows against a cropped, nearest-scaled gameplay image.

This is a diagnostic helper for screenshots which omit the emulator UI.  It
compares colour-boundary geometry, so palette cycling does not affect the
result and OBJ pixels can be masked out by their non-background colours.
"""
from __future__ import annotations

import argparse
import gc
import itertools
import re
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.signal import fftconvolve

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"


def lua_tilesets() -> list[int]:
    text = (OUT / "bg_level_expect.lua").read_text()
    body = re.search(r"tileset\s*=\s*\{\s*(.*?)\s*\}", text, re.S)
    if not body:
        raise RuntimeError("tileset table not found")
    return [int(v) for v in re.findall(r"\d+", body.group(1))]


def decode_tiles(blob: bytes) -> np.ndarray:
    src = np.frombuffer(blob, dtype=np.uint8).reshape(256, 16)
    tiles = np.zeros((256, 8, 8), dtype=np.uint8)
    for tile in range(256):
        for y in range(8):
            for x in range(8):
                bit = 7 - x
                tiles[tile, y, x] = (
                    ((src[tile, y * 2] >> bit) & 1)
                    | (((src[tile, y * 2 + 1] >> bit) & 1) << 1)
                )
    return tiles


def render_level(path: Path, tiles: np.ndarray) -> np.ndarray:
    words = np.frombuffer(path.read_bytes(), dtype="<u2").reshape(-1, 64)
    cols = words.shape[0]
    image = np.zeros((512, cols * 8), dtype=np.uint8)
    for col in range(cols):
        for row in range(64):
            word = int(words[col, row])
            tile = word & 0x3FF
            if tile >= 256:
                continue
            pix = tiles[tile]
            if word & 0x4000:
                pix = pix[:, ::-1]
            if word & 0x8000:
                pix = pix[::-1, :]
            # Keep the palette in the token. Boundaries are compared below,
            # not absolute values, so disco colour changes do not matter.
            token = ((word >> 10) & 7) * 16
            image[row * 8:(row + 1) * 8, col * 8:(col + 1) * 8] = token + pix
    return image


def boundaries(image: np.ndarray) -> np.ndarray:
    out = np.zeros(image.shape, dtype=np.float32)
    out[:, 1:] += image[:, 1:] != image[:, :-1]
    out[1:, :] += image[1:, :] != image[:-1, :]
    return out > 0


def mapped_accuracy(rendered: np.ndarray, labels: np.ndarray,
                    valid: np.ndarray, x: int, y: int) -> float:
    height, width = labels.shape
    window = rendered[y:y + height, x:x + width]
    if window.shape != labels.shape:
        return 0.0
    correct = 0
    total = int(valid.sum())
    for token in np.unique(window[valid]):
        here = valid & (window == token)
        counts = np.bincount(labels[here], minlength=3)
        correct += int(counts[:3].max())
    return correct / max(total, 1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=Path)
    ap.add_argument("--width", type=int, default=256)
    ap.add_argument("--height", type=int, default=175)
    ap.add_argument("--top", type=int, default=12)
    ap.add_argument("--levels", default="",
                    help="comma-separated level indices (default: all)")
    ap.add_argument("--exact", action="store_true",
                    help="search all 4 NES pixel -> 3 screenshot colour maps")
    ap.add_argument("--exclude-rgb", default="",
                    help="ignore one RGB colour, e.g. 0,90,0 for BG2 ink")
    args = ap.parse_args()

    shot = Image.open(args.image).convert("RGB").resize(
        (args.width, args.height), Image.Resampling.NEAREST)
    rgb = np.asarray(shot)
    colors, counts = np.unique(rgb.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(counts)[::-1]
    bg_colors = colors[order[:3]]
    bg_valid = np.any(np.all(rgb[:, :, None, :] == bg_colors[None, None, :, :],
                             axis=3), axis=2)
    if args.exclude_rgb:
        excluded = np.array(
            [int(v) for v in args.exclude_rgb.split(",")], dtype=np.uint8)
        if excluded.shape != (3,):
            raise ValueError("--exclude-rgb needs R,G,B")
        bg_valid &= ~np.all(rgb == excluded, axis=2)
    # Assign the three background colours stable labels, then compare only
    # boundaries whose two pixels are not OBJ blue/pink.
    labels = np.full(rgb.shape[:2], 255, dtype=np.uint8)
    for i, color in enumerate(bg_colors):
        labels[np.all(rgb == color, axis=2)] = i
    target = boundaries(labels).astype(np.float32)
    target *= bg_valid
    target[:, 1:] *= bg_valid[:, :-1]
    target[1:, :] *= bg_valid[:-1, :]
    target = target[::2, ::2]
    target_count = float(target.sum())

    tilesets = lua_tilesets()
    selected = ({int(v) for v in args.levels.split(",") if v.strip()}
                if args.levels else None)
    results: list[tuple[float, int, int, int, int]] = []
    for level, tileset in enumerate(tilesets):
        if selected is not None and level not in selected:
            continue
        path = OUT / f"level_expect_{level}.bin"
        if not path.exists():
            continue
        best = (-1.0, 0.0, 0, 0, 0)
        for phase in (0, 1):
            stem = "bgchr_alt" if phase else "bgchr"
            tiles = decode_tiles((OUT / f"{stem}{tileset}.bin").read_bytes())
            rendered = render_level(path, tiles)
            render = boundaries(rendered).astype(np.float32)[::2, ::2]
            if args.exact:
                small_labels = labels[::2, ::2]
                small_valid = bg_valid[::2, ::2]
                render_pixels = (rendered[::2, ::2] & 0x0F)
                correlations = {}
                for pixel in range(4):
                    source = (render_pixels == pixel).astype(np.float32)
                    for color in range(3):
                        template = ((small_labels == color) & small_valid)
                        correlations[pixel, color] = fftconvolve(
                            source, template[::-1, ::-1].astype(np.float32),
                            mode="valid")
                score = None
                at, value = (0, 0), -1.0
                for mapping in itertools.product(range(3), repeat=4):
                    candidate = sum(correlations[p, mapping[p]]
                                    for p in range(4))
                    candidate_at = np.unravel_index(
                        np.argmax(candidate), candidate.shape)
                    candidate_value = float(candidate[candidate_at])
                    if candidate_value > value:
                        value, at = candidate_value, candidate_at
                value /= max(float(small_valid.sum()), 1.0)
                del correlations, render_pixels
            else:
                # Cross-correlation gives the number of target boundaries which
                # exist at each candidate map position.
                hit = fftconvolve(render, target[::-1, ::-1], mode="valid")
                # Penalise additional rendered boundaries in the same window.
                area = fftconvolve(
                    render, np.ones(target.shape, dtype=np.float32), mode="valid")
                score = (2.0 * hit - area) / max(target_count, 1.0)
                at = np.unravel_index(np.argmax(score), score.shape)
                value = float(score[at])
            at_x, at_y = at[1] * 2, at[0] * 2
            accuracy = 0.0
            accurate_x, accurate_y = at_x, at_y
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    candidate = mapped_accuracy(
                        rendered, labels, bg_valid, at_x + dx, at_y + dy)
                    if candidate > accuracy:
                        accuracy = candidate
                        accurate_x, accurate_y = at_x + dx, at_y + dy
            if value > best[0]:
                best = (value, accuracy, accurate_x, accurate_y, phase)
            del tiles, rendered, render, score
            if not args.exact:
                del hit, area
            gc.collect()
        results.append((best[1], best[0], level, best[2], best[3], best[4]))

    results.sort(reverse=True)
    for accuracy, score, level, x, y, phase in results[:args.top]:
        print(f"level={level:3d} x={x:5d} y={y:3d} phase={phase} "
              f"accuracy={accuracy:.4f} edge={score:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
