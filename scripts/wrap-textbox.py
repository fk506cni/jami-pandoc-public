#!/usr/bin/env python3
"""Post-process Pandoc docx output to wrap TextBoxMarker regions in OOXML text boxes.

Reads the docx file, finds TextBoxMarker-styled paragraphs emitted by
jami-style.lua, collects the content between start/end markers, and wraps
them in DrawingML text box anchors (wp:anchor > wps:wsp > w:txbxContent).

Preserves the original document.xml root element (with all namespace
declarations) to avoid corruption caused by ElementTree re-serialization.
"""

import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from io import BytesIO

# Namespace map — register all so ElementTree uses correct prefixes
NSMAP = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    "wp14": "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing",
    "wps": "http://schemas.microsoft.com/office/word/2010/wordprocessingShape",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "mc": "http://schemas.openxmlformats.org/markup-compatibility/2006",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
    "o": "urn:schemas-microsoft-com:office:office",
    "v": "urn:schemas-microsoft-com:vml",
    "w10": "urn:schemas-microsoft-com:office:word",
    "pic": "http://schemas.openxmlformats.org/drawingml/2006/picture",
    "wpc": "http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas",
    "asvg": "http://schemas.microsoft.com/office/drawing/2016/SVG/main",
}

for prefix, uri in NSMAP.items():
    ET.register_namespace(prefix, uri)

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
WP = "{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}"
WPS = "{http://schemas.microsoft.com/office/word/2010/wordprocessingShape}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
ASVG = "{http://schemas.microsoft.com/office/drawing/2016/SVG/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"


def get_marker_text(para):
    """Extract hidden text from a TextBoxMarker paragraph."""
    for r in para.findall(f"{W}r"):
        for t in r.findall(f"{W}t"):
            if t.text:
                return t.text
    return ""


def is_textbox_marker(para):
    """Check if a paragraph uses the TextBoxMarker style."""
    ppr = para.find(f"{W}pPr")
    if ppr is None:
        return False
    pstyle = ppr.find(f"{W}pStyle")
    if pstyle is None:
        return False
    return pstyle.get(f"{W}val") == "TextBoxMarker"


def parse_attrs(text):
    """Parse 'TEXTBOX_START:key=val;key=val;...' into a dict."""
    prefix = "TEXTBOX_START:"
    if not text.startswith(prefix):
        return {}
    params_str = text[len(prefix):]
    attrs = {}
    for pair in params_str.split(";"):
        if "=" in pair:
            k, v = pair.split("=", 1)
            attrs[k.strip()] = v.strip()
    return attrs


def _set_cell_borders(tc, top="nil", bottom="nil"):
    """Set booktabs cell borders. top/bottom: 'single' or 'nil'. left/right always nil."""
    tcpr = tc.find(f"{W}tcPr")
    if tcpr is None:
        tcpr = ET.Element(f"{W}tcPr")
        tc.insert(0, tcpr)

    existing = tcpr.find(f"{W}tcBorders")
    if existing is not None:
        tcpr.remove(existing)

    tcb = ET.SubElement(tcpr, f"{W}tcBorders")

    t = ET.SubElement(tcb, f"{W}top")
    if top == "single":
        t.set(f"{W}val", "single")
        t.set(f"{W}sz", "4")
        t.set(f"{W}space", "0")
        t.set(f"{W}color", "auto")
    else:
        t.set(f"{W}val", "nil")

    l = ET.SubElement(tcb, f"{W}left")
    l.set(f"{W}val", "nil")

    b = ET.SubElement(tcb, f"{W}bottom")
    if bottom == "single":
        b.set(f"{W}val", "single")
        b.set(f"{W}sz", "4")
        b.set(f"{W}space", "0")
        b.set(f"{W}color", "auto")
    else:
        b.set(f"{W}val", "nil")

    r = ET.SubElement(tcb, f"{W}right")
    r.set(f"{W}val", "nil")


