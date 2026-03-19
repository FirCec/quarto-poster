-- =========================================================
-- poster.lua (Betterland v2 - cleaned MVP baseline)
-- =========================================================

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

local function stringify(x)
  if x == nil then
    return ""
  end
  return pandoc.utils.stringify(x)
end

local function has_class(el, class_name)
  if not el or not el.classes then
    return false
  end
  for _, c in ipairs(el.classes) do
    if c == class_name then
      return true
    end
  end
  return false
end

local function clone_classes(classes)
  local out = {}
  if not classes then
    return out
  end
  for _, c in ipairs(classes) do
    table.insert(out, c)
  end
  return out
end

local function append_class(attr, class_name)
  local id = attr.identifier or ""
  local classes = clone_classes(attr.classes or {})
  local attrs = attr.attributes or {}

  local already = false
  for _, c in ipairs(classes) do
    if c == class_name then
      already = true
      break
    end
  end

  if not already then
    table.insert(classes, class_name)
  end

  return pandoc.Attr(id, classes, attrs)
end

local function intersperse_inlines(items, sep)
  local out = {}
  for i, item in ipairs(items) do
    if i > 1 then
      for _, s in ipairs(sep) do
        table.insert(out, s)
      end
    end
    for _, inline in ipairs(item) do
      table.insert(out, inline)
    end
  end
  return out
end

local function text_equals_ci(a, b)
  return stringify(a):lower() == tostring(b):lower()
end

local function text_to_inlines(text)
  if text == nil or text == "" then
    return {}
  end

  local doc = pandoc.read(text, "markdown")
  if #doc.blocks > 0 then
    local first = doc.blocks[1]
    if first.t == "Para" or first.t == "Plain" then
      return first.content
    end
  end

  return { pandoc.Str(text) }
end

local function is_spacing_inline(inl)
  return inl
    and (inl.t == "Space" or inl.t == "SoftBreak" or inl.t == "LineBreak")
end

local function extract_images_from_image_paragraph(block)
  if not block or (block.t ~= "Para" and block.t ~= "Plain") then
    return nil
  end

  local images = {}

  for _, inl in ipairs(block.content) do
    if inl.t == "Image" then
      table.insert(images, inl)
    elseif not is_spacing_inline(inl) then
      return nil
    end
  end

  if #images == 0 then
    return nil
  end

  return images
end

local function build_resource_item_from_image(img)
  local classes = { "poster-resource-item" }

  if has_class(img, "qr") then
    table.insert(classes, "poster-resource-item--qr")
  end

  if has_class(img, "logo") then
    table.insert(classes, "poster-resource-item--logo")
  end

  return pandoc.Div(
    { pandoc.Plain({ img }) },
    pandoc.Attr("", classes)
  )
end

local function normalize_image_paragraphs(blocks)
  local normalized = {}
  local row_items = {}

  for _, block in ipairs(blocks or {}) do
    local imgs = extract_images_from_image_paragraph(block)

    if imgs then
      for _, img in ipairs(imgs) do
        table.insert(row_items, build_resource_item_from_image(img))
      end
    else
      table.insert(normalized, block)
    end
  end

  if #row_items > 0 then
    table.insert(
      normalized,
      1,
      pandoc.Div(row_items, pandoc.Attr("", { "poster-resource-row" }))
    )
  end

  return normalized
end

local function escape_html(s)
  if s == nil then
    return ""
  end
  s = tostring(s)
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  s = s:gsub('"', "&quot;")
  return s
end

local function is_references_section(block)
  if not block then
    return false
  end

  if block.identifier == "references" then
    return true
  end

  if block.t == "Div" and #block.content > 0 then
    local first = block.content[1]
    if first and first.t == "Header" and text_equals_ci(first.content, "references") then
      return true
    end
  end

  return false
end


local function get_poster_authors_meta(meta)
  if meta.poster and meta.poster.authors ~= nil then
    return meta.poster.authors
  end
  return meta.author
end

local function get_poster_affiliations_meta(meta)
  if meta.poster and meta.poster.affiliations ~= nil then
    return meta.poster.affiliations
  end
  return meta.affiliation
end

-- ---------------------------------------------------------
-- Metadata parsing
-- ---------------------------------------------------------

local function meta_type(x)
  if x == nil then
    return nil
  end
  return pandoc.utils.type(x)
end

local function is_metalist(x)
  local t = meta_type(x)
  return t == "List" or t == "MetaList"
end

local function is_metamap(x)
  local t = meta_type(x)
  return t == "Map" or t == "MetaMap"
end

local function meta_to_string(x)
  return stringify(x)
end

