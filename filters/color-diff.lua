-- color-diff.lua: Convert .diff-add / .diff-del spans to colored OOXML
-- Only active for docx output

if FORMAT ~= "docx" then
  return {}
end

--- Escape XML special characters
local function xml_escape(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  return s
end

--- Convert inline elements to plain text
local function inlines_to_text(inlines)
  local parts = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      parts[#parts + 1] = inline.text
    elseif inline.t == "Space" then
      parts[#parts + 1] = " "
    elseif inline.t == "SoftBreak" then
      parts[#parts + 1] = " "
    elseif inline.t == "LineBreak" then
      parts[#parts + 1] = "\n"
    else
      -- Fallback: use pandoc.utils.stringify for other inlines
      parts[#parts + 1] = pandoc.utils.stringify(inline)
    end
  end
  return table.concat(parts)
end

--- Build an OOXML <w:r> element with given run properties and text
local function make_ooxml_run(text, rpr_xml)
  local escaped = xml_escape(text)
  return string.format(
    '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>',
    rpr_xml, escaped
  )
end

function Span(el)
  if el.classes:includes("diff-add") then
    local text = inlines_to_text(el.content)
    local rpr = '<w:rPr><w:color w:val="2E74B5"/></w:rPr>'
    return pandoc.RawInline("openxml", make_ooxml_run(text, rpr))
  elseif el.classes:includes("diff-del") then
    local text = inlines_to_text(el.content)
    local rpr = '<w:rPr><w:color w:val="C00000"/><w:strike/></w:rPr>'
    return pandoc.RawInline("openxml", make_ooxml_run(text, rpr))
  end
end
