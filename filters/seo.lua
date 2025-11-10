local utils = pandoc.utils
local path = pandoc.path

local function meta_string(value)
  if not value then
    return nil
  end
  return utils.stringify(value)
end

local function meta_list(value)
  local result = {}
  if not value then
    return result
  end
  local value_type = utils.type(value)
  if value_type == "MetaList" or type(value) == "table" then
    for _, item in ipairs(value) do
      local text = utils.stringify(item)
      if text ~= "" then
        table.insert(result, text)
      end
    end
  else
    local text = utils.stringify(value)
    if text ~= "" then
      table.insert(result, text)
    end
  end
  return result
end

local function dedupe(list)
  local seen = {}
  local result = {}
  for _, item in ipairs(list) do
    local key = item:lower()
    if not seen[key] then
      table.insert(result, item)
      seen[key] = true
    end
  end
  return result
end

local function ensure_meta_string(meta, key, value)
  if value and value ~= "" then
    meta[key] = pandoc.MetaString(value)
  end
end

local function ensure_meta_list(meta, key, values)
  if #values == 0 then
    return
  end
  local items = {}
  for _, value in ipairs(values) do
    table.insert(items, pandoc.MetaString(value))
  end
  meta[key] = pandoc.MetaList(items)
end

local function first_paragraph_text(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Para" or block.t == "Plain" then
      local text = utils.stringify(block):gsub("%s+", " ")
      if text ~= "" then
        return text
      end
    end
  end
  return nil
end

local function absolute_image(site_url, image)
  if not image or image == "" then
    return nil
  end
  if image:match("^https?://") then
    return image
  end
  local base = site_url or ""
  if base == "" then
    return image
  end
  if base:sub(-1) == "/" then
    base = base:sub(1, -2)
  end
  if image:sub(1, 1) ~= "/" then
    image = "/" .. image
  end
  return base .. image
end

local function json_escape(value)
  if not value then
    return ""
  end
  -- Only escape control characters (0x00-0x1F), backslash, and double quote
  -- UTF-8 characters should pass through as-is since JSON natively supports UTF-8
  local escaped = value
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("[\0-\31]", function(c)
      -- Only escape actual control characters (0x00-0x1F)
      return string.format("\\u%04x", c:byte())
    end)
  return escaped
end

local function compute_canonical(site_url)
  if not (site_url and site_url ~= "") then
    return nil
  end
  if not (quarto.doc and quarto.doc.output_file) then
    return site_url
  end
  local output_file = quarto.doc.output_file
  local project_dir = quarto.project and quarto.project.directory or "."
  local rel = path.make_relative(output_file, project_dir):gsub("\\\\", "/")
  rel = rel:gsub("^%./", "")
  local out_dir = quarto.project and quarto.project.output_directory
  if out_dir and out_dir ~= "" then
    out_dir = out_dir:gsub("\\\\", "/")
    if project_dir and project_dir ~= "" then
      local normalized_project = project_dir:gsub("\\\\", "/")
      if out_dir:sub(1, #normalized_project + 1) == normalized_project .. "/" then
        out_dir = out_dir:sub(#normalized_project + 2)
      end
    end
    out_dir = out_dir:gsub("^%./", "")
    if out_dir:sub(1, 1) == "/" then
      out_dir = out_dir:sub(2)
    end
  end
  if (not out_dir or out_dir == "") and quarto.project and quarto.project.config then
    local project = quarto.project.config.project
    if project then
      out_dir = project["output-dir"] or project["output_dir"]
    end
  end
  if out_dir and out_dir ~= "" then
    if rel:sub(1, #out_dir + 1) == out_dir .. "/" then
      rel = rel:sub(#out_dir + 2)
    elseif rel == out_dir then
      rel = ""
    end
  else
    local first_segment, remainder = rel:match("^([^/]+)/(.*)$")
    if first_segment and (first_segment == "docs" or first_segment == "_site" or first_segment == "site") then
      rel = remainder
    elseif rel == "docs" or rel == "_site" or rel == "site" then
      rel = ""
    end
  end
  if rel:sub(-10) == "index.html" then
    rel = rel:sub(1, -11)
  else
    rel = rel:gsub("%.html$", "/")
  end
  if rel == "" then
    rel = "/"
  elseif rel:sub(1, 1) ~= "/" then
    rel = "/" .. rel
  end
  local base = site_url:gsub("/+$", "")
  if rel == "/" then
    return base .. "/"
  else
    return base .. rel
  end
end

local function gather_keywords(meta, categories)
  local keywords = meta_list(meta["keywords"])
  local sources = {
    categories or meta_list(meta["categories"]),
    meta_list(meta["tags"]),
    meta_list(meta["additional-keywords"] or meta["extra-keywords"])
  }
  for _, source in ipairs(sources) do
    for _, value in ipairs(source) do
      table.insert(keywords, value)
    end
  end
  return dedupe(keywords)
end

function Pandoc(doc)
  local meta = doc.meta or pandoc.Meta({})

  local site_url = meta_string(meta["site-url"]) or meta_string(meta["site_url"]) or ""
  if site_url == "" and meta.website and meta.website["site-url"] then
    site_url = utils.stringify(meta.website["site-url"])
  end
  if site_url ~= "" then
    ensure_meta_string(meta, "site-url", site_url)
  end

  local site_title = meta_string(meta["site-title"]) or meta_string(meta["site_title"]) or meta_string(meta.website and meta.website.title) or meta_string(meta["title-prefix"])
  ensure_meta_string(meta, "site-title", site_title)

  local page_title = meta_string(meta["title"]) or site_title
  if page_title and site_title and site_title ~= "" and page_title ~= site_title then
    ensure_meta_string(meta, "seo-title", page_title .. " – " .. site_title)
  else
    ensure_meta_string(meta, "seo-title", page_title)
  end

  local categories_list = meta_list(meta["categories"])
  local has_categories = #categories_list > 0
  local has_date = meta_string(meta["date"]) ~= nil

  local description = meta_string(meta["description"])
  if not description or description == "" then
    if has_date or has_categories then
      description = first_paragraph_text(doc.blocks) or meta_string(meta["site-description"])
    else
      description = meta_string(meta["site-description"]) or first_paragraph_text(doc.blocks)
    end
  end
  ensure_meta_string(meta, "description", description)

  local keywords = gather_keywords(meta, categories_list)
  ensure_meta_list(meta, "keywords", keywords)
  if #keywords > 0 then
    ensure_meta_string(meta, "keywords-text", table.concat(keywords, ", "))
  end

  local image = meta_string(meta["image"]) or meta_string(meta["social-image"])
  ensure_meta_string(meta, "social-image", image)
  local absolute = absolute_image(site_url, image)
  ensure_meta_string(meta, "social-image-abs", absolute or image)
  local image_alt = meta_string(meta["image-alt"]) or meta_string(meta["social-image-alt"]) or "VB's website social card"
  ensure_meta_string(meta, "social-image-alt", image_alt)

  local canonical = compute_canonical(site_url) or meta_string(meta["canonical-url"])
  ensure_meta_string(meta, "canonical-url", canonical)

  local twitter_site = meta_string(meta["twitter-site"]) or meta_string(meta["twitter"]) or "@reach_vb"
  local twitter_creator = meta_string(meta["twitter-creator"]) or twitter_site
  ensure_meta_string(meta, "twitter-site", twitter_site)
  ensure_meta_string(meta, "twitter-creator", twitter_creator)
  ensure_meta_string(meta, "twitter-card", meta_string(meta["twitter-card"]) or "summary_large_image")

  local og_type = "website"
  local schema_type = "WebPage"
  if has_date or has_categories then
    og_type = "article"
    schema_type = "BlogPosting"
  elseif meta.listing ~= nil then
    schema_type = "CollectionPage"
  end
  ensure_meta_string(meta, "og-type", og_type)
  ensure_meta_string(meta, "schema-page-type", schema_type)

  local author_name = meta_string(meta["author-name"]) or meta_string(meta["author"])
  if not author_name or author_name == "" then
    local author = meta["author"]
    if author and author.t == "MetaList" and #author > 0 then
      author_name = utils.stringify(author[1])
    end
  end
  ensure_meta_string(meta, "author-name", author_name or "Vaibhav (VB) Srivastav")

  local published = meta_string(meta["date"])
  if published and published:match("^%d%d%d%d%-%d%d%-%d%d") then
    ensure_meta_string(meta, "published-date", published)
  end

  if site_url ~= "" then
    local trimmed = site_url:gsub("/+$", "")
    ensure_meta_string(meta, "schema-website-id", trimmed .. "/#website")
    ensure_meta_string(meta, "schema-person-id", trimmed .. "/#person")
  end

  local schema_site_id = meta_string(meta["schema-website-id"]) or site_url
  local schema_person_id = meta_string(meta["schema-person-id"]) or site_url
  local site_description = meta_string(meta["site-description"]) or description
  local same_as = meta_list(meta["same-as"] or meta["same_as"])
  local same_as_json = "[]"
  if #same_as > 0 then
    local parts = {}
    for _, link in ipairs(same_as) do
      table.insert(parts, string.format('"%s"', json_escape(link)))
    end
    same_as_json = "[" .. table.concat(parts, ", ") .. "]"
  end
  local published_date = meta_string(meta["published-date"]) or ""
  local published_line = ""
  if published_date ~= "" then
    published_line = string.format(',\n      "datePublished": "%s"', json_escape(published_date))
  end
  local page_image_value = meta_string(meta["social-image-abs"]) or absolute or image or ""
  local page_image_line = ""
  if page_image_value ~= "" then
    page_image_line = string.format(',\n      "image": "%s"', json_escape(page_image_value))
  end

  local schema_json = string.format([[{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": "%s",
      "url": "%s",
      "name": "%s",
      "description": "%s",
      "publisher": {
        "@id": "%s"
      }
    },
    {
      "@type": "Person",
      "@id": "%s",
      "name": "Vaibhav (VB) Srivastav",
      "url": "%s",
      "description": "%s",
      "image": "%s",
      "sameAs": %s
    },
    {
      "@type": "%s",
      "@id": "%s",
      "url": "%s",
      "name": "%s",
      "description": "%s",
      "inLanguage": "en",
      "author": {
        "@id": "%s"
      }%s%s
    }
  ]
}]],
    json_escape(schema_site_id ~= "" and schema_site_id or site_url),
    json_escape(site_url),
    json_escape(site_title or ""),
    json_escape(site_description or ""),
    json_escape(schema_person_id ~= "" and schema_person_id or site_url),
    json_escape(schema_person_id ~= "" and schema_person_id or site_url),
    json_escape(site_url),
    json_escape(site_description or ""),
    json_escape(page_image_value or ""),
    same_as_json,
    json_escape(schema_type or "WebPage"),
    json_escape(canonical or site_url),
    json_escape(canonical or site_url),
    json_escape(meta_string(meta["seo-title"]) or page_title or site_title or ""),
    json_escape(description or site_description or ""),
    json_escape(schema_person_id ~= "" and schema_person_id or site_url),
    published_line,
    page_image_line)
  ensure_meta_string(meta, "schema-json", schema_json)

  doc.meta = meta
  return doc
end
