-- =========================================================
-- poster.lua — Betterland Poster
--
-- Responsibilities (five only):
--   1. Parse poster.authors + poster.affiliations from YAML
--      → build poster_header MetaBlocks (author group,
--        affiliation group, contact group)
--   2. Extract .poster-left div  → doc.meta.poster_left
--   3. Extract .poster-right div → doc.meta.poster_right
--   4. Extract .poster-extras div (optional)
--      → doc.meta.poster_extras
--   5. Clear doc.blocks — template.html owns all structure,
--      $body$ is intentionally unused.
--
-- The template handles directly from YAML:
--   $title$, $subtitle$, $poster.main_finding$,
--   $poster.qrcode$, $poster.logo_left$, $poster.logo_right$
-- =========================================================


-- ---------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------

-- Safely stringify any pandoc metadata value.
local function stringify(x)
  if x == nil then return "" end
  return pandoc.utils.stringify(x)
end

-- Test whether a block element has a given CSS class.
local function has_class(el, name)
  if not el or not el.classes then return false end
  for _, c in ipairs(el.classes) do
    if c == name then return true end
  end
  return false
end

-- Parse a markdown string into a list of Inline elements.
-- Useful for author names that may contain bold/italic markup.
local function text_to_inlines(text)
  if text == nil or text == "" then return {} end
  local doc = pandoc.read(text, "markdown")
  if #doc.blocks > 0 then
    local first = doc.blocks[1]
    if first.t == "Para" or first.t == "Plain" then
      return first.content
    end
  end
  return { pandoc.Str(text) }
end

-- Join a list of inline lists with a separator inline list.
-- Used to produce "Author A, Author B, Author C".
local function intersperse_inlines(items, sep)
  local out = {}
  for i, item in ipairs(items) do
    if i > 1 then
      for _, s in ipairs(sep) do table.insert(out, s) end
    end
    for _, inl in ipairs(item) do table.insert(out, inl) end
  end
  return out
end

-- Build a superscript inline from a list of affiliation numbers.
local function superscript_inlines(nums)
  if not nums or #nums == 0 then return {} end
  return { pandoc.Superscript({ pandoc.Str(table.concat(nums, ",")) }) }
end

-- Test whether a metadata value is a list type.
local function is_metalist(x)
  if x == nil then return false end
  local t = pandoc.utils.type(x)
  return t == "List" or t == "MetaList"
end

-- Test whether a metadata value is a map/table type.
local function is_metamap(x)
  if x == nil then return false end
  local t = pandoc.utils.type(x)
  return t == "Map" or t == "MetaMap"
end

-- Safely convert a metadata value to a list of strings.
local function as_string_list(val)
  local out = {}
  if val == nil then return out end
  if is_metalist(val) then
    for _, v in ipairs(val) do
      local s = stringify(v)
      if s ~= "" then table.insert(out, s) end
    end
  else
    local s = stringify(val)
    if s ~= "" then table.insert(out, s) end
  end
  return out
end

-- Test whether a block is a references section.
-- Matches either id="references" or a heading with text "References".
local function is_references_section(block)
  if not block then return false end
  if block.identifier == "references" then return true end
  if block.t == "Div" and #block.content > 0 then
    local first = block.content[1]
    if first and first.t == "Header" then
      return stringify(first.content):lower() == "references"
    end
  end
  return false
end


-- ---------------------------------------------------------
-- METADATA PARSING
-- poster.authors and poster.affiliations from YAML
-- ---------------------------------------------------------

local function parse_authors(meta)
  local raw = meta.poster and meta.poster.authors or meta.author
  local authors = {}

  if raw == nil then return authors end

  local function parse_one(item)
    local is_rich = is_metamap(item) or (
      type(item) == "table" and (
        item.name ~= nil or item.affil ~= nil or
        item.email ~= nil or item.orcid ~= nil or
        item.github ~= nil or item.website ~= nil
      )
    )

    if is_rich then
      local main_val = stringify(item.main):lower()
      table.insert(authors, {
        name       = stringify(item.name) ~= "" and stringify(item.name) or stringify(item),
        affil_nums = as_string_list(item.affil),
        main       = (main_val == "true" or main_val == "yes" or main_val == "1"),
        email      = stringify(item.email),
        orcid      = stringify(item.orcid),
        github     = stringify(item.github),
        website    = stringify(item.website),
      })
    else
      -- Plain string author — treat as main author, no extras
      table.insert(authors, {
        name       = stringify(item),
        affil_nums = {},
        main       = true,
        email      = "", orcid  = "",
        github     = "", website = "",
      })
    end
  end

  if is_metalist(raw) then
    for _, item in ipairs(raw) do parse_one(item) end
  else
    parse_one(raw)
  end

  -- If no author is marked main, mark all as main
  local any_main = false
  for _, au in ipairs(authors) do
    if au.main then any_main = true; break end
  end
  if not any_main then
    for _, au in ipairs(authors) do au.main = true end
  end

  return authors
