#!/usr/bin/env python3
"""Convert PNG and JPG/JPEG assets to WebP for DoctorNect web performance.

Scans specified asset directories (non-recursive), produces optimized .webp versions
alongside existing raster files without altering or deleting the originals,
and automatically generates frontend/lib/core/utils/asset_webp_manifest.dart.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
FRONTEND_DIR = SCRIPT_DIR.parent

FOLDERS = [
    "assets/icons/doctor",
    "assets/icons/common",
    "assets/images/services",
    "assets/images/specialties",
    "assets/images",
]

MANIFEST_FILE = FRONTEND_DIR / "lib" / "core" / "utils" / "asset_webp_manifest.dart"


def format_bytes(bytes_count: int) -> str:
    """Format bytes into a readable string."""
    if bytes_count < 1024:
        return f"{bytes_count} B"
    elif bytes_count < 1024 * 1024:
        return f"{bytes_count / 1024:.1f} KB"
    else:
        return f"{bytes_count / (1024 * 1024):.2f} MB"


def convert_png(src: Path, dst: Path) -> tuple[int, int, bool]:
    """Convert PNG to WebP with lossless=True, quality=100, method=6. Preserves alpha."""
    src_size = src.stat().st_size
    with Image.open(src) as img:
        # Save as lossless WebP to preserve exact pixel quality & alpha transparency
        img.save(dst, format="WEBP", lossless=True, quality=100, method=6)
    dst_size = dst.stat().st_size
    return src_size, dst_size, True


def convert_jpg(src: Path, dst: Path) -> tuple[int, int, bool]:
    """Convert JPG/JPEG to WebP with quality=95, method=6. Converts to RGB."""
    src_size = src.stat().st_size
    with Image.open(src) as img:
        rgb_img = img.convert("RGB") if img.mode != "RGB" else img
        rgb_img.save(dst, format="WEBP", quality=95, method=6)
    dst_size = dst.stat().st_size
    return src_size, dst_size, True


def main() -> int:
    print("=" * 70)
    print(" DoctorNect Asset WebP Optimization Pipeline")
    print("=" * 70)

    total_orig_bytes = 0
    total_webp_bytes = 0
    converted_count = 0
    skipped_count = 0

    all_webp_asset_paths: list[str] = []

    for rel_folder in FOLDERS:
        folder_path = FRONTEND_DIR / rel_folder
        if not folder_path.exists():
            print(f"[WARN] Folder not found: {rel_folder}")
            continue

        print(f"\nScanning: {rel_folder}")

        # List files directly in folder (non-recursive)
        for item in sorted(os.listdir(folder_path)):
            src_path = folder_path / item
            if not src_path.is_file():
                continue

            lower_name = item.lower()
            ext = src_path.suffix.lower()

            if ext in (".png", ".jpg", ".jpeg"):
                webp_name = f"{src_path.stem}.webp"
                webp_path = folder_path / webp_name
                asset_rel_path = f"{rel_folder}/{webp_name}".replace("\\", "/")

                # Check if up-to-date
                if webp_path.exists() and webp_path.stat().st_mtime >= src_path.stat().st_mtime:
                    src_size = src_path.stat().st_size
                    webp_size = webp_path.stat().st_size
                    total_orig_bytes += src_size
                    total_webp_bytes += webp_size
                    skipped_count += 1
                    diff = src_size - webp_size
                    pct = (diff / src_size * 100) if src_size > 0 else 0
                    print(
                        f"  [UP-TO-DATE] {item} -> {webp_name} "
                        f"({format_bytes(src_size)} -> {format_bytes(webp_size)}, -{pct:.1f}%)"
                    )
                else:
                    try:
                        if ext == ".png":
                            src_size, webp_size, _ = convert_png(src_path, webp_path)
                        else:
                            src_size, webp_size, _ = convert_jpg(src_path, webp_path)

                        total_orig_bytes += src_size
                        total_webp_bytes += webp_size
                        converted_count += 1
                        diff = src_size - webp_size
                        pct = (diff / src_size * 100) if src_size > 0 else 0
                        print(
                            f"  [CONVERTED]  {item} -> {webp_name} "
                            f"({format_bytes(src_size)} -> {format_bytes(webp_size)}, -{pct:.1f}%)"
                        )
                    except Exception as err:
                        print(f"  [ERROR] Failed to convert {item}: {err}", file=sys.stderr)

            # Record any existing or converted webp in this folder
            if ext == ".webp" or lower_name.endswith(".webp"):
                pass  # We collect all .webp files next

        # Collect all .webp files in this scanned directory for the manifest
        for item in sorted(os.listdir(folder_path)):
            p = folder_path / item
            if p.is_file() and p.suffix.lower() == ".webp":
                rel = f"{rel_folder}/{item}".replace("\\", "/")
                if rel not in all_webp_asset_paths:
                    all_webp_asset_paths.append(rel)

    all_webp_asset_paths.sort()

    # Generate asset_webp_manifest.dart
    MANIFEST_FILE.parent.mkdir(parents=True, exist_ok=True)
    manifest_lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "// Generated by frontend/scripts/convert_assets_to_webp.py.",
        "",
        "/// Set of all available WebP asset paths for web runtime resolution.",
        "const Set<String> kWebpAssets = {",
    ]
    for p in all_webp_asset_paths:
        manifest_lines.append(f"  '{p}',")
    manifest_lines.append("};")
    manifest_lines.append("")

    with open(MANIFEST_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(manifest_lines))

    print("\n" + "=" * 70)
    print(" SUMMARY")
    print("=" * 70)
    print(f" Converted new/updated: {converted_count}")
    print(f" Already up-to-date:    {skipped_count}")
    print(f" Total WebP in set:     {len(all_webp_asset_paths)}")
    print(f" Manifest written to:   {MANIFEST_FILE.relative_to(FRONTEND_DIR)}")
    if total_orig_bytes > 0:
        total_diff = total_orig_bytes - total_webp_bytes
        total_pct = (total_diff / total_orig_bytes * 100) if total_orig_bytes > 0 else 0
        print(f" Original size:         {format_bytes(total_orig_bytes)}")
        print(f" WebP size:             {format_bytes(total_webp_bytes)}")
        print(f" Total savings:         {format_bytes(total_diff)} ({total_pct:.1f}% reduction)")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