local function as_string_list(meta_val)
  local out = {}

  if meta_val == nil then
    return out
  end

  if is_metalist(meta_val) then
    for _, v in ipairs(meta_val) do
      local s = meta_to_string(v)
      if s ~= "" then
        table.insert(out, s)
      end
    end
  else
    local s = meta_to_string(meta_val)
    if s ~= "" then
      table.insert(out, s)
    end
  end

  return out
end

local function parse_authors(meta)
  local a = get_poster_authors_meta(meta)
  local authors = {}

  if a == nil then
    return authors
  end

  if is_metalist(a) then
    for _, item in ipairs(a) do
-- WITH THIS:
      local item_is_rich = is_metamap(item) or (
        type(item) == "table" and (
          item.name ~= nil or item.affil ~= nil or
          item.email ~= nil or item.orcid ~= nil or
          item.twitter ~= nil or item.github ~= nil or
          item.website ~= nil
        )
      )

      if item_is_rich then
        local obj = {
          name = meta_to_string(item.name) ~= "" and meta_to_string(item.name) or meta_to_string(item),
          affil_nums = as_string_list(item.affil),
          main = false,
          email = meta_to_string(item.email),
          orcid = meta_to_string(item.orcid),
          twitter = meta_to_string(item.twitter),
          github = meta_to_string(item.github),
          website = meta_to_string(item.website)
        }

        local main_value = meta_to_string(item.main):lower()
        obj.main = (main_value == "true" or main_value == "yes" or main_value == "1")

        table.insert(authors, obj)
      else
        table.insert(authors, {
          name = meta_to_string(item),
          affil_nums = {},
          main = true,
          email = "",
          orcid = "",
          twitter = "",
          github = "",
          website = ""
        })
      end
    end
  else
    table.insert(authors, {
      name = meta_to_string(a),
      affil_nums = {},
      main = true,
      email = "",
      orcid = "",
      twitter = "",
      github = "",
      website = ""
    })
  end

  local any_main = false
  for _, au in ipairs(authors) do
    if au.main then
      any_main = true
      break
    end
  end

  if not any_main then
    for _, au in ipairs(authors) do
      au.main = true
    end
  end

  return authors
end

local function parse_affiliations(meta)
  local aff = get_poster_affiliations_meta(meta)
  local out = {}

  if aff == nil then
    return out
  end

  if is_metalist(aff) then
    for i, item in ipairs(aff) do
      if type(item) == "table" and (item.num ~= nil or item.address ~= nil) then
        local num = meta_to_string(item.num)
        local address = meta_to_string(item.address)

        if num == "" then
          num = tostring(i)
        end

        table.insert(out, {
          num = num,
          address = address
        })
      else
        table.insert(out, {
          num = tostring(i),
          address = meta_to_string(item)
        })
      end
    end
  else
    table.insert(out, {
      num = "1",
      address = meta_to_string(aff)
    })
  end

  return out
end

-- ---------------------------------------------------------
-- Metadata rendering
-- ---------------------------------------------------------

local function superscript_inlines(nums)
  if not nums or #nums == 0 then
    return {}
  end

  return {
    pandoc.Superscript({
      pandoc.Str(table.concat(nums, ","))
    })
  }
end

local function author_name_inlines(author)
  local inlines = text_to_inlines(author.name)
  local sups = superscript_inlines(author.affil_nums)

  for _, s in ipairs(sups) do
    table.insert(inlines, s)
  end

  return inlines
end

local function build_author_group(authors)
  if #authors == 0 then
    return nil
  end

  local main_authors = {}
  local coauthors = {}

  for _, au in ipairs(authors) do
    local author_inlines = author_name_inlines(au)
    if au.main then
      table.insert(main_authors, author_inlines)
    else
      table.insert(coauthors, author_inlines)
    end
  end

  local blocks = {}

  if #main_authors > 0 then
    local para = pandoc.Para(
      intersperse_inlines(main_authors, { pandoc.Str(","), pandoc.Space() })
    )
    table.insert(blocks, pandoc.Div({ para }, pandoc.Attr("", { "poster-authors" })))
  end

  if #coauthors > 0 then
    local para = pandoc.Para(
      intersperse_inlines(coauthors, { pandoc.Str(","), pandoc.Space() })
    )
    table.insert(blocks, pandoc.Div({ para }, pandoc.Attr("", { "poster-coauthors" })))
  end

  if #blocks == 0 then
    return nil
  end

  return pandoc.Div(blocks, pandoc.Attr("", { "poster-author-group" }))
end

