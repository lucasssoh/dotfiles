-- swayimg: the image viewer, dressed like the shell (DrawerTheme colours,
-- the UI font). Only what differs from swayimg's defaults is here; the
-- full list is /usr/share/swayimg/example.lua.
--
--   ← →      previous / next image in the folder
--   Return   gallery (and back)
--   w h e    fit the width, the height, the whole image (as in Liseuse)
--   + -      zoom             Backspace  back to the default fit
--   E        edit in satty (crop, annotate), saved next to the original
--   f        fullscreen       [ ]  rotate       q / Esc  quit

local faint  = 0x80f2f2f7  -- DrawerTheme.primary at half strength
local ink2   = 0xff8e8e93  -- DrawerTheme.secondary
local cream  = 0xffefece5  -- DrawerTheme.cream
local black  = 0xff000000
local card   = 0xff17171a  -- DrawerTheme.card
local deep   = 0xff0b0b0d  -- DrawerTheme.cardDeep

swayimg.decoration = false
swayimg.imagelist.adjacent = true   -- opened from Nemo, the whole folder follows

swayimg.text.font = "sans-serif"    -- MiSans, through 70-ui-font.conf
swayimg.text.size = 13
swayimg.text.padding = 16
swayimg.text.shadow = 0x60000000

-- A watermark rather than a caption: the text stays, faint enough to
-- read past, so the keys are there when you need them and the image is
-- never hidden behind a panel. swayimg has one colour and one timeout
-- for the whole layer, so the name and the counter take the same faint
-- ink and stay too. Press t to hide all of it.
swayimg.text.color = faint
swayimg.text.timeout = 0

local keys = "w width   h height   e whole   + − zoom   ← → browse   Return gallery   E edit   t hide"

swayimg.viewer.text = {
  topleft     = { "{name}" },
  topright    = { "{list.index} / {list.total}" },
  bottomleft  = { keys },
  bottomright = { "{scale}" },
}
swayimg.slideshow.text = {
  bottomleft = { keys },
}
swayimg.viewer.set_window_background(black)
swayimg.viewer.set_image_chessboard(16, 0xff1c1c20, 0xff2a2a2f)
swayimg.viewer.mark_color = cream

swayimg.slideshow.set_window_background(black)

swayimg.gallery.thumb_size = 180
swayimg.gallery.padding_size = 8
swayimg.gallery.border_size = 2
swayimg.gallery.border_color = cream
swayimg.gallery.selected_scale = 1.06
swayimg.gallery.selected_color = card
swayimg.gallery.unselected_color = deep
swayimg.gallery.window_color = black
swayimg.gallery.pstore = true       -- thumbnails kept on disk between runs
swayimg.gallery.text = {
  topright   = { "{list.index} / {list.total}" },
  bottomleft = { "← → ↑ ↓ choose   Return open   E edit   t hide" },
}

-- satty writes "photo-edit.png" beside "photo.jpg"; the original is never
-- touched. Single quotes escaped for the shell, '%' doubled because satty
-- reads the output name as a strftime pattern.
local function edit(img)
  if not img then return end
  local dir, stem = img.path:match("^(.*)/([^/]+)$")
  stem = stem:gsub("%.[^.]+$", "")
  local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
  local out = (dir .. "/" .. stem .. "-edit.png"):gsub("%%", "%%%%")
  os.execute("satty --filename " .. q(img.path) .. " --output-filename " .. q(out)
    .. " --early-exit >/dev/null 2>&1 &")
end

for _, mode in ipairs({ swayimg.viewer, swayimg.slideshow }) do
  mode.on_key("Left",  function() mode.open("prev") end)
  mode.on_key("Right", function() mode.open("next") end)
end
swayimg.viewer.on_key("Shift+e", function() edit(swayimg.viewer.get_image()) end)
swayimg.gallery.on_key("Shift+e", function() edit(swayimg.gallery.get_image()) end)

-- The fits use the same letters as Liseuse, so a photo and a page are
-- fitted the same way.
for _, mode in ipairs({ swayimg.viewer, swayimg.slideshow }) do
  mode.on_key("w", function() mode.set_fix_scale("width") end)
  mode.on_key("h", function() mode.set_fix_scale("height") end)
  mode.on_key("e", function() mode.set_fix_scale("fit") end)
end

for _, mode in ipairs({ swayimg.viewer, swayimg.slideshow, swayimg.gallery }) do
  mode.on_key("q", function() swayimg.exit() end)
end
