return {
  {
    'akinsho/bufferline.nvim',
    version = "*",
    dependencies = 'nvim-tree/nvim-web-devicons',
    config = function()
      -- Compteur de diagnostics affiché devant le nom du fichier :
      -- « 3 Main.java ✕ ». On ne montre que le nombre de la pire
      -- sévérité présente, pas une ligne de compteurs : la couleur dit
      -- déjà laquelle c'est (BufferLineError/Warning, lua/coucou/init.lua),
      -- exactement comme nvim-tree qui colore le nom du fichier au lieu
      -- d'aligner des pictogrammes.
      --
      -- Seuls ERROR et WARN comptent. Les HINT (variable inutilisée de
      -- lua_ls, etc.) feraient porter un compteur à presque tous les
      -- onglets, ce qui ne distingue plus rien -- alors que dans
      -- nvim-tree ils ont leur place, vu qu'on y cherche un fichier
      -- précis dans une arborescence.
      local function diagnostic_prefix(bufnr)
        if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
          return ""
        end
        local counts = vim.diagnostic.count(bufnr)
        local severity = vim.diagnostic.severity
        for _, level in ipairs({ severity.ERROR, severity.WARN }) do
          local n = counts[level]
          if n and n > 0 then
            return n .. " "
          end
        end
        return ""
      end

      require("bufferline").setup({
        options = {
          mode = "buffers",
          separator_style = "thin",
          always_show_bufferline = true,
          show_buffer_close_icons = true,
          show_close_icon = true,
          color_icons = true,

          -- Alimente le composant « diagnostics » de bufferline. On ne
          -- s'en sert pas pour afficher quoi que ce soit (voir
          -- diagnostics_indicator juste en dessous) mais pour son effet
          -- de bord : c'est lui qui applique la couleur de la pire
          -- sévérité au segment du nom.
          diagnostics = "nvim_lsp",

          -- Chaîne vide plutôt que le « (3) » par défaut : le compteur
          -- est déjà devant le nom. bufferline ne jette pas un segment
          -- vide (ui.lua, filter_invalid ne filtre que les nil), donc la
          -- recoloration du nom survit -- et le spacing qui suit, lui,
          -- est bien conditionné sur #text > 0, donc aucune espace en
          -- trop après le nom.
          diagnostics_indicator = function()
            return ""
          end,

          -- Le compteur doit être *devant* le nom, là où bufferline ne
          -- place jamais son indicateur. Le glisser dans le nom lui-même
          -- est ce qui l'y met, et lui fait au passage hériter de la
          -- couleur de sévérité, ce que le composant « numbers » (le
          -- seul autre segment placé avant) n'aurait pas donné : il n'a
          -- qu'un seul highlight, indépendant des diagnostics.
          name_formatter = function(buf)
            return diagnostic_prefix(buf.bufnr) .. buf.name
          end,

          offsets = {
            {
              filetype = "NvimTree",
              text = "buffers",
              text_align = "center",
              separator = false,
            }
          },
        }
      })

      -- bufferline ne s'abonne pas à DiagnosticChanged (ses autocmds :
      -- BufAdd, BufEnter, BufRead, ColorScheme, SessionLoadPost,
      -- TabEnter, User, VimLeavePre). Sans ça la tabline n'est
      -- réévaluée qu'au prochain redraw provoqué par autre chose, et le
      -- compteur reste en retard d'une sauvegarde sur le serveur LSP.
      vim.api.nvim_create_autocmd("DiagnosticChanged", {
        group = vim.api.nvim_create_augroup("BufferlineDiagnostics", { clear = true }),
        callback = function()
          vim.cmd.redrawtabline()
        end,
      })
    end,
  },
}
