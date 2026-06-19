#!/usr/bin/env python3
"""fix-svg-foreignobject.py — Convert foreignObject to native SVG <text>.

Mermaid.js renders all text labels using <foreignObject> with embedded HTML,
which Microsoft Word's SVG renderer cannot display. This script replaces
each <foreignObject> with equivalent native SVG <text>/<tspan> elements.

Usage:
    python3 scripts/fix-svg-foreignobject.py <svg> [<svg> ...]
"""

import re
import sys


# Mermaid theme defaults (from %%{init}%% config)
FONT_FAMILY = '"trebuchet ms", verdana, arial, sans-serif'
FONT_SIZE = 24
FILL_DEFAULT = "#333"
FILL_CLUSTER = "#333"
EDGE_BG_FILL = "#f4fce8"  # hsl(84, 77%, 95%)


def extract_text_lines(html):
    """Extract text lines from HTML content, splitting on <br> tags."""
    text = re.sub(r"<br\s*/?>", "\n", html)
    text = re.sub(r"<[^>]+>", "", text)
    text = (text
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", '"')
            .replace("&#39;", "'"))
    return [line.strip() for line in text.split("\n") if line.strip()]


def build_text_element(cx, cy, lines, font_size, fill):
    """Build an SVG <text> element (single or multi-line with <tspan>)."""
    attrs = (
        f'text-anchor="middle" dominant-baseline="central" '
        f'font-family={FONT_FAMILY!r} font-size="{font_size}" fill="{fill}"'
    )
    if len(lines) == 1:
        return f'<text x="{cx:.1f}" y="{cy:.1f}" {attrs}>{lines[0]}</text>'

    line_height = font_size * 1.4
    total = line_height * (len(lines) - 1)
    start_y = cy - total / 2
    tspans = "".join(
        f'<tspan x="{cx:.1f}" y="{start_y + i * line_height:.1f}">{line}</tspan>'
        for i, line in enumerate(lines)
    )
    return f"<text {attrs}>{tspans}</text>"


def foreignobject_to_text(match):
    """Replace a single <foreignObject> with native SVG <text>."""
    attrs_str = match.group(1)
    html_content = match.group(2)

    w_m = re.search(r'width="([^"]+)"', attrs_str)
    h_m = re.search(r'height="([^"]+)"', attrs_str)
    if not w_m or not h_m:
        return ""

    width = float(w_m.group(1))
    height = float(h_m.group(1))

    # Skip empty foreignObjects (unlabeled edges)
    if width == 0 and height == 0:
        return ""

    lines = extract_text_lines(html_content)
    if not lines:
        return ""

    cx = width / 2
    cy = height / 2
    is_edge = "edgeLabel" in html_content
    fill = FILL_DEFAULT

    result = ""
    # Edge labels need a background rect for readability over lines
    if is_edge:
        result += (
            f'<rect x="0" y="0" width="{width}" height="{height}" '
            f'fill="{EDGE_BG_FILL}" opacity="0.85" rx="2"/>'
        )

    result += build_text_element(cx, cy, lines, FONT_SIZE, fill)
    return result


def fix_svg_foreignobject(path):
    """Process one SVG file. Returns number of replacements made."""
    with open(path, "r", encoding="utf-8") as f:
        svg = f.read()

    pattern = r"<foreignObject([^>]*)>(.*?)</foreignObject>"
    orig_count = len(re.findall(pattern, svg, flags=re.DOTALL))

    svg = re.sub(pattern, foreignobject_to_text, svg, flags=re.DOTALL)

    new_count = len(re.findall(pattern, svg, flags=re.DOTALL))
    replaced = orig_count - new_count

    if replaced:
        with open(path, "w", encoding="utf-8") as f:
            f.write(svg)

    return replaced


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <svg> [<svg> ...]", file=sys.stderr)
        sys.exit(1)

    total = 0
    for p in sys.argv[1:]:
        n = fix_svg_foreignobject(p)
        if n:
            print(f"  {p}: converted {n} foreignObject(s)")
            total += n

    if total:
        print(f"Converted {total} foreignObject(s) total")
    else:
        print("No foreignObject elements found")


if __name__ == "__main__":
    main()
