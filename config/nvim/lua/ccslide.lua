-- ============================================================
-- CCSLIDE.LUA — mode slide pour les decks mdp
-- ============================================================
-- Chargé par ftplugin/markdown.lua (mappings buffer-local) et par
-- lua/plugins/lualine.lua (jauge de remplissage).
--
-- Pourquoi une jauge : mdp REFUSE de démarrer si une seule slide dépasse
-- la taille du terminal, et il ne le dit qu'au lancement -- c'est-à-dire
-- devant l'amphi. Mesuré sur mdp 1.0.19, il compte toutes les lignes
-- brutes de la slide (lignes vides comprises) et réclame 3 lignes de plus
-- pour son bandeau de titre et sa barre de pied.
-- ============================================================

local M = {}

M.overhead = 3  -- bandeau + pied de mdp (mesuré, pas estimé)

-- Pas de marge fixe : `vim.o.lines` / `vim.o.columns` SONT la taille
-- courante du terminal, réévaluée par nvim à chaque resize, et M.present()
-- rend ce même terminal plein écran à mdp via `:!`. Le budget suit donc
-- la fenêtre en direct au lieu d'être figé.

local SCRIPT = vim.fn.expand("~/.config/ccslide/ccslide.py")
local ns = vim.api.nvim_create_namespace("ccslide")

-- ============================================================
-- Analyse du deck
-- ============================================================

--- Une règle horizontale mdp : au moins 3 fois - ou *, espaces tolérés.
local function is_sep(line)
    local s = vim.trim(line)
    if s:match("^[%-%s]+$") and select(2, s:gsub("%-", "")) >= 3 then
        return true
    end
    if s:match("^[%*%s]+$") and select(2, s:gsub("%*", "")) >= 3 then
        return true
    end
    return false
end

M.is_sep = is_sep

--- Nombre de lignes de l'en-tête de métadonnées (bloc <!-- --> ou %clés).
local function meta_end(lines)
    local i = 1
    while i <= #lines and vim.trim(lines[i]) == "" do
        i = i + 1
    end
    if i <= #lines and vim.startswith(vim.trim(lines[i]), "<!--") then
        for j = i, #lines do
            if lines[j]:find("%-%->") then
                return j
            end
        end
        return #lines
    end
    local start = i
    while i <= #lines and vim.startswith(vim.trim(lines[i]), "%") do
        i = i + 1
    end
    return i > start and i - 1 or 0
end