def _apply_booktabs_to_table(tbl):
    """Apply three-line (booktabs) borders to a single table."""
    tblpr = tbl.find(f"{W}tblPr")
    if tblpr is None:
        tblpr = ET.Element(f"{W}tblPr")
        tbl.insert(0, tblpr)

    # Set tblLook val="04A0" (firstRow=1, noVBand=1)
    look = tblpr.find(f"{W}tblLook")
    if look is None:
        look = ET.SubElement(tblpr, f"{W}tblLook")
    look.set(f"{W}val", "04A0")

    # Remove table-level tblBorders
    tb = tblpr.find(f"{W}tblBorders")
    if tb is not None:
        tblpr.remove(tb)

    rows = tbl.findall(f"{W}tr")
    if not rows:
        return

    for ri, row in enumerate(rows):
        is_header = (row.find(f"{W}trPr/{W}tblHeader") is not None) or (ri == 0)
        is_last = (ri == len(rows) - 1)

        for tc in row.findall(f"{W}tc"):
            if is_header:
                _set_cell_borders(tc, top="single", bottom="single")
            elif is_last:
                _set_cell_borders(tc, bottom="single")
            else:
                _set_cell_borders(tc)  # all nil


def apply_booktabs_borders(root):
    """Apply booktabs (three-line) borders to all tables in the document.

    Skips tables immediately preceded by a GRID_TABLE marker paragraph.
    """
    parent_map = {child: parent for parent in root.iter() for child in parent}

    for tbl in list(root.iter(f"{W}tbl")):
        parent = parent_map.get(tbl)
        if parent is None:
            continue

        # Check if previous sibling is a GRID_TABLE marker
        siblings = list(parent)
        idx = siblings.index(tbl)
        if idx > 0:
            prev = siblings[idx - 1]
            if (prev.tag == f"{W}p" and is_textbox_marker(prev)
                    and get_marker_text(prev) == "GRID_TABLE"):
                continue

        _apply_booktabs_to_table(tbl)


def resize_images_in_content(content_elements, max_width_emu):
    """Resize inline images in content to fit within max_width_emu."""
    for elem in content_elements:
        for inline in elem.iter(f"{WP}inline"):
            ext = inline.find(f"{WP}extent")
            if ext is not None:
                cx = int(ext.get("cx", "0"))
                cy = int(ext.get("cy", "0"))
                if cx > max_width_emu and cx > 0:
                    ratio = max_width_emu / cx
                    new_cx = max_width_emu
                    new_cy = int(cy * ratio)
                    ext.set("cx", str(new_cx))
                    ext.set("cy", str(new_cy))
                    for a_ext in inline.iter(f"{A}ext"):
                        a_cx = int(a_ext.get("cx", "0"))
                        a_cy = int(a_ext.get("cy", "0"))
                        if a_cx > max_width_emu and a_cx > 0:
                            a_ratio = max_width_emu / a_cx
                            a_ext.set("cx", str(max_width_emu))
                            a_ext.set("cy", str(int(a_cy * a_ratio)))


def _center_table(tbl):
    """Center a table within its container (text box).

    A table narrower than the text box would otherwise sit left-aligned with
    empty space on its right. Setting tblPr > jc=center balances it. For a
    table that already fills the box this is a visual no-op. The w:jc element is
    inserted at its correct CT_TblPr schema position (right after tblW etc.).
    """
    tblpr = tbl.find(f"{W}tblPr")
    if tblpr is None:
        tblpr = ET.Element(f"{W}tblPr")
        tbl.insert(0, tblpr)
    for jc in tblpr.findall(f"{W}jc"):
        tblpr.remove(jc)
    # CT_TblPr elements that must precede <w:jc>.
    before = {f"{W}{t}" for t in (
        "tblStyle", "tblpPr", "tblOverlap", "bidiVisual",
        "tblStyleRowBandSize", "tblStyleColBandSize", "tblW")}
    idx = 0
    for i, child in enumerate(list(tblpr)):
        if child.tag in before:
            idx = i + 1
    jc = ET.Element(f"{W}jc")
    jc.set(f"{W}val", "center")
    tblpr.insert(idx, jc)


