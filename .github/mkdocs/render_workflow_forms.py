#!/usr/bin/env python3
"""Render the GitHub "Run workflow" form of every dispatchable workflow as SVG.

The docs show these images instead of hand-made screenshots, so they always
match the workflow inputs (order, type, required, default, options).

    python .github/mkdocs/render_workflow_forms.py          # (re)write the SVGs
    python .github/mkdocs/render_workflow_forms.py --check  # CI: fail if stale

Output: docs/_images/workflows/<workflow-file-stem>.svg
"""
import argparse
import sys
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

import yaml

REPO = Path(__file__).resolve().parents[2]
WORKFLOWS = REPO / ".github" / "workflows"
OUT_DIR = REPO / "docs" / "_images" / "workflows"
GENERATOR = ".github/mkdocs/render_workflow_forms.py"

WIDTH = 460
PAD = 16                 # panel padding
BADGE_COL = 30           # left column for the numbered badges
FIELD_X = PAD + BADGE_COL
FIELD_W = WIDTH - FIELD_X - PAD
LABEL_CHARS = 64         # wrap width for 12px labels in FIELD_W
LINE_H = 16
CONTROL_H = 30
GAP = 14

FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
C_BORDER = "#d0d7de"
C_TEXT = "#1f2328"
C_MUTED = "#59636e"
C_BG = "#ffffff"
C_FIELD_BG = "#f6f8fa"
C_REQUIRED = "#d1242f"
C_BADGE = "#0969da"
C_BUTTON = "#1f883d"


def dispatch_inputs(path):
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    on = data.get(True, data.get("on"))  # PyYAML reads the key `on` as True
    if not isinstance(on, dict) or "workflow_dispatch" not in on:
        return None, None
    dispatch = on.get("workflow_dispatch") or {}
    inputs = (dispatch.get("inputs") or {}) if isinstance(dispatch, dict) else {}
    return data.get("name") or path.stem, inputs


def text(x, y, s, size=12, weight="normal", fill=C_TEXT, anchor="start", suffix=""):
    return (f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}">{escape(str(s))}{suffix}</text>')


REQUIRED_MARK = f'<tspan fill="{C_REQUIRED}" font-weight="600"> *</tspan>'


def key_label(x, y, key):
    return text(x, y, key, size=10, fill=C_MUTED, anchor="end")


