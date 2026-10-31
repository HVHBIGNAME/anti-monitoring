"""Small shared SVG helpers for documentation and local inventory reports."""

from html import escape

PALETTES = {
    "dark": {"bg": "#101310", "panel": "#171c16", "line": "#30392c", "fg": "#f0f2e8", "muted": "#a1ad9b", "accent": "#d2ff5a", "soft": "#344620", "warn": "#ffc77b"},
    "light": {"bg": "#f3f2e9", "panel": "#e9ebdf", "line": "#cdd3c0", "fg": "#20271b", "muted": "#616d55", "accent": "#496817", "soft": "#dce8bd", "warn": "#91520b"},
}


def text(x, y, value, *, fill, size=20, weight=400, mono=False, anchor="start"):
    value = str(value)
    if any(ord(char) < 32 and char not in "\t\r\n" for char in value):
        raise ValueError("Text contains an invalid XML control character")
    return (f'<text x="{x}" y="{y}" fill="{fill}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}"'
            + (' class="mono"' if mono else '') + f'>{escape(value)}</text>')


def start_svg(width, height, title, description, theme):
    p = PALETTES[theme]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
  <title id="title">{escape(title)}</title>
  <desc id="desc">{escape(description)}</desc>
  <style>text {{ font-family: Arial, Helvetica, sans-serif; }} .mono {{ font-family: 'Courier New', Courier, monospace; }}</style>
  <rect x=".5" y=".5" width="{width - 1}" height="{height - 1}" rx="18" fill="{p['bg']}" stroke="{p['line']}"/>
'''
