-- =========================================================
-- poster.lua (Betterland v1)
-- =========================================================

local key_div = nil
local branding_div = nil

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function has_class(div, class)
  for _, c in ipairs(div.classes) do
    if c == class then return true end
  end
  return false
end

local function stringify(x)
  if x == nil then return "" end
  return pandoc.utils.stringify(x)
end

------------------------------------------------------------
-- Detect key + branding (DO NOT REMOVE)
------------------------------------------------------------

function Div(div)

  if not key_div and has_class(div, "key-message") then
    key_div = div
  end

  if not branding_div and has_class(div, "branding") then
    branding_div = div
  end

  return div
end

------------------------------------------------------------
-- Metadata block
------------------------------------------------------------

local function is_metalist(x) return x and x.t == "MetaList" end
local function is_metamap(x)  return x and x.t == "MetaMap"  end
local function is_metastring(x) return x and x.t == "MetaString" end
local function is_metainlines(x) return x and x.t == "MetaInlines" end

local function meta_to_string(x)
  if x == nil then return "" end
  return pandoc.utils.stringify(x)
end

local function as_number_list(meta_val)
  -- accepts MetaList of numbers/strings OR a single value
  local out = {}
  if meta_val == nil then return out end
  if is_metalist(meta_val) then
    for _, v in ipairs(meta_val) do
      local s = meta_to_string(v)
      if s ~= "" then table.insert(out, s) end
    end
  else
    local s = meta_to_string(meta_val)
    if s ~= "" then table.insert(out, s) end
  end
  return out
end

local function superscripts(nums)
  -- nums: array of strings like {"1","2"}
  if #nums == 0 then return {} end
  local inlines = { pandoc.Superscript({ pandoc.Str(table.concat(nums, ",")) }) }
  return inlines
end

local function parse_authors(meta)
  -- returns array of author objects: {name="", affil_nums={}, main=false, email="", orcid="", twitter="", github="", website=""}
  local a = meta.author
  local authors = {}

  if a == nil then return authors end

  if is_metalist(a) then
    for _, item in ipairs(a) do
      if is_metamap(item) then
        local obj = {
          name = meta_to_string(item.name) ~= "" and meta_to_string(item.name) or meta_to_string(item),
          affil_nums = as_number_list(item.affil),
          main = (meta_to_string(item.main) == "true" or meta_to_string(item.main) == "TRUE"),
          email = meta_to_string(item.email),
          orcid = meta_to_string(item.orcid),
          twitter = meta_to_string(item.twitter),
          github = meta_to_string(item.github),
          website = meta_to_string(item.website),
        }
        table.insert(authors, obj)
      else
        table.insert(authors, { name = meta_to_string(item), affil_nums = {}, main = true })
      end
    end
  else
    -- single author string
    table.insert(authors, { name = meta_to_string(a), affil_nums = {}, main = true })
  end

  -- if none marked main, treat all as main
  local any_main = false
  for _, au in ipairs(authors) do
    if au.main then any_main = true break end
  end
  if not any_main then
    for _, au in ipairs(authors) do au.main = true end
  end

  return authors
end

local function parse_affiliations(meta)
  -- returns array of {num="1", address="..."} or from simple list
  local aff = meta.affiliation
  local out = {}

  if aff == nil then return out end

  if is_metalist(aff) then
    for i, item in ipairs(aff) do
      if is_metamap(item) then
        local num = meta_to_string(item.num)
        local address = meta_to_string(item.address)
        if num == "" then num = tostring(i) end
        table.insert(out, { num = num, address = address })
      else
        -- simple list
        table.insert(out, { num = tostring(i), address = meta_to_string(item) })
      end
    end
  else
    -- single string
    table.insert(out, { num = "1", address = meta_to_string(aff) })
  end

  return out
end

local function author_line(authors, want_main)
  -- returns inlines for main or coauthors line
  local inlines = {}
  local first = true
  for _, au in ipairs(authors) do
    if (want_main and au.main) or ((not want_main) and (not au.main)) then
      if not first then 
        table.insert(inlines, pandoc.Str(", ")) 
        table.insert(inlines, pandoc.Space())
      end
      first = false

      table.insert(inlines, pandoc.Str(au.name))
      local sups = superscripts(au.affil_nums)
      if #sups > 0 then
         table.insert(inlines, pandoc.Str(""))
         for _, s in ipairs(sups) do
           table.insert(inlines, s)
         end
      end
    end
  end
  return inlines
end