def resize_tables_in_content(content_elements, max_width_emu):
    """Resize tables in content to fit within max_width_emu, and center them.

    Scales gridCol widths proportionally. 1 twip = 635 EMU.
    """
    EMU_PER_TWIP = 635
    max_width_twips = int(max_width_emu / EMU_PER_TWIP)

    for elem in content_elements:
        # Direct table element
        tables = [elem] if elem.tag == f"{W}tbl" else []
        tables.extend(elem.iter(f"{W}tbl"))

        for tbl in tables:
            _center_table(tbl)
            grid = tbl.find(f"{W}tblGrid")
            if grid is None:
                continue
            cols = grid.findall(f"{W}gridCol")
            if not cols:
                continue

            total = sum(int(c.get(f"{W}w", "0")) for c in cols)
            if total <= 0 or total <= max_width_twips:
                continue

            ratio = max_width_twips / total
            for c in cols:
                old_w = int(c.get(f"{W}w", "0"))
                c.set(f"{W}w", str(int(old_w * ratio)))

            # Also scale cell widths (tcPr > tcW)
            for tc in tbl.iter(f"{W}tc"):
                tcpr = tc.find(f"{W}tcPr")
                if tcpr is not None:
                    tcw = tcpr.find(f"{W}tcW")
                    if tcw is not None:
                        old_w = int(tcw.get(f"{W}w", "0"))
                        if old_w > 0:
                            tcw.set(f"{W}w", str(int(old_w * ratio)))


