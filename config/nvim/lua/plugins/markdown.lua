return {
  -- 1. Le rendu visuel immersif dans le terminal
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { 
      "nvim-treesitter/nvim-treesitter", 
      "nvim-tree/nvim-web-devicons" 
    },
    ft = { "markdown" }, -- Lazy-load : s'active uniquement pour le Markdown
    config = function()
      -- Chemin absolu plutôt que nom nu : ~/.local/bin est 2e dans le PATH
      -- de cette machine, mais tex2utf n'y est pas (ce n'est pas une
      -- commande qu'on tape) -- et vim.fn.executable() accepte un chemin,
      -- donc la liste de convertisseurs se filtre correctement.
      local tex2utf = vim.fn.stdpath("config") .. "/bin/tex2utf"

      require("render-markdown").setup({
        heading = {
          enabled = true,
          render_modes = true,
          sign = true,
          icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
          position = "overlay",
          signs = { "󰫎 " },
          width = "full",
          left_margin = 0,
          left_pad = 0,
          right_pad = 0,
          min_width = 0,
          border = false,
          backgrounds = {
            "RenderMarkdownH1Bg", "RenderMarkdownH2Bg", "RenderMarkdownH3Bg",
            "RenderMarkdownH4Bg", "RenderMarkdownH5Bg", "RenderMarkdownH6Bg",
          },
          foregrounds = {
            "RenderMarkdownH1", "RenderMarkdownH2", "RenderMarkdownH3",
            "RenderMarkdownH4", "RenderMarkdownH5", "RenderMarkdownH6",
          },
        },
        code = {
          enabled = true,
          render_modes = true,
          sign = true,
          style = "full",
          position = "left",
          language_pad = 0,
          language_name = true,
          disable_background = { "diff" },
          width = "full",
          left_margin = 0,
          left_pad = 0,
          right_pad = 0,
          min_width = 0,
          border = "thin",
          above = "▄",
          below = "▀",
          highlight = "RenderMarkdownCode",
          highlight_inline = "RenderMarkdownCodeInline",
        },
        checkbox = {
          enabled = true,
          render_modes = true,
          position = "inline",
          unchecked = { icon = "󰄱 ", highlight = "RenderMarkdownUnchecked" },
          checked = { icon = "󰱒 ", highlight = "RenderMarkdownChecked" },
          custom = {
            todo = { raw = "[-]", rendered = "󰗡 Todo", highlight = "RenderMarkdownTodo" },
          },
        },
        pipe_table = {
          enabled = true,
          render_modes = true,
          preset = "none",
          style = "full",
          cell = "padded",
          padding = 1,
          border = {
            "┌", "┬", "┐", "├", "┼", "┤", "└", "┴", "┘", "│", "─",
          },
        },
        -- Formules mathématiques rendues en unicode à la place du
        -- source LaTeX. render-markdown délègue la conversion à un
        -- binaire externe, d'où la chaîne de repli :
        --   utftex (libtexprintf-tools) rend en 2D — a^2 devient a²,
        --     a_{n-1} devient aₙ₋₁, \frac trace une vraie barre, les
        --     matrices et \binom obtiennent leurs grandes parenthèses ;
        --   latex2text (pylatexenc) reprend en une seule ligne les
        --     commandes qu'utftex ne connaît pas (\pmod, \text, ...),
        --     sur lesquelles il sort en code 1.
        -- La sortie d'utftex tient souvent sur plusieurs lignes : en
        -- position "center" le plugin conceal le $...$, pose la ligne
        -- du milieu en virt_text inline et les autres en virt_lines
        -- au-dessus/en dessous — la formule s'affiche donc en 2D,
        -- à sa place dans le texte.
        latex = {
          enabled = true,
          render_modes = true,
          -- Chaîne de repli, essayée dans l'ordre : chaque convertisseur
          -- ne reçoit que les formules sur lesquelles le précédent a
          -- échoué. Le « cat » final n'est pas une facétie -- c'est un
          -- garde-fou. Quand plus aucun convertisseur ne rend une
          -- formule, render-markdown affiche le texte littéral « error »
          -- à sa place (handler/latex.lua : Handler.cache[input] =
          -- 'error'), ce qui efface le contenu au lieu de le laisser
          -- lisible. cat renvoie la formule telle quelle : on retombe
          -- sur le source LaTeX, sans les $, ce qui est le pire cas
          -- honnête.
          converter = { tex2utf, "latex2text", "cat" },
          inline = true,
          block = true,
          position = "center",
          highlight = "RenderMarkdownMath",
          top_pad = 0,
          bottom_pad = 0,
        },
        callout = {
          note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
          tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
          warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
          caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
          todo = { raw = "[!TODO]", rendered = "󰗡 Todo", highlight = "RenderMarkdownInfo" },
        },
      })

      -- Les blocs $$ ... $$ écrits sur plusieurs lignes sont le seul
      -- endroit où render-markdown laisse la source visible. Son handler
      -- latex ne sait se substituer à un nœud que s'il tient sur une
      -- ligne (position "center") ; au-delà il retombe sur des
      -- virt_lines au-dessus, d'où la formule rendue en haut et la
      -- source modifiable en dessous -- incohérent avec les titres, les
      -- tableaux et les formules inline, qui remplacent la leur.
      --
      -- Le plugin a pourtant déjà la primitive : Marks:replace, dont se
      -- sert le rendu des tableaux, pose conceal_lines sur le nœud et
      -- laisse lib/replacements.lua ré-ancrer les virt_lines sur la
      -- première ligne encore visible. On réécrit donc la marque que le
      -- handler vient de produire dans cette forme-là, au lieu de
      -- réimplémenter la conversion, son cache et son placement.
      --
      -- Côté curseur le résultat est celui du reste de la config :
      -- dehors, la formule occupe la place du bloc et les lignes de
      -- source ont disparu ; dedans, anti_conceal rend la source
      -- (core/ui.lua, extmark:overlaps(range) avec mark.conceal).
      --
      -- Si une version future change la forme des marques, le test
      -- opts.virt_lines cesse de matcher et on retombe simplement sur le
      -- comportement d'origine, pas sur un rendu cassé.
      -- Groupe à nous (pas un groupe du plugin) : RenderMarkdownMath
      -- sert aussi aux formules inline, où un fond ferait ressembler la
      -- formule à du code au milieu de la phrase. Le bloc a donc le
      -- sien, défini dans lua/coucou/init.lua à côté de
      -- RenderMarkdownCode dont il reprend la teinte de fond.
      local MATH_BLOCK_HL = "RenderMarkdownMathBlock"

      local handler = require("render-markdown.handler.latex")
      if not handler.latex_block_in_place then
        handler.latex_block_in_place = true
        local parse = handler.parse

        -- Étendue des blocs latex multi-ligne, relue dans l'arbre
        -- treesitter plutôt qu'accumulée d'un appel du handler à
        -- l'autre : il est appelé une fois par racine, et un état gardé
        -- entre les appels se désynchroniserait dès qu'une passe de
        -- rendu est interrompue.
        local function multiline_blocks(buf)
          local blocks = {}
          local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
          if not ok or not parser then
            return blocks
          end
          parser:for_each_tree(function(tree, language_tree)
            if language_tree:lang() ~= "latex" then
              return
            end
            local start_row, _, end_row, end_col = tree:root():range()
            if end_row > start_row then
              blocks[start_row] = { end_row = end_row, end_col = end_col }
            end
          end)
          return blocks
        end

        -- Largeur du texte de la fenêtre, comme le « width = full » des
        -- blocs de code : c'est elle qui donne au bloc math le même fond
        -- pleine largeur, donc la même lecture « conteneur ».
        local function text_width(buf)
          local win = vim.fn.bufwinid(buf)
          if win == -1 then
            return vim.o.columns
          end
          local info = vim.fn.getwininfo(win)[1]
          local width = vim.api.nvim_win_get_width(win)
          return math.max(width - (info and info.textoff or 0), 1)
        end

        -- Deux choses ici, et la première est la raison d'être du reste.
        --
        -- 1. La hauteur. Un « $$ / x = 1 / $$ » fait 3 lignes de source
        --    pour 1 ligne rendue : tout le document en dessous remonte de
        --    2 lignes dès que le curseur sort du bloc, et redescend dès
        --    qu'il y rentre. On complète donc le rendu jusqu'à la hauteur
        --    de la source, moitié au-dessus moitié en dessous, pour que
        --    rien ne bouge. Une formule plus haute que sa source (une
        --    intégrale dans un bloc de 3 lignes) déborde encore d'une
        --    ligne ou deux : on ne peut pas retirer des lignes au texte,
        --    seulement en ajouter.
        --
        -- 2. Le fond. Chaque ligne est complétée par des espaces jusqu'à
        --    la largeur du texte et repeinte dans le groupe du bloc, ce
        --    qui donne le bandeau continu des blocs de code plutôt que
        --    des caractères flottants au milieu du paragraphe.
        local function pad_block(lines, height, width)
          local out = {}
          local missing = math.max(height - #lines, 0)
          local above = math.floor(missing / 2)
          local function blank()
            return { { string.rep(" ", width), MATH_BLOCK_HL } }
          end
          for _ = 1, above do
            out[#out + 1] = blank()
          end
          for _, line in ipairs(lines) do
            local used = 0
            for _, chunk in ipairs(line) do
              chunk[2] = MATH_BLOCK_HL
              used = used + vim.fn.strdisplaywidth(chunk[1])
            end
            if used < width then
              line[#line + 1] = { string.rep(" ", width - used), MATH_BLOCK_HL }
            end
            out[#out + 1] = line
          end
          for _ = above + 1, missing do
            out[#out + 1] = blank()
          end
          return out
        end

        handler.parse = function(ctx)
          local marks = parse(ctx)
          -- Le handler accumule les nœuds et ne rend qu'au dernier
          -- appel, pour convertir toutes les formules d'un coup.
          if not ctx.last then
            return marks
          end
          local blocks = multiline_blocks(ctx.buf)
          local width = text_width(ctx.buf)
          local backgrounds = {}
          for _, mark in ipairs(marks) do
            local block = blocks[mark.start_row]
            if block and mark.opts and mark.opts.virt_lines then
              local height = block.end_row - mark.start_row + 1
              mark.replace = pad_block(mark.opts.virt_lines, height, width)
              mark.conceal = true
              mark.start_col = 0
              mark.opts = {
                end_row = block.end_row,
                end_col = block.end_col,
                conceal_lines = "",
              }
              -- Le même fond sur les lignes de source, pour l'état où le
              -- curseur est dans le bloc : conceal = false, donc cette
              -- marque n'est jamais masquée -- mais les lignes qu'elle
              -- peint ne sont dessinées que lorsque le conceal_lines
              -- ci-dessus est levé. Entrer dans un bloc n'échange donc
              -- que son contenu, pas son cadre.
              backgrounds[#backgrounds + 1] = {
                conceal = false,
                modes = mark.modes,
                start_row = mark.start_row,
                start_col = 0,
                opts = {
                  end_row = block.end_row,
                  end_col = block.end_col,
                  hl_group = MATH_BLOCK_HL,
                  hl_eol = true,
                },
              }

              -- Le cas inverse : une formule plus haute que sa source
              -- (une intégrale dans un bloc de 3 lignes). On ne peut pas
              -- raccourcir le rendu, mais on peut allonger la source --
              -- et seulement elle. Neovim n'affiche pas les virt_lines
              -- portées par une ligne masquée (c'est ce que documente
              -- lib/replacements.lua du plugin) : ancrées sur la
              -- dernière ligne du bloc, ces lignes vides n'existent donc
              -- que lorsque le conceal_lines est levé, c'est-à-dire
              -- exactement quand la source est visible. C'est le
              -- « seulement dans l'état révélé » qu'anti_conceal ne sait
              -- pas exprimer.
              local overflow = #mark.replace - height
              if overflow > 0 then
                local filler = {}
                for _ = 1, overflow do
                  filler[#filler + 1] = { { string.rep(" ", width), MATH_BLOCK_HL } }
                end
                backgrounds[#backgrounds + 1] = {
                  conceal = false,
                  modes = mark.modes,
                  start_row = block.end_row,
                  start_col = 0,
                  opts = { virt_lines = filler },
                }
              end
            end
          end
          vim.list_extend(marks, backgrounds)
          return marks
        end
      end
    end,
  },
}
