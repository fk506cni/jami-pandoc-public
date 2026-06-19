#!/usr/bin/env python3
"""
Restore .textbox Div blocks from the NEW markdown file into diff markdown.

pandiff destroys .textbox Divs, converting tables to HTML <table> and
stripping figure wrappers. This script:
1. Removes HTML <table>...</table> blocks from pandiff output
2. Removes figure diff patterns ({--![...]--} / {++![...]++})
3. Inserts the original .textbox Div blocks from the NEW file

Usage:
    echo "$MERGED_MD" | python3 scripts/restore-textboxes.py NEW_FILE.md
"""

import sys
import re


def extract_textbox_blocks(text):
    """Extract .textbox Div blocks from markdown, with their section heading context.

    Returns list of dicts: {'heading': '### 2.1 ...', 'text': '::: {.textbox ...}\n...\n:::'}
    """
    blocks = []
    lines = text.split('\n')
    current_heading = None
    i = 0
    while i < len(lines):
        # Track current heading
        m = re.match(r'^(##+ .+)$', lines[i])
        if m:
            current_heading = m.group(1).strip()

        # Found a textbox block
        if lines[i].strip().startswith('::: {.textbox'):
            tb_lines = [lines[i]]
            i += 1
            depth = 1
            while i < len(lines) and depth > 0:
                stripped = lines[i].strip()
                if stripped == ':::':
                    depth -= 1
                elif re.match(r'^:::\s*\{', stripped):
                    depth += 1
                tb_lines.append(lines[i])
                i += 1
            blocks.append({
                'heading': current_heading,
                'text': '\n'.join(tb_lines),
            })
            continue
        i += 1
    return blocks


def remove_html_tables(text):
    """Remove HTML <table>...</table> blocks (pandiff converts pipe tables to HTML)."""
    return re.sub(r'\n*<table>.*?</table>\n*', '\n\n', text, flags=re.DOTALL)


def remove_figure_diffs(text):
    """Remove diff-annotated figure lines from pandiff output.

    Patterns:
      {--![caption](path)--}
      {++![caption](path)++}
    """
    text = re.sub(r'\n*\{--!\[.*?\]\(.*?\)--\}\s*\n*', '\n\n', text, flags=re.DOTALL)
    text = re.sub(r'\n*\{\+\+!\[.*?\]\(.*?\)\+\+\}\s*\n*', '\n\n', text, flags=re.DOTALL)
    return text


def insert_textbox_blocks(text, textbox_blocks):
    """Insert textbox blocks at the end of their respective sections.

    Each textbox is placed just before the next heading (or end of text)
    within the section identified by the textbox's heading context.
    """
    # Collect insertion points: (position_in_text, textbox_text)
    insertions = []

    for block in textbox_blocks:
        heading = block['heading']
        tb_text = block['text']

        if not heading:
            continue

        # Find the heading in the merged text
        heading_pattern = re.escape(heading)
        m = re.search(r'^' + heading_pattern + r'$', text, re.MULTILINE)
        if not m:
            continue

        # Find the next heading at same or higher level
        heading_level = len(heading.split()[0])  # count '#' chars
        after_heading = text[m.end():]
        # Match any heading with level <= current (e.g., ## or ### for a ### section)
        next_heading = re.search(
            r'^#{2,' + str(heading_level) + r'}\s',
            after_heading,
            re.MULTILINE,
        )
        if next_heading:
            insert_pos = m.end() + next_heading.start()
        else:
            insert_pos = len(text)

        insertions.append((insert_pos, tb_text))

    # Sort by position descending (process from end to avoid offset shifts)
    insertions.sort(key=lambda x: x[0], reverse=True)

    for pos, tb_text in insertions:
        text = text[:pos].rstrip() + '\n\n' + tb_text + '\n\n' + text[pos:]

    return text


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} NEW_FILE.md", file=sys.stderr)
        sys.exit(1)

    new_file = sys.argv[1]
    merged_md = sys.stdin.read()

    with open(new_file) as f:
        new_text = f.read()

    # Extract textbox blocks from the NEW file
    textbox_blocks = extract_textbox_blocks(new_text)

    # Remove pandiff's HTML tables and figure diffs from merged markdown
    merged_md = remove_html_tables(merged_md)
    merged_md = remove_figure_diffs(merged_md)

    # Insert textbox blocks at correct positions
    merged_md = insert_textbox_blocks(merged_md, textbox_blocks)

    # Clean up excessive blank lines
    merged_md = re.sub(r'\n{3,}', '\n\n', merged_md)

    sys.stdout.write(merged_md)


if __name__ == '__main__':
    main()
