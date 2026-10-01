-- swayimg: the image viewer, dressed like the shell (DrawerTheme colours,
-- the UI font). Only what differs from swayimg's defaults is here; the
-- full list is /usr/share/swayimg/example.lua.
--
--   ← →      previous / next image in the folder
--   Return   gallery (and back)
--   e        edit in satty (crop, annotate), saved next to the original
--   f        fullscreen       [ ]  rotate       q / Esc  quit

local ink    = 0xfff2f2f7  -- DrawerTheme.primary
local ink2   = 0xff8e8e93  -- DrawerTheme.secondary
local cream  = 0xffefece5  -- DrawerTheme.cream
local black  = 0xff000000
local card   = 0xff17171a  -- DrawerTheme.card
local deep   = 0xff0b0b0d  -- DrawerTheme.cardDeep

swayimg.decoration = false
swayimg.imagelist.adjacent = true   -- opened from Nemo, the whole folder follows

swayimg.text.font = "sans-serif"    -- MiSans, through 70-ui-font.conf
swayimg.text.size = 15
swayimg.text.padding = 18
swayimg.text.color = ink
swayimg.text.shadow = 0x80000000
swayimg.text.timeout = 2

swayimg.viewer.text = {
  topleft  = { "{name}" },
  topright = { "{list.index} / {list.total}" },
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
swayimg.gallery.text = { topright = { "{list.index} / {list.total}" } }

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
swayimg.viewer.on_key("e", function() edit(swayimg.viewer.get_image()) end)
swayimg.gallery.on_key("e", function() edit(swayimg.gallery.get_image()) end)

for _, mode in ipairs({ swayimg.viewer, swayimg.slideshow, swayimg.gallery }) do
  mode.on_key("q", function() swayimg.exit() end)
end