def build_textbox_paragraph(attrs, content_elements, z_order):
    """Build an OOXML paragraph containing a text box anchor with content."""
    width = int(attrs.get("width", "0"))
    height = int(attrs.get("height", "0"))
    pos_x = int(attrs.get("pos-x", "0"))
    pos_y = int(attrs.get("pos-y", "0"))
    anchor_h = attrs.get("anchor-h", "page")
    anchor_v = attrs.get("anchor-v", "page")
    wrap = attrs.get("wrap", "tight")
    behind = attrs.get("behind", "true")
    behind_val = "1" if behind == "true" else "0"

    # Internal margin (EMU): minimal to align content to top/edges
    l_ins = 45720   # ~1.27mm left
    t_ins = 0       # 0 top — content aligns to textbox top edge
    r_ins = 45720   # ~1.27mm right
    b_ins = 0       # 0 bottom

    # Resize images and tables to fit textbox content width
    content_width = width - l_ins - r_ins
    resize_images_in_content(content_elements, content_width)
    resize_tables_in_content(content_elements, content_width)

    # Build wp:anchor
    anchor = ET.Element(f"{WP}anchor")
    anchor.set("distT", "0")
    anchor.set("distB", "0")
    anchor.set("distL", "114300")
    anchor.set("distR", "114300")
    anchor.set("simplePos", "0")
    anchor.set("relativeHeight", str(251659776 + z_order * 2))
    anchor.set("behindDoc", behind_val)
    anchor.set("locked", "0")
    anchor.set("layoutInCell", "1")
    anchor.set("allowOverlap", "1")

    # simplePos
    sp = ET.SubElement(anchor, f"{WP}simplePos")
    sp.set("x", "0")
    sp.set("y", "0")

    # positionH
    ph = ET.SubElement(anchor, f"{WP}positionH")
    ph.set("relativeFrom", anchor_h)
    po_h = ET.SubElement(ph, f"{WP}posOffset")
    po_h.text = str(pos_x)

    # positionV
    pv = ET.SubElement(anchor, f"{WP}positionV")
    pv.set("relativeFrom", anchor_v)
    po_v = ET.SubElement(pv, f"{WP}posOffset")
    po_v.text = str(pos_y)

    # extent
    ext = ET.SubElement(anchor, f"{WP}extent")
    ext.set("cx", str(width))
    ext.set("cy", str(height))

    # effectExtent
    ee = ET.SubElement(anchor, f"{WP}effectExtent")
    ee.set("l", "0")
    ee.set("t", "0")
    ee.set("r", "0")
    ee.set("b", "0")

    # wrap
    if wrap == "tight":
        wt = ET.SubElement(anchor, f"{WP}wrapTight")
        wt.set("wrapText", "bothSides")
        wp_poly = ET.SubElement(wt, f"{WP}wrapPolygon")
        wp_poly.set("edited", "0")
        for idx, coords in enumerate(
            [(0, 0), (0, 21600), (21600, 21600), (21600, 0), (0, 0)]
        ):
            tag = f"{WP}start" if idx == 0 else f"{WP}lineTo"
            pt = ET.SubElement(wp_poly, tag)
            pt.set("x", str(coords[0]))
            pt.set("y", str(coords[1]))
    elif wrap == "square":
        ws = ET.SubElement(anchor, f"{WP}wrapSquare")
        ws.set("wrapText", "bothSides")
    else:  # none
        ET.SubElement(anchor, f"{WP}wrapNone")

    # docPr
    dp = ET.SubElement(anchor, f"{WP}docPr")
    dp.set("id", str(1000 + z_order))
    dp.set("name", f"TextBox {z_order + 1}")
    # Store page attribute for relocate_textbox_by_page()
    page = attrs.get("page", "")
    if page:
        dp.set("data-page", page)

    # cNvGraphicFramePr
    cnv = ET.SubElement(anchor, f"{WP}cNvGraphicFramePr")
    ET.SubElement(cnv, f"{A}graphicFrameLocks")

    # graphic > graphicData > wsp
    graphic = ET.SubElement(anchor, f"{A}graphic")
    gd = ET.SubElement(graphic, f"{A}graphicData")
    gd.set("uri", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape")

    wsp = ET.SubElement(gd, f"{WPS}wsp")

    # cNvSpPr
    cnvsp = ET.SubElement(wsp, f"{WPS}cNvSpPr")
    cnvsp.set("txBox", "1")
    ET.SubElement(cnvsp, f"{A}spLocks")

    # spPr
    sppr = ET.SubElement(wsp, f"{WPS}spPr")
    xfrm = ET.SubElement(sppr, f"{A}xfrm")
    off = ET.SubElement(xfrm, f"{A}off")
    off.set("x", "0")
    off.set("y", "0")
    aext = ET.SubElement(xfrm, f"{A}ext")
    aext.set("cx", str(width))
    aext.set("cy", str(height))
    pgeom = ET.SubElement(sppr, f"{A}prstGeom")
    pgeom.set("prst", "rect")
    ET.SubElement(pgeom, f"{A}avLst")
    sfill = ET.SubElement(sppr, f"{A}solidFill")
    sysclr = ET.SubElement(sfill, f"{A}sysClr")
    sysclr.set("val", "window")
    sysclr.set("lastClr", "FFFFFF")
    ln = ET.SubElement(sppr, f"{A}ln")
    ln.set("w", "6350")
    ET.SubElement(ln, f"{A}noFill")

    # txbx > txbxContent
    txbx = ET.SubElement(wsp, f"{WPS}txbx")
    txbxc = ET.SubElement(txbx, f"{W}txbxContent")
    for elem in content_elements:
        txbxc.append(elem)

    # bodyPr — valign: "top"→anchor="t", "bottom"→anchor="b"
    valign = attrs.get("valign", "top")
    anchor_val = "b" if valign == "bottom" else "t"
    bpr = ET.SubElement(wsp, f"{WPS}bodyPr")
    bpr.set("wrap", "square")
    bpr.set("anchor", anchor_val)
    bpr.set("lIns", str(l_ins))
    bpr.set("tIns", str(t_ins))
    bpr.set("rIns", str(r_ins))
    bpr.set("bIns", str(b_ins))

    # Wrap in w:p > w:r > w:drawing
    p = ET.Element(f"{W}p")
    r = ET.SubElement(p, f"{W}r")
    drawing = ET.SubElement(r, f"{W}drawing")
    drawing.append(anchor)

    return p


def extract_root_tag(xml_bytes):
    """Extract the original root element opening tag from XML bytes.

    Returns the full opening tag string (e.g. '<w:document xmlns:w="..." ...>')
    so we can restore it after ElementTree re-serialization, preserving all
    original namespace declarations that ET would otherwise drop.
    """
    xml_str = xml_bytes.decode("utf-8")
    # Find <w:document ...> or similar root tag (skip XML declaration)
    m = re.search(r"<([a-zA-Z][a-zA-Z0-9]*:)?document\s[^>]*>", xml_str)
    if m:
        return m.group(0)
    return None


def restore_root_tag(new_xml_bytes, original_root_tag):
    """Replace the re-serialized root element tag with the original one.

    ElementTree re-serialization loses namespace declarations that aren't
    used in the tree. This restores the original root tag which has all
    the namespace declarations Word expects, and adds mc:Ignorable for
    wps/wp14 namespaces used by text boxes.
    """
    xml_str = new_xml_bytes.decode("utf-8")

    # Collect any NEW namespace declarations from the re-serialized root
    # that weren't in the original (e.g. wps namespace added by our textbox)
    new_m = re.search(r"<([a-zA-Z][a-zA-Z0-9]*:)?document\s([^>]*)>", xml_str)
    if not new_m:
        return new_xml_bytes

    new_attrs = new_m.group(2)
    new_ns_decls = dict(re.findall(r'xmlns:(\w+)="([^"]*)"', new_attrs))
    orig_ns_decls = dict(re.findall(r'xmlns:(\w+)="([^"]*)"', original_root_tag))

    # Merge: add any new namespace declarations to original root tag
    merged_tag = original_root_tag
    for prefix, uri in new_ns_decls.items():
        if prefix not in orig_ns_decls:
            merged_tag = merged_tag[:-1] + f' xmlns:{prefix}="{uri}">'
            orig_ns_decls[prefix] = uri

    # Add mc, wp14 namespaces and mc:Ignorable (required for wps text boxes)
    MC_URI = "http://schemas.openxmlformats.org/markup-compatibility/2006"
    WP14_URI = "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
    if "mc" not in orig_ns_decls:
        merged_tag = merged_tag[:-1] + f' xmlns:mc="{MC_URI}">'
    if "wp14" not in orig_ns_decls:
        merged_tag = merged_tag[:-1] + f' xmlns:wp14="{WP14_URI}">'

    # Add mc:Ignorable attribute if not present
    if "mc:Ignorable" not in merged_tag:
        merged_tag = merged_tag[:-1] + ' mc:Ignorable="wps wp14">'
    else:
        # Ensure wps and wp14 are in the ignorable list
        ig_m = re.search(r'mc:Ignorable="([^"]*)"', merged_tag)
        if ig_m:
            ignorable = ig_m.group(1).split()
            for ns in ["wps", "wp14"]:
                if ns not in ignorable:
                    ignorable.append(ns)
            merged_tag = merged_tag.replace(
                ig_m.group(0), f'mc:Ignorable="{" ".join(ignorable)}"'
            )

    # Replace the re-serialized root tag with merged original
    xml_str = re.sub(
        r"<([a-zA-Z][a-zA-Z0-9]*:)?document\s[^>]*>",
        merged_tag,
        xml_str,
        count=1,
    )
    return xml_str.encode("utf-8")


def relocate_textbox_by_page(root):
    """Move textbox anchor paragraphs to target page positions based on page attribute.

    Estimates page boundaries from the document structure:
    - continuous sectPr marks the transition from header area to body (2-col start)
    - explicit page breaks (w:br w:type="page") mark additional page boundaries
    - if no page breaks, body paragraphs are split evenly across estimated pages
    """
    body = root.find(f"{W}body")
    if body is None:
        return

    children = list(body)

    # Find body start: the paragraph after the continuous sectPr (1-col → 2-col)
    body_start = 0
    for i, child in enumerate(children):
        if child.tag == f"{W}p":
            ppr = child.find(f"{W}pPr")
            if ppr is not None:
                sectpr = ppr.find(f"{W}sectPr")
                if sectpr is not None:
                    body_start = i + 1
                    break

    # Find body end: the last sectPr in body (document-level sectPr)
    body_end = len(children)
    for i in range(len(children) - 1, body_start - 1, -1):
        if children[i].tag == f"{W}sectPr":
            body_end = i
            break

    # Count header paragraphs (before body_start) to estimate page 1 header area
    header_para_count = 0
    for i in range(0, body_start):
        if children[i].tag == f"{W}p":
            header_para_count += 1

    # Collect body paragraphs (excluding textbox anchor paragraphs)
    body_paras = []
    for i in range(body_start, body_end):
        child = children[i]
        if child.tag == f"{W}p":
            # Skip paragraphs that are textbox anchors (contain wp:anchor)
            has_anchor = child.find(f".//{WP}anchor") is not None
            if not has_anchor:
                body_paras.append(i)

    if not body_paras:
        return

    # Find page breaks within body to determine page boundaries
    page_breaks = [body_paras[0]]  # page 1 starts at first body paragraph
    for idx in body_paras:
        child = children[idx]
        for br in child.iter(f"{W}br"):
            if br.get(f"{W}type") == "page":
                page_breaks.append(idx)
                break

    # Collect textbox paragraphs and find max requested page
    textboxes_to_move = []
    max_page_requested = 1
    for i, child in enumerate(children):
        if child.tag != f"{W}p":
            continue
        anchor_el = child.find(f".//{WP}anchor")
        if anchor_el is None:
            continue
        docpr = anchor_el.find(f"{WP}docPr")
        if docpr is None or "TextBox" not in docpr.get("name", ""):
            continue
        textboxes_to_move.append((i, child))
        page_str = docpr.get("data-page", "")
        if page_str:
            try:
                max_page_requested = max(max_page_requested, int(page_str))
            except ValueError:
                pass

    if not textboxes_to_move:
        return

    # Page offset: the 1-column header (title/authors/abstract) on page 1
    # plus high density of short paragraphs (headings, list items) in early
    # sections means more paragraphs fit on initial pages than the even-
    # distribution heuristic estimates. Apply a fixed offset at lookup time
    # so that page=N targets a later paragraph position.
    page_offset = 2 if (body_start > 0 and header_para_count > 2) else 0

    # Ensure enough page boundaries for all requested pages (including offset)
    num_pages_needed = max(max_page_requested + page_offset, len(page_breaks))
    if len(page_breaks) < num_pages_needed and len(body_paras) > 1:
        segment_size = max(1, len(body_paras) // num_pages_needed)
        page_breaks = []
        for p in range(num_pages_needed):
            idx = min(p * segment_size, len(body_paras) - 1)
            page_breaks.append(body_paras[idx])
        print(f"  Estimated {num_pages_needed} page boundaries "
              f"({len(body_paras)} body paragraphs, ~{segment_size} per page, "
              f"page_offset={page_offset}, header: {header_para_count} paras)")
    elif len(page_breaks) < 2:
        mid = body_paras[len(body_paras) // 2] if body_paras else body_start
        page_breaks.append(mid)
    moves = []
    for orig_idx, para in textboxes_to_move:
        anchor_el = para.find(f".//{WP}anchor")
        docpr = anchor_el.find(f"{WP}docPr")
        page_str = docpr.get("data-page", "") if docpr is not None else ""
        if not page_str:
            continue
        target_page = int(page_str)
        if target_page < 1:
            continue

        # Apply page offset to compensate for header area + paragraph density
        effective_page = min(target_page + page_offset, len(page_breaks))

        # Determine target index based on effective page number
        if effective_page <= len(page_breaks):
            target_idx = page_breaks[effective_page - 1]
        else:
            # Beyond known pages — place at last page boundary
            target_idx = page_breaks[-1]

        if orig_idx != target_idx:
            moves.append((orig_idx, target_idx, para))

    if not moves:
        return

    # Sort moves by original index descending to avoid index shifting issues
    moves.sort(key=lambda x: x[0], reverse=True)
    for orig_idx, target_idx, para in moves:
        body.remove(para)
        # Recalculate target position after removal
        children = list(body)
        # Find the target element and insert before it
        actual_target = min(target_idx, len(children))
        # Adjust if our removal shifted indices
        body.insert(actual_target, para)
        print(f"  Relocated TextBox to page position (target index {actual_target})")

    # Refresh children list
    children = list(body)


def _strip_yaml_and_code(md_text):
    """Remove YAML front matter and fenced code blocks from markdown text."""
    # Remove YAML front matter
    md_text = re.sub(r'^---\n.*?\n---\n', '', md_text, count=1, flags=re.DOTALL)
    # Remove fenced code blocks
    md_text = re.sub(r'```[^`]*```', '', md_text, flags=re.DOTALL)
    return md_text


def embed_svg_native(root, parts, source_md_path):
    """Embed SVG files natively into the docx using Office 2016+ SVG extension.

    Uses position-based matching: the K-th image in the source markdown
    corresponds to the K-th a:blip element in document.xml.
    """

    # Read source markdown and extract image paths
    with open(source_md_path, "r", encoding="utf-8") as f:
        md_text = f.read()

    md_text = _strip_yaml_and_code(md_text)
    image_paths = re.findall(r'!\[.*?\]\(([^)\s]+)', md_text)

    if not image_paths:
        return

    # Identify which images are SVGs (with their original index)
    svg_images = []
    for idx, path in enumerate(image_paths):
        if path.endswith(".svg"):
            svg_images.append((idx, path))

    if not svg_images:
        return

    print(f"Found {len(svg_images)} SVG image(s) to embed natively")

    # Get all a:blip elements in document order
    blips = list(root.iter(f"{A}blip"))

    # Parse word/_rels/document.xml.rels
    RELS_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
    ET.register_namespace("", RELS_NS)
    rels_path = "word/_rels/document.xml.rels"
    rels_root = ET.fromstring(parts[rels_path])

    # Find max rId number
    max_rid = 0
    for rel in rels_root:
        rid = rel.get("Id", "")
        if rid.startswith("rId"):
            try:
                num = int(rid[3:])
                max_rid = max(max_rid, num)
            except ValueError:
                pass

    # Parse [Content_Types].xml
    CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
    ET.register_namespace("", CT_NS)
    ct_root = ET.fromstring(parts["[Content_Types].xml"])

    svg_ct_added = False
    svg_counter = 0

    for img_idx, svg_path in svg_images:
        if img_idx >= len(blips):
            print(f"  Warning: no matching blip for image index {img_idx} ({svg_path})")
            continue

        blip = blips[img_idx]

        # Resolve SVG file path (paths in markdown are relative to working directory)
        svg_full_path = svg_path

        if not os.path.isfile(svg_full_path):
            print(f"  Warning: SVG file not found: {svg_full_path}")
            continue

        # Read SVG file
        with open(svg_full_path, "rb") as f:
            svg_data = f.read()

        # Add SVG to parts
        svg_counter += 1
        svg_media_path = f"word/media/svg{svg_counter}.svg"
        parts[svg_media_path] = svg_data

        # Add Relationship
        max_rid += 1
        new_rid = f"rId{max_rid}"
        rel_el = ET.SubElement(rels_root, "Relationship")
        rel_el.set("Id", new_rid)
        rel_el.set("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image")
        rel_el.set("Target", f"media/svg{svg_counter}.svg")

        # Add asvg:svgBlob extension to a:blip
        # Structure: a:blip > a:extLst > a:ext(uri) > asvg:svgBlob(r:embed)
        ext_lst = blip.find(f"{A}extLst")
        if ext_lst is None:
            ext_lst = ET.SubElement(blip, f"{A}extLst")

        ext_el = ET.SubElement(ext_lst, f"{A}ext")
        ext_el.set("uri", "{96DAC541-7B7A-43D3-8B79-37D633B846F1}")

        svg_blob = ET.SubElement(ext_el, f"{ASVG}svgBlob")
        svg_blob.set(f"{R}embed", new_rid)

        print(f"  Embedded: {svg_path} → {svg_media_path} ({new_rid})")

        # Add SVG content type (once)
        if not svg_ct_added:
            # Check if already exists
            has_svg_ct = False
            for default in ct_root.findall(f"{{{CT_NS}}}Default"):
                if default.get("Extension") == "svg":
                    has_svg_ct = True
                    break
            if not has_svg_ct:
                ct_default = ET.SubElement(ct_root, "Default")
                ct_default.set("Extension", "svg")
                ct_default.set("ContentType", "image/svg+xml")
            svg_ct_added = True

    # Write back rels and Content_Types
    rels_buf = BytesIO()
    ET.ElementTree(rels_root).write(rels_buf, xml_declaration=True, encoding="UTF-8")
    parts[rels_path] = rels_buf.getvalue()

    ct_buf = BytesIO()
    ET.ElementTree(ct_root).write(ct_buf, xml_declaration=True, encoding="UTF-8")
    parts["[Content_Types].xml"] = ct_buf.getvalue()


def process_docx(docx_path, source_md=None, no_relocate=False):
    """Process the docx file, replacing TextBoxMarker regions with text boxes."""
    with zipfile.ZipFile(docx_path, "r") as zin:
        parts = {}
        for item in zin.infolist():
            parts[item.filename] = zin.read(item.filename)

    doc_xml = parts["word/document.xml"]

    # Save original root element tag before parsing (preserves all namespaces)
    original_root_tag = extract_root_tag(doc_xml)

    root = ET.fromstring(doc_xml)
    body = root.find(f"{W}body")

    if body is None:
        print("ERROR: No body element found", file=sys.stderr)
        sys.exit(1)

    # Apply booktabs borders to all tables (before textbox processing)
    apply_booktabs_borders(root)

    # Embed SVG natively (after booktabs, before textbox processing)
    if source_md:
        embed_svg_native(root, parts, source_md)

    # Collect all direct children of body
    children = list(body)

    # Find textbox regions
    regions = []
    i = 0
    while i < len(children):
        child = children[i]
        if child.tag == f"{W}p" and is_textbox_marker(child):
            text = get_marker_text(child)
            if text.startswith("TEXTBOX_START:"):
                attrs = parse_attrs(text)
                start_idx = i
                content = []
                i += 1
                while i < len(children):
                    if (children[i].tag == f"{W}p"
                            and is_textbox_marker(children[i])):
                        end_text = get_marker_text(children[i])
                        if end_text == "TEXTBOX_END":
                            regions.append((start_idx, i, attrs, content))
                            break
                    else:
                        content.append(children[i])
                    i += 1
        i += 1

    if not regions:
        print(f"No TextBoxMarker regions found in {docx_path}")
        return

    print(f"Found {len(regions)} textbox region(s)")

    # Process regions in reverse order to maintain indices
    for z_order, (start_idx, end_idx, attrs, content) in enumerate(
        reversed(regions)
    ):
        actual_z = len(regions) - 1 - z_order

        # Remove original elements (markers + content) from body
        for j in range(end_idx, start_idx - 1, -1):
            body.remove(children[j])

        # Build textbox paragraph
        tb_para = build_textbox_paragraph(attrs, content, actual_z)

        # Insert at start position
        body.insert(start_idx, tb_para)

        # Update children list
        children = list(body)

    # Relocate textboxes with page attribute to target page positions
    if not no_relocate:
        relocate_textbox_by_page(root)
    else:
        print("  Skipping page relocation (--no-relocate): textboxes stay at natural document flow positions")

    # Serialize back
    tree = ET.ElementTree(root)
    buf = BytesIO()
    tree.write(buf, xml_declaration=True, encoding="UTF-8")
    new_xml = buf.getvalue()

    # Restore original root element tag (with all namespace declarations)
    if original_root_tag:
        new_xml = restore_root_tag(new_xml, original_root_tag)

    parts["word/document.xml"] = new_xml

    # Write back to ZIP
    with zipfile.ZipFile(docx_path, "w", zipfile.ZIP_DEFLATED) as zout:
        for filename, data in parts.items():
            zout.writestr(filename, data)

    print(f"Processed: {docx_path} ({len(regions)} text box(es))")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(
        description="Post-process Pandoc docx: booktabs, SVG embedding, textboxes")
    parser.add_argument("docx", help="Path to docx file")
    parser.add_argument("--source", help="Source markdown for SVG embedding")
    parser.add_argument("--no-relocate", action="store_true",
                        help="Skip page-based textbox relocation (use natural document flow)")
    args = parser.parse_args()
    process_docx(args.docx, source_md=args.source, no_relocate=args.no_relocate)