local function contact_inlines_for_author(au)
  local parts = {}

  local function add_text(txt)
    if txt and txt ~= "" then
      if #parts > 0 then table.insert(parts, pandoc.Str(" · ")) end
      table.insert(parts, pandoc.Str(txt))
    end
  end

  local function add_link(label, href)
    if label and label ~= "" and href and href ~= "" then
      if #parts > 0 then table.insert(parts, pandoc.Str(" · ")) end
      table.insert(parts, pandoc.Link(label, href))
    end
  end

  -- email (as plain text to avoid mailto policies if you prefer; can be mailto:)
  if au.email and au.email ~= "" then
    add_link(au.email, "mailto:" .. au.email)
  end

  -- website
  if au.website and au.website ~= "" then
    add_link(au.website, au.website)
  end

  -- ORCID
  if au.orcid and au.orcid ~= "" then
    add_link("ORCID:" .. au.orcid, "https://orcid.org/" .. au.orcid)
  end

  -- twitter
  if au.twitter and au.twitter ~= "" then
    local handle = au.twitter
    if handle:sub(1,1) ~= "@" then handle = "@" .. handle end
    add_link(handle, "https://twitter.com/" .. au.twitter:gsub("^@", ""))
  end

  -- github
  if au.github and au.github ~= "" then
    local user = au.github:gsub("^@", "")
    add_link("@" .. user, "https://github.com/" .. user)
  end

  return parts
end

local function contacts_block(authors)
  -- Build one or more lines, for MAIN authors only
  local blocks = {}
  for _, au in ipairs(authors) do
    if au.main then
      local inlines = contact_inlines_for_author(au)
      if #inlines > 0 then
        table.insert(blocks, pandoc.Para({ pandoc.Span(inlines, pandoc.Attr("", {"poster-meta__contacts"})) }))
      end
    end
  end
  if #blocks == 0 then return nil end
  return pandoc.Div(blocks, pandoc.Attr("", {"poster-meta__contacts-wrap"}))
end


local function affiliations_block(affs)
  -- <p><sup>1</sup> Address<br>...</p>
  if #affs == 0 then return nil end
  local inlines = {}
  for i, a in ipairs(affs) do
    table.insert(inlines, pandoc.Superscript({ pandoc.Str(a.num) }))
    table.insert(inlines, pandoc.Space())
    table.insert(inlines, pandoc.Str(a.address))
    if i < #affs then
      table.insert(inlines, pandoc.LineBreak())
    end
  end
  return pandoc.Para({ pandoc.Span(inlines, pandoc.Attr("", {"poster-meta__affiliations"})) })
end

local function make_meta_block(meta)
  local blocks = {}

  if meta.title then
    table.insert(
      blocks,
      pandoc.Header(
        1,
        { pandoc.Str(meta_to_string(meta.title)) },
        pandoc.Attr("", {"poster-meta__title"})
      )
    )
  end

  if meta.subtitle then
    table.insert(
      blocks,
      pandoc.Para({
        pandoc.Span(
          { pandoc.Str(meta_to_string(meta.subtitle)) },
          pandoc.Attr("", {"poster-meta__subtitle"})
        )
      })
    )
  end

  local authors = parse_authors(meta)
  local main_line = author_line(authors, true)
  if #main_line > 0 then
    table.insert(blocks, pandoc.Para({ pandoc.Span(main_line, pandoc.Attr("", {"poster-meta__authors"})) }))
  end

  local co_line = author_line(authors, false)
  if #co_line > 0 then
    table.insert(blocks, pandoc.Para({ pandoc.Span(co_line, pandoc.Attr("", {"poster-meta__coauthors"})) }))
  end

  local contacts = contacts_block(authors)
  if contacts then table.insert(blocks, contacts) end

  local affs = parse_affiliations(meta)
  local aff_block = affiliations_block(affs)
  if aff_block then table.insert(blocks, aff_block) end

  return pandoc.Div(blocks, pandoc.Attr("", {"poster-meta"}))
end


------------------------------------------------------------
-- Build final layout
------------------------------------------------------------

function Pandoc(doc)

  local before = {}
  local after = {}
  local seen_key = false

  for _, block in ipairs(doc.blocks) do

    if key_div and block == key_div then
      seen_key = true
    elseif branding_div and block == branding_div then
      -- skip (handled separately)
    else
      if not seen_key then
        table.insert(before, block)
      else
        table.insert(after, block)
      end
    end

  end

  local meta_block = make_meta_block(doc.meta)

  local left_col = pandoc.Div(
    { meta_block, pandoc.Div(before, pandoc.Attr("", {"poster-flow"})) },
    pandoc.Attr("", {"poster-left"})
  )

  local key_block
  if key_div then
    key_block = pandoc.Div(key_div.content, pandoc.Attr("", {"poster-key"}))
  else
    key_block = pandoc.Div(
      { pandoc.Para({ pandoc.Str("Missing key message") }) },
      pandoc.Attr("", {"poster-key", "poster-key--missing"})
    )
  end

  local branding_block
  if branding_div then
    branding_block = pandoc.Div(branding_div.content, pandoc.Attr("", {"poster-branding"}))
  else
    branding_block = pandoc.Div({}, pandoc.Attr("", {"poster-branding"}))
  end

  local center_col = pandoc.Div(
    { key_block, branding_block },
    pandoc.Attr("", {"poster-center"})
  )

  local right_col = pandoc.Div(
    { pandoc.Div(after, pandoc.Attr("", {"poster-flow"})) },
    pandoc.Attr("", {"poster-right"})
  )

  local layout = pandoc.Div(
    { left_col, center_col, right_col },
    pandoc.Attr("", {"poster__grid"})
  )

  doc.blocks = { layout }
  return doc
end