end


local function parse_affiliations(meta)
  local raw = meta.poster and meta.poster.affiliations or meta.affiliation
  local out = {}

  if raw == nil then return out end

  if is_metalist(raw) then
    for i, item in ipairs(raw) do
      if type(item) == "table" and (item.num ~= nil or item.address ~= nil) then
        local num = stringify(item.num)
        if num == "" then num = tostring(i) end
        table.insert(out, { num = num, address = stringify(item.address) })
      else
        table.insert(out, { num = tostring(i), address = stringify(item) })
      end
    end
  else
    table.insert(out, { num = "1", address = stringify(raw) })
  end

  return out
end


-- ---------------------------------------------------------
-- HEADER BLOCK BUILDERS
-- Produce pandoc AST blocks for the $poster_header$ slot.
-- Title and subtitle are handled by the template directly.
-- This builds: author group, affiliation group, contact group.
-- ---------------------------------------------------------

-- "Author A^1^, Author B^1,2^" and co-author line below
local function build_author_group(authors)
  if #authors == 0 then return nil end

  local main_inlines = {}
  local co_inlines   = {}

  for _, au in ipairs(authors) do
    local name_inlines = text_to_inlines(au.name)
    local sup = superscript_inlines(au.affil_nums)
    for _, s in ipairs(sup) do table.insert(name_inlines, s) end

    if au.main then
      -- Inline contact: Name¹ (email · @github)
      local contact_items = {}
      if au.email ~= "" then
        table.insert(contact_items, pandoc.Link(
          { pandoc.Str(au.email) }, "mailto:" .. au.email
        ))
      end
      if au.github ~= "" then
        local handle = au.github:gsub("^@", "")
        table.insert(contact_items, pandoc.Link(
          { pandoc.Str("@" .. handle) }, "https://github.com/" .. handle
        ))
      end
      if #contact_items > 0 then
        local sep = { pandoc.Space(), pandoc.Str("·"), pandoc.Space() }
        table.insert(name_inlines, pandoc.Space())
        table.insert(name_inlines, pandoc.Str("("))
        for i, item in ipairs(contact_items) do
          if i > 1 then
            for _, s in ipairs(sep) do table.insert(name_inlines, s) end
          end
          table.insert(name_inlines, item)
        end
        table.insert(name_inlines, pandoc.Str(")"))
      end
      table.insert(main_inlines, name_inlines)
    else
      table.insert(co_inlines, name_inlines)
    end
  end

  local blocks = {}
  local sep = { pandoc.Str(","), pandoc.Space() }

  if #main_inlines > 0 then
    table.insert(blocks, pandoc.Div(
      { pandoc.Para(intersperse_inlines(main_inlines, sep)) },
      pandoc.Attr("", { "poster-authors" })
    ))
  end

  if #co_inlines > 0 then
    table.insert(blocks, pandoc.Div(
      { pandoc.Para(intersperse_inlines(co_inlines, sep)) },
      pandoc.Attr("", { "poster-coauthors" })
    ))
  end

  if #blocks == 0 then return nil end
  return pandoc.Div(blocks, pandoc.Attr("", { "poster-author-group" }))
end


-- "^1^ Institution Name" list
local function build_affiliation_group(affs)
  if #affs == 0 then return nil end

  local blocks = {}
  for _, aff in ipairs(affs) do
    local inlines = { pandoc.Superscript({ pandoc.Str(aff.num) }), pandoc.Space() }
    for _, inl in ipairs(text_to_inlines(aff.address)) do
      table.insert(inlines, inl)
    end
    table.insert(blocks, pandoc.Div(
      { pandoc.Para(inlines) },
      pandoc.Attr("", { "poster-affiliation-item" })
    ))
  end

  return pandoc.Div(blocks, pandoc.Attr("", { "poster-affiliation-group" }))
end