def render(workflow_file, name, inputs):
    parts = []
    y = PAD

    # Title + branch selector
    parts.append(text(PAD, y + 14, "Run workflow", size=14, weight="600"))
    y += 30
    parts.append(text(PAD, y + 12, "Use workflow from", size=12, weight="600"))
    y += 20
    parts.append(f'<rect x="{PAD}" y="{y}" width="190" height="{CONTROL_H}" rx="6" '
                 f'fill="{C_FIELD_BG}" stroke="{C_BORDER}"/>')
    parts.append(text(PAD + 10, y + 19, "Branch: <your branch> ▾", size=12))
    y += CONTROL_H + GAP + 4

    for i, (key, spec) in enumerate(inputs.items(), start=1):
        spec = spec or {}
        kind = spec.get("type", "string")
        required = bool(spec.get("required", False))
        default = spec.get("default")
        label = str(spec.get("description") or key).strip()

        # numbered badge, aligned with the first label line
        parts.append(f'<circle cx="{PAD + 11}" cy="{y + 8}" r="10" fill="{C_BADGE}"/>')
        parts.append(text(PAD + 11, y + 12, i, size=11, weight="600", fill="#ffffff", anchor="middle"))

        if kind == "boolean":
            checked = default is True or str(default).lower() == "true"
            lines = textwrap.wrap(label, LABEL_CHARS - 4) or [key]
            parts.append(f'<rect x="{FIELD_X}" y="{y}" width="14" height="14" rx="3" '
                         f'fill="{C_BADGE if checked else C_BG}" stroke="{C_MUTED if not checked else C_BADGE}"/>')
            if checked:
                parts.append(f'<path d="M{FIELD_X + 3} {y + 7} l3 3 l5 -6" stroke="#ffffff" '
                             f'stroke-width="2" fill="none"/>')
            for j, line in enumerate(lines):
                parts.append(text(FIELD_X + 22, y + 12 + j * LINE_H, line))
            parts.append(text(FIELD_X + 22, y + 12 + len(lines) * LINE_H - 2, key, size=10, fill=C_MUTED))
            y += (len(lines) + 1) * LINE_H - 2 + GAP
            continue

        lines = textwrap.wrap(label, LABEL_CHARS) or [key]
        for j, line in enumerate(lines):
            last = j == len(lines) - 1
            parts.append(text(FIELD_X, y + 12 + j * LINE_H, line,
                              suffix=REQUIRED_MARK if (required and last) else ""))
        y += len(lines) * LINE_H + 4

        parts.append(f'<rect x="{FIELD_X}" y="{y}" width="{FIELD_W}" height="{CONTROL_H}" rx="6" '
                     f'fill="{C_FIELD_BG if kind == "choice" else C_BG}" stroke="{C_BORDER}"/>')
        if kind == "choice":
            options = [str(o) for o in (spec.get("options") or [])]
            shown = str(default) if default is not None else (options[0] if options else "")
            parts.append(text(FIELD_X + 10, y + 19, shown))
            parts.append(text(FIELD_X + FIELD_W - 10, y + 19, "▾", anchor="end"))
            parts.append(key_label(FIELD_X + FIELD_W - 24, y + 19, key))
            more = len(options) - 1 if shown in options else len(options)
            if more > 0:
                hint = " | ".join(o for o in options if o != shown)
                hint = (hint[:52] + "…") if len(hint) > 53 else hint
                parts.append(text(FIELD_X, y + CONTROL_H + 13, f"other options: {hint}", size=10, fill=C_MUTED))
                y += 14
        else:
            if default not in (None, ""):
                parts.append(text(FIELD_X + 10, y + 19, default))
            parts.append(key_label(FIELD_X + FIELD_W - 10, y + 19, key))
        y += CONTROL_H + GAP

    # Run button
    y += 2
    parts.append(f'<rect x="{PAD}" y="{y}" width="120" height="{CONTROL_H}" rx="6" fill="{C_BUTTON}"/>')
    parts.append(text(PAD + 60, y + 19, "Run workflow", weight="600", fill="#ffffff", anchor="middle"))
    y += CONTROL_H + PAD
    panel_h = y

    # Caption below the panel
    caption = f"Generated from .github/workflows/{workflow_file}"
    height = panel_h + 26

    head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" '
            f'viewBox="0 0 {WIDTH} {height}" font-family="{escape(FONT)}" role="img" '
            f'aria-label="{escape(name)} — Run workflow form">')
    frame = (f'<rect x="0.5" y="0.5" width="{WIDTH - 1}" height="{panel_h - 1}" rx="8" '
             f'fill="{C_BG}" stroke="{C_BORDER}"/>')
    title = f"<title>{escape(name)} — Run workflow form</title>"
    foot = text(WIDTH / 2, panel_h + 17, caption, size=10, fill=C_MUTED, anchor="middle")
    return "\n".join([head, title, frame, *parts, foot, "</svg>"]) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="exit 1 if any SVG is missing or out of date")
    args = ap.parse_args()

    expected = {}
    for path in sorted(WORKFLOWS.glob("*.y*ml")):
        name, inputs = dispatch_inputs(path)
        if name is None or not inputs:
            continue
        expected[OUT_DIR / f"{path.stem}.svg"] = render(path.name, name, inputs)

    stale = [p for p, svg in expected.items()
             if not p.exists() or p.read_text(encoding="utf-8") != svg]
    orphans = [p for p in OUT_DIR.glob("*.svg") if p not in expected] if OUT_DIR.exists() else []

    if args.check:
        if stale or orphans:
            print("Workflow form images are out of date:")
            for p in stale + orphans:
                print(f"  - {p.relative_to(REPO)}")
            print(f"Run: python {GENERATOR}  (and commit docs/_images/workflows/)")
            return 1
        print(f"OK: {len(expected)} workflow form images match the workflows.")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for p, svg in expected.items():
        p.write_text(svg, encoding="utf-8")
    for p in orphans:
        p.unlink()
    print(f"Wrote {len(expected)} images to {OUT_DIR.relative_to(REPO)} "
          f"({len(stale)} changed, {len(orphans)} removed).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
