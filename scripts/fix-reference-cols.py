#!/usr/bin/env python3
"""Fix reference.docx for Pandoc compatibility.

1. Set body-level sectPr to 2-column continuous layout
2. Add missing paragraph styles that Pandoc uses (Compact, Heading3, etc.)
"""

import sys
import zipfile
import shutil
import xml.etree.ElementTree as ET
from io import BytesIO

NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
ET.register_namespace("w", NS)
# Preserve all other namespaces used in document.xml
for prefix, uri in [
    ("m", "http://schemas.openxmlformats.org/officeDocument/2006/math"),
    ("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships"),
    ("o", "urn:schemas-microsoft-com:office:office"),
    ("v", "urn:schemas-microsoft-com:vml"),
    ("w10", "urn:schemas-microsoft-com:office:word"),
    ("a", "http://schemas.openxmlformats.org/drawingml/2006/main"),
    ("pic", "http://schemas.openxmlformats.org/drawingml/2006/picture"),
    ("wp", "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"),
]:
    ET.register_namespace(prefix, uri)


def fix_body_sectpr(docx_path):
    W = f"{{{NS}}}"

    with zipfile.ZipFile(docx_path, "r") as zin:
        parts = {}
        for item in zin.infolist():
            parts[item.filename] = zin.read(item.filename)

    # Parse document.xml
    doc_xml = parts["word/document.xml"]
    tree = ET.ElementTree(ET.fromstring(doc_xml))
    root = tree.getroot()
    body = root.find(f"{W}body")

    # Find body-level sectPr (direct child of body, last element)
    body_sectpr = None
    for child in body:
        if child.tag == f"{W}sectPr":
            body_sectpr = child

    if body_sectpr is None:
        print("ERROR: No body-level sectPr found", file=sys.stderr)
        sys.exit(1)

    # Set type to continuous (so body section starts on same page as header)
    type_el = body_sectpr.find(f"{W}type")
    if type_el is None:
        type_el = ET.SubElement(body_sectpr, f"{W}type")
        # Insert as first child
        body_sectpr.remove(type_el)
        body_sectpr.insert(0, type_el)
    type_el.set(f"{W}val", "continuous")

    # Set cols to 2-column
    cols_el = body_sectpr.find(f"{W}cols")
    if cols_el is None:
        cols_el = ET.SubElement(body_sectpr, f"{W}cols")
    cols_el.set(f"{W}num", "2")
    cols_el.set(f"{W}space", "425")

    # Remove mid-document sectPr elements (in paragraph pPr) to avoid conflicts
    for ppr in body.findall(f".//{W}pPr"):
        for sectpr in ppr.findall(f"{W}sectPr"):
            ppr.remove(sectpr)

    # Serialize document.xml back
    buf = BytesIO()
    tree.write(buf, xml_declaration=True, encoding="UTF-8")
    parts["word/document.xml"] = buf.getvalue()

    # --- Add missing paragraph styles to styles.xml ---
    styles_xml = parts["word/styles.xml"]
    styles_tree = ET.ElementTree(ET.fromstring(styles_xml))
    styles_root = styles_tree.getroot()

    existing_ids = {
        s.get(f"{W}styleId")
        for s in styles_root.findall(f"{W}style")
    }

    def add_style(sid, sname, based_on, ppr_attrs=None, rpr_attrs=None):
        """Add a paragraph style if it doesn't already exist."""
        if sid in existing_ids:
            return
        style_el = ET.SubElement(styles_root, f"{W}style")
        style_el.set(f"{W}type", "paragraph")
        style_el.set(f"{W}styleId", sid)
        n = ET.SubElement(style_el, f"{W}name")
        n.set(f"{W}val", sname)
        b = ET.SubElement(style_el, f"{W}basedOn")
        b.set(f"{W}val", based_on)
        if ppr_attrs:
            ppr = ET.SubElement(style_el, f"{W}pPr")
            for tag, attrs in ppr_attrs:
                el = ET.SubElement(ppr, f"{W}{tag}")
                for k, v in attrs.items():
                    el.set(f"{W}{k}", v)
        if rpr_attrs:
            rpr = ET.SubElement(style_el, f"{W}rPr")
            for tag, attrs in rpr_attrs:
                el = ET.SubElement(rpr, f"{W}{tag}")
                for k, v in attrs.items():
                    el.set(f"{W}{k}", v)
        print(f"  Added style: {sid} ({sname})")

    # Pandoc uses these styles but JAMI template lacks them.
    # Compact: table cells — based on JSEK, 9pt, no indent, tight spacing
    add_style("Compact", "Compact", "JSEK",
              ppr_attrs=[
                  ("spacing", {"before": "0", "after": "0",
                               "line": "240", "lineRule": "auto"}),
                  ("ind", {"firstLine": "0", "start": "0"}),
              ],
              rpr_attrs=[("sz", {"val": "18"}), ("szCs", {"val": "18"})])

    # Heading3: subsection heading — based on Heading 2
    add_style("Heading3", "Heading 3", "2")

    # TableCaption: table caption — based on JSEK, 10pt, no indent
    add_style("TableCaption", "Table Caption", "JSEK",
              ppr_attrs=[("ind", {"firstLine": "0", "start": "0"})],
              rpr_attrs=[("sz", {"val": "20"}), ("szCs", {"val": "20"})])

    # ImageCaption: figure caption — based on JSEK, 10pt, centered, no indent
    add_style("ImageCaption", "Image Caption", "JSEK",
              ppr_attrs=[
                  ("jc", {"val": "center"}),
                  ("ind", {"firstLine": "0", "start": "0"}),
              ],
              rpr_attrs=[("sz", {"val": "20"}), ("szCs", {"val": "20"})])

    # Bibliography: references — based on JSEK, 8pt, no indent
    add_style("Bibliography", "Bibliography", "JSEK",
              ppr_attrs=[("ind", {"firstLine": "0", "start": "0"})],
              rpr_attrs=[("sz", {"val": "16"}), ("szCs", {"val": "16"})])

    # ListNumber: ordered list items — based on JSEK, compact hanging indent
    # left=420 (~7.4mm), hanging=210 (~3.7mm) → number at 210 twips, wrap at 420
    add_style("ListNumber", "List Number", "JSEK",
              ppr_attrs=[
                  ("ind", {"left": "420", "hanging": "210"}),
              ])

    # CaptionedFigure: Pandoc outputs this for figures — missing causes docx corruption
    add_style("CaptionedFigure", "Captioned Figure", "ImageCaption")

    # TextBoxMarker: hidden marker for wrap-textbox.py post-processing
    add_style("TextBoxMarker", "TextBox Marker", "JSEK",
              ppr_attrs=[("spacing", {"before": "0", "after": "0",
                                      "line": "240", "lineRule": "auto"})],
              rpr_attrs=[("vanish", {}), ("sz", {"val": "2"}), ("szCs", {"val": "2"})])

    # FigureTable, Table: table styles Pandoc uses — add as table styles
    for tsid, tsname in [("FigureTable", "Figure Table"), ("Table", "Table")]:
        if tsid not in existing_ids:
            tst = ET.SubElement(styles_root, f"{W}style")
            tst.set(f"{W}type", "table")
            tst.set(f"{W}styleId", tsid)
            tn = ET.SubElement(tst, f"{W}name")
            tn.set(f"{W}val", tsname)
            tb = ET.SubElement(tst, f"{W}basedOn")
            tb.set(f"{W}val", "af0")  # based on Table Grid
            print(f"  Added table style: {tsid} ({tsname})")

    # --- Modify existing styles: fonts and sizes ---
    def set_rpr_font_size(style, fonts=None, sz=None, bold=None):
        """Set rPr font, size, bold on a style element."""
        rpr = style.find(f"{W}rPr")
        if rpr is None:
            rpr = ET.SubElement(style, f"{W}rPr")
        if fonts:
            rf = rpr.find(f"{W}rFonts")
            if rf is None:
                rf = ET.SubElement(rpr, f"{W}rFonts")
            for attr, val in fonts.items():
                rf.set(f"{W}{attr}", val)
        if sz:
            for tag in ["sz", "szCs"]:
                el = rpr.find(f"{W}{tag}")
                if el is None:
                    el = ET.SubElement(rpr, f"{W}{tag}")
                el.set(f"{W}val", sz)
        if bold is not None:
            b_el = rpr.find(f"{W}b")
            if bold and b_el is None:
                ET.SubElement(rpr, f"{W}b")
            elif not bold and b_el is not None:
                rpr.remove(b_el)

    # --- Remove numPr and update fonts/sizes ---
    for style in styles_root.findall(f"{W}style"):
        sid = style.get(f"{W}styleId")
        if sid == "2":
            # Heading 2: Times New Roman / MS Pゴシック, 10.5pt, Bold
            ppr = style.find(f"{W}pPr")
            if ppr is not None:
                numpr = ppr.find(f"{W}numPr")
                if numpr is not None:
                    ppr.remove(numpr)
                    print("  Removed numPr from Heading 2")
            set_rpr_font_size(style,
                              fonts={"ascii": "Times New Roman",
                                     "hAnsi": "Times New Roman",
                                     "eastAsia": "\uff2d\uff33 \uff30\u30b4\u30b7\u30c3\u30af"},
                              sz="21", bold=True)
            print("  Updated Heading 2: Times New Roman / MS Pゴシック, 10.5pt, Bold")
        elif sid == "JSEK":
            # JSEK本文: Times New Roman / MS P明朝, 10.5pt
            set_rpr_font_size(style, sz="21")
            print("  Updated JSEK本文: 10.5pt")
        elif sid == "Heading3":
            # Prevent inheriting numPr from Heading 2 (basedOn="2")
            ppr = style.find(f"{W}pPr")
            if ppr is None:
                ppr = ET.SubElement(style, f"{W}pPr")
            numpr = ppr.find(f"{W}numPr")
            if numpr is None:
                numpr = ET.SubElement(ppr, f"{W}numPr")
            numid = numpr.find(f"{W}numId")
            if numid is None:
                numid = ET.SubElement(numpr, f"{W}numId")
            numid.set(f"{W}val", "0")
            print("  Set Heading3 numId=0 (inheritance prevention)")

    buf2 = BytesIO()
    styles_tree.write(buf2, xml_declaration=True, encoding="UTF-8")
    parts["word/styles.xml"] = buf2.getvalue()

    # Write back to ZIP
    with zipfile.ZipFile(docx_path, "w", zipfile.ZIP_DEFLATED) as zout:
        for filename, data in parts.items():
            zout.writestr(filename, data)

    print(f"Fixed: {docx_path} → 2-column continuous body sectPr")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <reference.docx>", file=sys.stderr)
        sys.exit(1)
    fix_body_sectpr(sys.argv[1])