--- Découpe le buffer en slides.
--- Retourne { { first = n, last = n, sep = n|nil }, ... } en index 1.
--- `sep` est la ligne de séparation qui SUIT la slide.
function M.slides(buf)
    buf = buf or 0
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local start = meta_end(lines) + 1
    local out, cur = {}, start

    for i = start, #lines do
        -- Une règle ne sépare que si une ligne vide la précède (man mdp) :
        -- sinon deux slides fusionnent en silence.
        if is_sep(lines[i]) and i > 1 and vim.trim(lines[i - 1]) == "" then
            table.insert(out, { first = cur, last = i - 1, sep = i })
            cur = i + 1
        end
    end
    table.insert(out, { first = cur, last = math.max(#lines, cur) })
    return out
end

--- Index de la slide où se trouve le curseur.
function M.current_index(buf)
    local slides = M.slides(buf)
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for i, s in ipairs(slides) do
        if line <= (s.sep or s.last) then
            return i, slides
        end
    end
    return #slides, slides
end

--- Hauteur disponible pour une slide, en lignes.
function M.budget()
    return (vim.g.ccslide_rows or vim.o.lines) - M.overhead
end

--- Largeur disponible pour une ligne, en colonnes.
function M.width_budget()
    return vim.g.ccslide_cols or vim.o.columns
end

-- ============================================================
-- Jauge lualine
-- ============================================================

--- Chaîne d'état : "󰐩 4/12 · 18/19". Vide hors deck.
function M.status()
    if not vim.b.ccslide_deck then
        return ""
    end
    local idx, slides = M.current_index()
    local s = slides[idx]
    local height = s.last - s.first + 1
    return string.format("󰐩 %d/%d · %d/%d", idx, #slides, height, M.budget())
end

--- true si la slide courante ne rentre pas — sert à colorer la jauge.
function M.over_budget()
    if not vim.b.ccslide_deck then
        return false
    end
    local idx, slides = M.current_index()
    local s = slides[idx]
    return (s.last - s.first + 1) > M.budget()
end

-- ============================================================
-- Repli : une slide = un fold
-- ============================================================
function M.foldexpr(lnum)
    local line = vim.fn.getline(lnum)
    if is_sep(line) then
        return ">1"
    end
    return "1"
end

-- ============================================================
-- Actions
-- ============================================================

local function get(buf, first, last)
    return vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
end

local function set(buf, first, last, replacement)
    vim.api.nvim_buf_set_lines(buf, first - 1, last, false, replacement)
end

--- Dernière ligne non vide de la slide (les lignes vides de fin comptent
--- dans la hauteur mdp, inutile d'en empiler).
local function content_end(buf, slide)
    local lines = get(buf, slide.first, slide.last)
    local last = slide.last
    for i = #lines, 1, -1 do
        if vim.trim(lines[i]) ~= "" then
            break
        end
        last = last - 1
    end
    return math.max(last, slide.first)
end

--- Nouvelle slide après la slide courante, curseur sur le titre.
function M.new_slide()
    local buf = 0
    local idx, slides = M.current_index(buf)
    local at = content_end(buf, slides[idx])

    vim.api.nvim_buf_set_lines(buf, at, at, false, { "", "---", "", "## " })
    vim.api.nvim_win_set_cursor(0, { at + 4, 3 })
    vim.cmd("startinsert!")
end

--- Point d'arrêt : mdp attend une touche avant d'afficher la suite.
function M.stop_point()
    local buf = 0
    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(buf, line, line, false, { "<br>" })
    vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
end

function M.goto_slide(delta)
    local idx, slides = M.current_index()
    local target = math.min(math.max(idx + delta, 1), #slides)
    vim.api.nvim_win_set_cursor(0, { slides[target].first, 0 })
    vim.cmd("normal! zz")
end

--- Déplace la slide courante d'un cran. Réinstaure la ligne vide avant
--- le séparateur, sans quoi il cesserait de séparer quoi que ce soit.
function M.move_slide(delta)
    local buf = 0
    local idx, slides = M.current_index(buf)
    local other = idx + delta
    if other < 1 or other > #slides then
        return
    end

    local i1, i2 = math.min(idx, other), math.max(idx, other)
    local a = get(buf, slides[i1].first, slides[i1].last)
    local b = get(buf, slides[i2].first, slides[i2].last)
    local sep = vim.fn.getline(slides[i1].sep)

    local merged = {}
    vim.list_extend(merged, b)
    if vim.trim(merged[#merged] or "") ~= "" then
        table.insert(merged, "")
    end
    table.insert(merged, sep)
    vim.list_extend(merged, a)

    set(buf, slides[i1].first, slides[i2].last, merged)
    vim.api.nvim_win_set_cursor(0, { slides[i1].first + (delta > 0 and #b + 1 or 0), 0 })
end

function M.duplicate_slide()
    local buf = 0
    local idx, slides = M.current_index(buf)
    local body = get(buf, slides[idx].first, content_end(buf, slides[idx]))

    local block = { "", "---", "" }
    vim.list_extend(block, body)

    local at = content_end(buf, slides[idx])
    vim.api.nvim_buf_set_lines(buf, at, at, false, block)
    vim.api.nvim_win_set_cursor(0, { at + 4, 0 })
end

--- Coupe la slide courante (récupérable avec p).
function M.cut_slide()
    local buf = 0
    local idx, slides = M.current_index(buf)
    if #slides == 1 then
        vim.notify("ccslide : le deck n'a qu'une slide", vim.log.levels.WARN)
        return
    end

    local s = slides[idx]
    -- On emporte le séparateur qui suit, ou celui qui précède pour la
    -- dernière slide, afin de ne pas laisser une règle orpheline.
    local first = s.first
    local last = s.sep or s.last
    if not s.sep then
        first = slides[idx - 1].sep
    end

    vim.fn.setreg('"', table.concat(get(buf, s.first, s.last), "\n"), "l")
    set(buf, first, last, {})
    vim.api.nvim_win_set_cursor(0, { math.min(first, vim.api.nvim_buf_line_count(buf)), 0 })
end

--- (Re)génère la slide Sommaire à partir des titres de niveau 2.
function M.toc()
    local buf = 0
    local slides = M.slides(buf)
    local entries, toc_at = {}, nil

    for i, s in ipairs(slides) do
        for _, line in ipairs(get(buf, s.first, s.last)) do
            local title = line:match("^##%s+(.+)$")
            if title then
                if vim.trim(title):lower():match("^sommaire") then
                    toc_at = i
                else
                    table.insert(entries, "- " .. title)
                end
                break
            end
        end
    end

    if #entries == 0 then
        vim.notify("ccslide : aucun titre '## ' à lister", vim.log.levels.WARN)
        return
    end

    local body = { "## Sommaire", "" }
    vim.list_extend(body, entries)

    if toc_at then
        set(buf, slides[toc_at].first, slides[toc_at].last, body)
    else
        local at = content_end(buf, slides[1])
        local block = { "", "---", "" }
        vim.list_extend(block, body)
        vim.api.nvim_buf_set_lines(buf, at, at, false, block)
    end
    vim.notify(string.format("ccslide : sommaire de %d slides", #entries))
end

--- Lance mdp sur la slide du curseur.
--- Volontairement via `:!` et non dans un terminal nvim : mdp reçoit ainsi
--- le terminal entier, exactement la taille sur laquelle la jauge se base.
--- Un onglet nvim lui aurait mangé 3 lignes (tabline, statusline, cmdline)
--- et le budget affiché aurait menti.
function M.present()
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" then
        vim.notify("ccslide : buffer sans fichier", vim.log.levels.ERROR)
        return
    end
    vim.cmd("silent write")

    local idx = M.current_index()
    vim.cmd(string.format("silent !mdp -j %d %s", idx, vim.fn.shellescape(file)))
    vim.cmd("redraw!")
end

--- Bascule entre tes notes (deck.md) et le support importé (prof.md).
function M.toggle_source()
    local current = vim.api.nvim_buf_get_name(0)
    local dir = vim.fn.fnamemodify(current, ":h")
    local name = vim.fn.fnamemodify(current, ":t")
    local other = dir .. "/" .. (name == "deck.md" and "prof.md" or "deck.md")

    if vim.fn.filereadable(other) == 0 then
        vim.notify("ccslide : " .. vim.fn.fnamemodify(other, ":t") .. " absent",
            vim.log.levels.WARN)
        return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(other))
end

-- ============================================================
-- Lint -> diagnostics nvim
-- ============================================================
local timers = {}

local function run_check(buf)
    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" or vim.fn.filereadable(SCRIPT) == 0 then
        return
    end

    local rows = vim.g.ccslide_rows or vim.o.lines
    local cols = M.width_budget()

    vim.system({
        "python3", SCRIPT, "--check", "--json",
        "--rows", tostring(rows), "--cols", tostring(cols), file,
    }, { text = true }, vim.schedule_wrap(function(result)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local ok, decoded = pcall(vim.json.decode, result.stdout or "")
        if not ok or not decoded.problems then
            return
        end

        local diagnostics = {}
        for _, p in ipairs(decoded.problems) do
            table.insert(diagnostics, {
                lnum = math.max(p.line - 1, 0),
                col = 0,
                severity = p.severity == "error"
                    and vim.diagnostic.severity.ERROR
                    or vim.diagnostic.severity.WARN,
                source = "ccslide",
                code = p.code,
                message = p.message,
            })
        end
        vim.diagnostic.set(ns, buf, diagnostics)
    end))
end

--- Lint débouncé. TextChanged part à chaque modification ; sans ce délai,
--- prendre des notes en cours lancerait un process Python par frappe.
function M.check(buf, immediate)
    buf = buf or vim.api.nvim_get_current_buf()

    if timers[buf] then
        timers[buf]:stop()
        if not timers[buf]:is_closing() then
            timers[buf]:close()
        end
        timers[buf] = nil
    end

    local timer = vim.uv.new_timer()
    timers[buf] = timer
    timer:start(immediate and 0 or 250, 0, vim.schedule_wrap(function()
        if timers[buf] == timer then
            timers[buf] = nil
        end
        timer:stop()
        if not timer:is_closing() then
            timer:close()
        end
        if vim.api.nvim_buf_is_valid(buf) then
            run_check(buf)
        end
    end))
end

-- ============================================================
-- Activation (appelée depuis ftplugin/markdown.lua)
-- ============================================================

--- Un deck se reconnaît à son nom de fichier ou à son en-tête mdp.
--- Ouvrir sur un commentaire HTML ne suffit PAS : un markdownlint-disable
--- ou un en-tête de licence en pose un aussi, et le mode slide se serait
--- activé sur des markdown qui n'ont rien à voir. Il faut une clé de
--- métadonnées à l'intérieur du bloc, ce que mdp exige de toute façon.
function M.detect(buf)
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    if name == "deck.md" or name == "prof.md" then
        return true
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, 12, false)
    local i = 1
    while lines[i] and vim.trim(lines[i]) == "" do
        i = i + 1
    end
    if not lines[i] then
        return false
    end

    local first = vim.trim(lines[i])
    if first:match("^%%title:") then  -- forme légacy %title:
        return true
    end
    if not first:match("^<!%-%-") then
        return false
    end

    -- Contenu du bloc de commentaire, délimiteurs retirés.
    local block = {}
    for j = i, math.min(#lines, i + 8) do
        table.insert(block, lines[j])
        if lines[j]:find("%-%->") then
            break
        end
    end
    local text = table.concat(block, "\n"):gsub("<!%-%-", ""):gsub("%-%->", "")
    for _, line in ipairs(vim.split(text, "\n")) do
        if vim.trim(line):match("^%a[%w_%-]*%s*:") then
            return true
        end
    end
    return false
end

function M.attach(buf)
    vim.b[buf].ccslide_deck = true

    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.require'ccslide'.foldexpr(v:lnum)"
    vim.opt_local.foldlevel = 99

    local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = "ccslide: " .. desc })
    end

    -- Alt = namespace du pack cc. <leader> reste libre pour ton code.
    -- <A-CR> ne traverse pas tous les terminaux : <A-s> fait la même chose.
    map("<A-CR>", M.new_slide, "nouvelle slide")
    map("<A-s>", M.new_slide, "nouvelle slide")
    map("<A-b>", M.stop_point, "point d'arrêt <br>")
    map("<A-j>", function() M.goto_slide(1) end, "slide suivante")
    map("<A-k>", function() M.goto_slide(-1) end, "slide précédente")
    map("<A-Down>", function() M.move_slide(1) end, "descendre la slide")
    map("<A-Up>", function() M.move_slide(-1) end, "monter la slide")
    map("<A-d>", M.duplicate_slide, "dupliquer la slide")
    map("<A-x>", M.cut_slide, "couper la slide")
    map("<A-t>", M.toc, "régénérer le sommaire")
    map("<A-p>", M.present, "présenter (mdp)")
    map("<A-o>", M.toggle_source, "bascule deck.md / prof.md")

    vim.keymap.set("i", "<A-CR>", function()
        vim.cmd("stopinsert")
        M.new_slide()
    end, { buffer = buf, silent = true, desc = "ccslide: nouvelle slide" })

    -- VimResized : redimensionner le terminal change le budget, donc le
    -- verdict. Sans ça, les diagnostics resteraient ceux de l'ancienne taille.
    vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "InsertLeave", "VimResized" }, {
        buffer = buf,
        group = vim.api.nvim_create_augroup("ccslide_check_" .. buf, { clear = true }),
        callback = function()
            M.check(buf)
        end,
    })

    M.check(buf, true)
end

return M
