-- jami-style.lua: Wrap top-level Para blocks with JSEK本文 custom-style
-- Only active for docx output
--
-- Uses Pandoc-level filter to avoid Blocks being called recursively
-- inside custom-style Divs (which would double-wrap their inner Para).

if FORMAT ~= "docx" then
  return {}
end

--- Check if a Div has a custom-style attribute
local function has_custom_style(div)
  return div.attributes and div.attributes["custom-style"] ~= nil
end

--- Convert dimension string (e.g. "80mm", "300pt") to EMU (English Metric Units)
--- 1mm = 36000 EMU, 1pt = 12700 EMU, 1cm = 360000 EMU, 1in = 914400 EMU
local function to_emu(s)
  if not s then return 0 end
  local num, unit = s:match("^([%d%.]+)%s*(%a+)$")
  if not num then return tonumber(s) or 0 end
  num = tonumber(num)
  if unit == "mm" then return math.floor(num * 36000)
  elseif unit == "pt" then return math.floor(num * 12700)
  elseif unit == "cm" then return math.floor(num * 360000)
  elseif unit == "in" then return math.floor(num * 914400)
  elseif unit == "emu" then return math.floor(num)
  else return math.floor(num) end
end

--- Build a TextBoxMarker RawBlock with encoded attributes
local function textbox_marker(text)
  return pandoc.RawBlock("openxml",
    '<w:p><w:pPr><w:pStyle w:val="TextBoxMarker"/></w:pPr>' ..
    '<w:r><w:rPr><w:vanish/></w:rPr>' ..
    '<w:t>' .. text .. '</w:t></w:r></w:p>')
end

-- Forward declarations for mutual recursion
local process_blocks

--- Process a .textbox Div: emit start/end markers around content
local function process_textbox(div)
  local attrs = div.attributes
  local width = to_emu(attrs["width"] or "0")
  local height = to_emu(attrs["height"] or "0")
  local pos_x = to_emu(attrs["pos-x"] or "0pt")
  local pos_y = to_emu(attrs["pos-y"] or "0pt")
  local anchor_h = attrs["anchor-h"] or "page"
  local anchor_v = attrs["anchor-v"] or "page"
  local wrap = attrs["wrap"] or "tight"
  local behind = attrs["behind"] or "false"
  local valign = attrs["valign"] or "top"
  local page = attrs["page"]  -- optional, nil if not specified

  local params = string.format(
    "TEXTBOX_START:width=%d;height=%d;pos-x=%d;pos-y=%d;anchor-h=%s;anchor-v=%s;wrap=%s;behind=%s;valign=%s",
    width, height, pos_x, pos_y, anchor_h, anchor_v, wrap, behind, valign)
  if page then
    params = params .. ";page=" .. page
  end

  local result = pandoc.List()
  result:insert(textbox_marker(params))
  -- Process inner content normally (apply JSEK本文 etc.)
  local inner = process_blocks(div.content)
  result:extend(inner)
  result:insert(textbox_marker("TEXTBOX_END"))
  return result
end

--- Recursively process blocks: wrap bare Para in JSEK本文 Div,
--- recurse into Divs without custom-style, skip Divs with custom-style.
process_blocks = function(blocks)
  local result = pandoc.List()
  for _, block in ipairs(blocks) do
    if block.t == "Para" then
      result:insert(pandoc.Div(block, pandoc.Attr("", {}, {{"custom-style", "JSEK本文"}})))
    elseif block.t == "Div" then
      if block.classes:includes("textbox") then
        -- .textbox Div — emit markers
        result:extend(process_textbox(block))
      elseif block.classes:includes("grid") then
        -- .grid Div — emit GRID_TABLE marker to preserve full borders
        result:insert(textbox_marker("GRID_TABLE"))
        local inner = process_blocks(block.content)
        result:extend(inner)
      elseif has_custom_style(block) then
        -- Already styled — keep entire subtree as-is
        result:insert(block)
      else
        -- No custom-style — recurse into children
        block.content = process_blocks(block.content)
        result:insert(block)
      end
    elseif block.t == "OrderedList" then
      -- Convert to manually-numbered paragraphs with compact ListNumber style
      local start_num = block.listAttributes.start
      for i, item in ipairs(block.content) do
        local num = start_num + i - 1
        for j, blk in ipairs(item) do
          if j == 1 and (blk.t == "Para" or blk.t == "Plain") then
            blk.content:insert(1, pandoc.Str(tostring(num) .. ". "))
            result:insert(pandoc.Div(
              pandoc.Para(blk.content),
              pandoc.Attr("", {}, {{"custom-style", "ListNumber"}})
            ))
          else
            local processed = process_blocks(pandoc.List({blk}))
            result:extend(processed)
          end
        end
      end
    else
      -- Header, Table, CodeBlock, BulletList, etc. — pass through
      result:insert(block)
    end
  end
  return result
end

return {
  -- Pass 1: Rewrite SVG image paths to .svg.png
  { Image = function(img)
      if img.src:match("%.svg$") then
        img.src = img.src .. ".png"
      end
      return img
    end
  },
  -- Pass 2: Process blocks (JSEK本文 wrapping, textbox markers, etc.)
  { Pandoc = function(doc)
      doc.blocks = process_blocks(doc.blocks)
      return doc
    end
  },
}
