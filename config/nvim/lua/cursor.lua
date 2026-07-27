return {
  "sphamba/smear-cursor.nvim",
  opts = {
    -- Trail color (going with pure white to match your cursor)
    cursor_color = "#ffffff",
    -- Animation everywhere
    smear_between_buffers = true,
    smear_between_neighbor_lines = true,
    smear_insert_mode = true,
    -- For smoother rendering on your Fedora 43
    scroll_buffer_space = true,
    -- Effect speed (smaller = faster)
    -- Tuned to be snappy but still visible
    stiffness = 0.8,               -- Spring resistance (0.1 to 1)
    trailing_stiffness = 0.5,      -- Trail speed
    distance_stop_animating = 0.5, -- Stop precision
    -- Disable if you find it makes weird "shadows" on the text
    legacy_computing_symbols_support = false,
  },
}
