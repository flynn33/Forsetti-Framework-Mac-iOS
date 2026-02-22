#!/usr/bin/env python3
"""
Split wiki.md into individual GitHub wiki page files.

Output directory: wiki_pages/
  - Home.md          : title, intro, and table of contents
  - <N>-<Slug>.md    : one file per ## section
"""

import re
import os

WIKI_SOURCE = "wiki.md"
OUTPUT_DIR = "wiki_pages"


def slugify(title: str) -> str:
    """Convert a section title like '1. Scope and Audience' into '1-Scope-and-Audience'."""
    slug = title.replace(". ", "-").replace(" ", "-")
    slug = re.sub(r"[^A-Za-z0-9\-]", "", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug


def main() -> None:
    if not os.path.isfile(WIKI_SOURCE):
        raise SystemExit(
            f"Error: source file '{WIKI_SOURCE}' not found. "
            "Run this script from the repository root where wiki.md lives."
        )

    with open(WIKI_SOURCE, "r", encoding="utf-8") as f:
        raw = f.read()

    # Split on lines that start a new ## section
    parts = re.split(r"\n(?=## )", raw)

    intro_block = parts[0].strip()
    section_parts = parts[1:]

    # Build table of contents entries and page map
    toc_lines: list[str] = []
    pages: dict[str, str] = {}

    for section in section_parts:
        lines = section.strip().splitlines()
        heading = lines[0]  # e.g. "## 1. Scope and Audience"
        title = heading.lstrip("#").strip()  # "1. Scope and Audience"
        slug = slugify(title)
        pages[slug] = section.strip()
        toc_lines.append(f"- [{title}]({slug})")

    # Home page = intro + table of contents
    toc_block = "\n".join(toc_lines)
    home_content = f"{intro_block}\n\n## Contents\n\n{toc_block}\n"
    pages["Home"] = home_content

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for page_name, content in pages.items():
        path = os.path.join(OUTPUT_DIR, f"{page_name}.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content + "\n")
        print(f"  wrote {path}")

    print(f"\nTotal pages generated: {len(pages)}")


if __name__ == "__main__":
    main()