local function build_affiliation_group(affs)
  if #affs == 0 then
    return nil
  end

  local blocks = {}

  for _, aff in ipairs(affs) do
    local inlines = {
      pandoc.Superscript({ pandoc.Str(aff.num) }),
      pandoc.Space()
    }

    for _, inline in ipairs(text_to_inlines(aff.address)) do
      table.insert(inlines, inline)
    end

    local para = pandoc.Para(inlines)

    table.insert(
      blocks,
      pandoc.Div({ para }, pandoc.Attr("", { "poster-affiliation-item" }))
    )
  end

  return pandoc.Div(blocks, pandoc.Attr("", { "poster-affiliation-group" }))
end

local function contact_link(label, href)
  return pandoc.Link(label, href)
end

local function contact_items_for_author(author)
  local out = {}

  if author.email ~= "" then
    table.insert(out, contact_link(author.email, "mailto:" .. author.email))
  end

  if author.website ~= "" then
    table.insert(out, contact_link(author.website, author.website))
  end

  if author.orcid ~= "" then
    table.insert(out, contact_link("ORCID: " .. author.orcid, "https://orcid.org/" .. author.orcid))
  end

  if author.twitter ~= "" then
    local handle = author.twitter:gsub("^@", "")
    table.insert(out, contact_link("@" .. handle, "https://twitter.com/" .. handle))
  end

  if author.github ~= "" then
    local user = author.github:gsub("^@", "")
    table.insert(out, contact_link("@" .. user, "https://github.com/" .. user))
  end

  return out
end

local function build_contact_group(authors)
  local blocks = {}

  for _, au in ipairs(authors) do
    if au.main then
      local items = contact_items_for_author(au)

      if #items > 0 then
        local inlines = {}
        for i, item in ipairs(items) do
          if i > 1 then
            table.insert(inlines, pandoc.Space())
            table.insert(inlines, pandoc.Str("·"))
            table.insert(inlines, pandoc.Space())
          end
          table.insert(inlines, item)
        end

        local para = pandoc.Para(inlines)
        table.insert(
          blocks,
          pandoc.Div({ para }, pandoc.Attr("", { "poster-contact-line" }))
        )
      end
    end
  end

  if #blocks == 0 then
    return nil
  end

  return pandoc.Div(blocks, pandoc.Attr("", { "poster-contact-group" }))
end

local function build_header(meta)
  local blocks = {}
  local title = meta_to_string(meta.title)
  local subtitle = meta_to_string(meta.subtitle)

  local title_group_blocks = {}

  if title ~= "" then
    table.insert(
      title_group_blocks,
      pandoc.RawBlock("html", '<h1 class="poster-title">' .. escape_html(title) .. '</h1>')
    )
  end

  if subtitle ~= "" then
    table.insert(
      title_group_blocks,
      pandoc.RawBlock("html", '<p class="poster-subtitle">' .. escape_html(subtitle) .. '</p>')
    )
  end

  if #title_group_blocks > 0 then
    table.insert(
      blocks,
      pandoc.Div(title_group_blocks, pandoc.Attr("", { "poster-title-group" }))
    )
  end

  local authors = parse_authors(meta)
  local affs = parse_affiliations(meta)

  local author_group = build_author_group(authors)
  if author_group then
    table.insert(blocks, author_group)
  end

  local affiliation_group = build_affiliation_group(affs)
  if affiliation_group then
    table.insert(blocks, affiliation_group)
  end

  local contact_group = build_contact_group(authors)
  if contact_group then
    table.insert(blocks, contact_group)
  end

  return pandoc.Div(
    blocks,
    pandoc.Attr("poster-header", { "poster-header" }, {
      ["role"] = "banner",
      ["aria-label"] = "Poster header"
    })
  )
end

-- ---------------------------------------------------------
-- Region builders
-- ---------------------------------------------------------

local function build_key_region(key_div)
  if not key_div then
    return pandoc.Div(
      {
        pandoc.Div(
          { pandoc.Para({ pandoc.Str("Missing key message") }) },
          pandoc.Attr("", { "poster-key-main" })
        )
      },
      pandoc.Attr("poster-key-region", { "poster-key-region", "poster-key-region--missing" }, {
        ["role"] = "region",
        ["aria-label"] = "Key message"
      })
    )
  end

  local blocks = {}
  local paras = {}
  local others = {}

  for _, block in ipairs(key_div.content) do
    if block.t == "Para" or block.t == "Plain" then
      table.insert(paras, block)
    else
      table.insert(others, block)
    end
  end

  if #paras >= 1 then
    table.insert(
      blocks,
      pandoc.Div(
        { pandoc.Para(paras[1].content) },
        pandoc.Attr("", { "poster-key-main" })
      )
    )
  end

  local extra_blocks = {}

  if #paras > 1 then
    for i = 2, #paras do
      table.insert(extra_blocks, paras[i])
    end
  end

  for _, block in ipairs(others) do
    table.insert(extra_blocks, block)
  end

  if #extra_blocks > 0 then
    table.insert(
      blocks,
      pandoc.Div(extra_blocks, pandoc.Attr("", { "poster-key-extra" }))
    )
  end

  return pandoc.Div(
    blocks,
    pandoc.Attr("poster-key-region", { "poster-key-region" }, {
      ["role"] = "region",
      ["aria-label"] = "Key message"
    })
  )
