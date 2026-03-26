return {
  "sphamba/smear-cursor.nvim",
  opts = {
    -- La couleur de la traînée (on part sur ton blanc pur pour matcher ton curseur)
    cursor_color = "#ffffff",
    
    -- Animation partout
    smear_between_buffers = true,
    smear_between_neighbor_lines = true,
    smear_insert_mode = true,
    
    -- Pour un rendu plus fluide sur ta Fedora 43
    scroll_buffer_space = true,
    
    -- Vitesse de l'effet (plus c'est petit, plus c'est rapide)
    -- On l'ajuste pour que ce soit nerveux mais visible
    stiffness = 0.8,               -- Résistance du ressort (0.1 à 1)
    trailing_stiffness = 0.5,      -- Vitesse de la traînée
    distance_stop_animating = 0.5, -- Précision de l'arrêt
    
    -- Désactive si tu trouves que ça fait des "ombres" bizarres sur le texte
    legacy_computing_symbols_support = false,
  },
}
