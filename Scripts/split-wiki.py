#!/usr/bin/env python3
"""
Generate individual GitHub wiki page files from wiki.md, README.md, guide.md,
and developer-guide.md.

Output directory: wiki_pages/
  - Home.md                      : README.md content (repository overview / wiki landing page)
  - Developer-Guide.md           : guide.md content (integration rules and developer workflow)
  - Forsetti-Developer-Guide.md  : developer-guide.md content (framework developer guide)
  - <N>-<Slug>.md                : one file per ## section from wiki.md
"""

import re
import os

WIKI_SOURCE = "wiki.md"
README_SOURCE = "README.md"
GUIDE_SOURCE = "guide.md"
DEVELOPER_GUIDE_SOURCE = "developer-guide.md"
OUTPUT_DIR = "wiki_pages"


def slugify(title: str) -> str:
    """Convert a section title like '1. Scope and Audience' into '1-Scope-and-Audience'."""
    slug = title.replace(". ", "-").replace(" ", "-")
    slug = re.sub(r"[^A-Za-z0-9\-]", "", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug


def read_file(path: str) -> str:
    if not os.path.isfile(path):
        raise SystemExit(
            f"Error: source file '{path}' not found. "
            "Run this script from the repository root."
        )
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def main() -> None:
    readme_raw = read_file(README_SOURCE)
    guide_raw = read_file(GUIDE_SOURCE)
    developer_guide_raw = read_file(DEVELOPER_GUIDE_SOURCE)
    wiki_raw = read_file(WIKI_SOURCE)

    pages: dict[str, str] = {}

    # Home page = README.md (repository overview and wiki landing page)
    pages["Home"] = readme_raw.strip()

    # Developer guide page = guide.md
    pages["Developer-Guide"] = guide_raw.strip()

    # Forsetti developer guide page = developer-guide.md
    pages["Forsetti-Developer-Guide"] = developer_guide_raw.strip()

    # Split wiki.md on lines that start a new ## section
    parts = re.split(r"\n(?=## )", wiki_raw)
    section_parts = parts[1:]  # skip the # title / intro block

    for section in section_parts:
        lines = section.strip().splitlines()
        heading = lines[0]  # e.g. "## 1. Scope and Audience"
        title = heading.lstrip("#").strip()  # "1. Scope and Audience"
        slug = slugify(title)
        pages[slug] = section.strip()

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for page_name, content in pages.items():
        path = os.path.join(OUTPUT_DIR, f"{page_name}.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content + "\n")
        print(f"  wrote {path}")

    print(f"\nTotal pages generated: {len(pages)}")


if __name__ == "__main__":
    main()