end


local function build_resources_region(resources_div)
  if not resources_div then
    return pandoc.Div(
      {},
      pandoc.Attr("poster-resources-region", { "poster-resources-region", "poster-resources-region--empty" }, {
        ["role"] = "region",
        ["aria-label"] = "Resources"
      })
    )
  end

  local content = normalize_image_paragraphs(resources_div.content)

  return pandoc.Div(
    {
      pandoc.Div(content, pandoc.Attr("", { "poster-resources-content" }))
    },
    pandoc.Attr("poster-resources-region", { "poster-resources-region" }, {
      ["role"] = "region",
      ["aria-label"] = "Resources"
    })
  )
end

local function decorate_detail_blocks(blocks)
  local out = {}

  for _, block in ipairs(blocks) do
    if is_references_section(block) then
      block.attr = append_class(block.attr, "poster-references")
    end
    table.insert(out, block)
  end

  return out
end

local function build_support_region(blocks)
  return pandoc.Div(
    {
      pandoc.Div(blocks or {}, pandoc.Attr("", { "poster-flow", "poster-flow--support" }))
    },
    pandoc.Attr("poster-support-region", { "poster-support-region" }, {
      ["role"] = "region",
      ["aria-label"] = "Support content"
    })
  )
end

local function build_detail_region(blocks)
  return pandoc.Div(
    {
      pandoc.Div(decorate_detail_blocks(blocks or {}), pandoc.Attr("", { "poster-flow", "poster-flow--detail" }))
    },
    pandoc.Attr("poster-detail-region", { "poster-detail-region" }, {
      ["role"] = "region",
      ["aria-label"] = "Detailed results"
    })
  )
end

-- ---------------------------------------------------------
-- Classification
-- ---------------------------------------------------------

local function is_key_message_div(block)
  return block
    and block.t == "Div"
    and has_class(block, "key-message")
end

local function is_resources_div(block)
  return block
    and block.t == "Div"
    and (has_class(block, "resources") or has_class(block, "branding"))
end

local function is_explicit_support(block)
  return block
    and block.t == "Div"
    and has_class(block, "poster-support")
end

local function is_explicit_detail(block)
  return block
    and block.t == "Div"
    and has_class(block, "poster-detail")
end

local function classify_blocks(blocks)
  local key_block = nil
  local resources_block = nil
  local support_blocks = {}
  local detail_blocks = {}

  local seen_key = false

  for _, block in ipairs(blocks) do
    if is_key_message_div(block) and key_block == nil then
      key_block = block
      seen_key = true
    elseif is_resources_div(block) and resources_block == nil then
      resources_block = block
    elseif is_explicit_support(block) then
      table.insert(support_blocks, block)
    elseif is_explicit_detail(block) then
      table.insert(detail_blocks, block)
    else
      if seen_key then
        table.insert(detail_blocks, block)
      else
        table.insert(support_blocks, block)
      end
    end
  end

  return {
    key_block = key_block,
    resources_block = resources_block,
    support_blocks = support_blocks,
    detail_blocks = detail_blocks
  }
end

-- ---------------------------------------------------------
-- Main transformation
-- =========================================================
-- Lua now produces exactly four sibling regions as $body$.
-- The outer .poster-layout grid wrapper is owned by
-- template.html — this keeps structural HTML readable and
-- ensures screen and print CSS reference the same grid
-- defined in one place.
-- ---------------------------------------------------------

function Pandoc(doc)
  local classified = classify_blocks(doc.blocks)

  local header          = build_header(doc.meta)
  local key_region      = build_key_region(classified.key_block)
  local support_region  = build_support_region(classified.support_blocks)
  local detail_region   = build_detail_region(classified.detail_blocks)
  local resources_region = build_resources_region(classified.resources_block)

  local center_column = pandoc.Div(
    { key_region, resources_region },
    pandoc.Attr("poster-center-column", { "poster-center-column" }, {
      ["role"] = "region",
      ["aria-label"] = "Key message and resources"
    })
  )

  -- Return four direct children — template wraps them in .poster-layout
  doc.blocks = {
    header,
    support_region,
    center_column,
    detail_region
  }

  return doc
end