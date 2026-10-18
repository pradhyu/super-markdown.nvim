local config = require("super-markdown.config")
local ascii = require("super-markdown.mermaid.ascii")

local M = {}

local function get_cache_dir()
  local dir = config.options.mermaid.cache_dir
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

function M.compile(mermaid_code, callback)
  local hash = vim.fn.sha256(mermaid_code)
  local cache_dir = get_cache_dir()
  local png_path = string.format("%s/%s.png", cache_dir, hash)
  local svg_path = string.format("%s/%s.svg", cache_dir, hash)
  local mmd_path = string.format("%s/%s.mmd", cache_dir, hash)

  -- Check if cached PNG already exists
  if vim.fn.filereadable(png_path) == 1 then
    callback(nil, {
      png = png_path,
      svg = svg_path,
      hash = hash,
      ascii = ascii.render(mermaid_code),
      cached = true,
    })
    return
  end

  -- Write raw mmd to cache
  local mmd_file = io.open(mmd_path, "w")
  if mmd_file then
    mmd_file:write(mermaid_code)
    mmd_file:close()
  end

  -- Check if local mmdc is available
  if vim.fn.executable("mmdc") == 1 then
    vim.system({ "mmdc", "-i", mmd_path, "-o", png_path, "-b", "transparent" }, {}, function(obj)
      vim.schedule(function()
        if obj.code == 0 and vim.fn.filereadable(png_path) == 1 then
          callback(nil, {
            png = png_path,
            svg = svg_path,
            hash = hash,
            ascii = ascii.render(mermaid_code),
            cached = false,
          })
        else
          M.compile_via_api(mermaid_code, hash, svg_path, png_path, callback)
        end
      end)
    end)
    return
  end

  -- Fallback to cloud API
  M.compile_via_api(mermaid_code, hash, svg_path, png_path, callback)
end

function M.compile_via_api(mermaid_code, hash, svg_path, png_path, callback)
  local theme = config.options.mermaid.theme or "dark"
  local payload = vim.fn.json_encode({
    code = mermaid_code,
    mermaid = { theme = theme },
  })
  local encoded = vim.base64.encode(payload)
  local url = config.options.mermaid.api_url .. encoded

  -- Fetch SVG asynchronously via curl
  vim.system({ "curl", "-s", "--connect-timeout", "5", "-o", svg_path, url }, {}, function(curl_obj)
    vim.schedule(function()
      if curl_obj.code ~= 0 or vim.fn.getfsize(svg_path) <= 0 then
        pcall(os.remove, svg_path)
        callback("Failed to download Mermaid SVG", {
          png = nil,
          svg = nil,
          hash = hash,
          ascii = ascii.render(mermaid_code),
        })
        return
      end

      -- Check if file contains valid SVG content
      local svg_file = io.open(svg_path, "r")
      local header = svg_file and svg_file:read(200) or ""
      if svg_file then svg_file:close() end

      if not (header:find("<svg") or header:find("<?xml")) then
        pcall(os.remove, svg_path)
        callback("Invalid SVG response from endpoint", {
          png = nil,
          svg = nil,
          hash = hash,
          ascii = ascii.render(mermaid_code),
        })
        return
      end

      -- If ImageMagick `magick` is available, convert SVG to PNG
      if vim.fn.executable("magick") == 1 then
        vim.system({ "magick", "-background", "none", svg_path, png_path }, {}, function(conv_obj)
          vim.schedule(function()
            local success = (conv_obj.code == 0 and vim.fn.getfsize(png_path) > 0)
            if success then
              callback(nil, {
                png = png_path,
                svg = svg_path,
                hash = hash,
                ascii = ascii.render(mermaid_code),
              })
            else
              pcall(os.remove, png_path)
              callback("Image conversion failed", {
                png = nil,
                svg = svg_path,
                hash = hash,
                ascii = ascii.render(mermaid_code),
              })
            end
          end)
        end)
      else
        callback(nil, {
          png = nil,
          svg = svg_path,
          hash = hash,
          ascii = ascii.render(mermaid_code),
        })
      end
    end)
  end)
end

return M