-- Contact links for main authors: email · github · orcid · website
local function build_contact_group(authors)
  local blocks = {}

  for _, au in ipairs(authors) do
    if au.main then
      local items = {}

      if au.email ~= "" then
        table.insert(items, pandoc.Link(
          { pandoc.Str(au.email) }, "mailto:" .. au.email
        ))
      end
      if au.github ~= "" then
        local handle = au.github:gsub("^@", "")
        table.insert(items, pandoc.Link(
          { pandoc.Str("@" .. handle) }, "https://github.com/" .. handle
        ))
      end
      if au.orcid ~= "" then
        table.insert(items, pandoc.Link(
          { pandoc.Str("ORCID: " .. au.orcid) },
          "https://orcid.org/" .. au.orcid
        ))
      end
      if au.website ~= "" then
        table.insert(items, pandoc.Link(
          { pandoc.Str(au.website) }, au.website
        ))
      end

      if #items > 0 then
        -- Join with " · " separator
        local sep = { pandoc.Space(), pandoc.Str("·"), pandoc.Space() }
        table.insert(blocks, pandoc.Div(
          { pandoc.Para(intersperse_inlines(items, sep)) },
          pandoc.Attr("", { "poster-contact-line" })
        ))
      end
    end
  end

  if #blocks == 0 then return nil end
  return pandoc.Div(blocks, pandoc.Attr("", { "poster-contact-group" }))
end


-- Assemble the full poster_header MetaBlocks:
-- author group + affiliation group + contact group
-- (title/subtitle are placed by the template directly)
local function build_poster_header(meta)
  local authors = parse_authors(meta)
  local affs    = parse_affiliations(meta)
  local blocks  = {}

  local author_group = build_author_group(authors)
  if author_group then table.insert(blocks, author_group) end

  local affil_group = build_affiliation_group(affs)
  if affil_group then table.insert(blocks, affil_group) end

  --- local contact_group = build_contact_group(authors)
  --- if contact_group then table.insert(blocks, contact_group) end

  return blocks
end


-- ---------------------------------------------------------
-- CONTENT EXTRACTION
-- Find named divs in doc.blocks and return their contents.
-- Simple, explicit, no position-based routing logic.
-- ---------------------------------------------------------

-- Add poster-references CSS class to references sections
-- so the CSS can style them with smaller type.
local function decorate_references(blocks)
  local out = {}
  for _, block in ipairs(blocks) do
    if is_references_section(block) then
      if block.attr then
        local classes = {}
        for _, c in ipairs(block.attr.classes or {}) do
          table.insert(classes, c)
        end
        local already = false
        for _, c in ipairs(classes) do
          if c == "poster-references" then already = true; break end
        end
        if not already then
          table.insert(classes, "poster-references")
          block.attr = pandoc.Attr(
            block.attr.identifier or "",
            classes,
            block.attr.attributes or {}
          )
        end
      end
    end
    table.insert(out, block)
  end
  return out
end

local function extract_div_by_class(blocks, class_name)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and has_class(block, class_name) then
      return block.content
    end
  end
  return nil
end


-- ---------------------------------------------------------
-- MAIN TRANSFORMATION
-- ---------------------------------------------------------

function Pandoc(doc)

  -- 1. Build poster_header from YAML metadata
  local header_blocks = build_poster_header(doc.meta)
  if #header_blocks > 0 then
    doc.meta.poster_header = pandoc.MetaBlocks(header_blocks)
  end

  -- 2. Extract .poster-left content
  local left_blocks = extract_div_by_class(doc.blocks, "poster-left")
  if left_blocks then
    doc.meta.poster_left = pandoc.MetaBlocks(left_blocks)
  end

  -- 3. Extract .poster-right content
  --    Decorate any references section for CSS styling
  local right_blocks = extract_div_by_class(doc.blocks, "poster-right")
  if right_blocks then
    doc.meta.poster_right = pandoc.MetaBlocks(
      decorate_references(right_blocks)
    )
  end

  -- 4. Extract .poster-extras content (optional)
  --    Placed in Zone B of the center column if present.
  local extras_blocks = extract_div_by_class(doc.blocks, "poster-extras")
  if extras_blocks then
    doc.meta.poster_extras = pandoc.MetaBlocks(extras_blocks)
  end

  -- 5. Clear doc.blocks — template.html owns all structural HTML.
  --    $body$ in the template is intentionally empty.
  doc.blocks = {}

  return doc
end