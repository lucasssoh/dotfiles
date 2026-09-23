-- ============================================================
-- PUML_JAVA.LUA — diagramme de classes UML depuis du code Java
-- ============================================================
-- :PumlFromJava [dossier]   (défaut : le paquet du .java courant, sinon cwd)
--
-- Racine d'un projet Maven/Gradle (pom.xml, build.gradle) -> son
-- src/main/java. Sous le dossier choisi, on saute les tests, le code
-- généré et les sorties de build (EXCLUDED) : le diagramme décrit la
-- conception, pas l'outillage. Les viser explicitement reste possible
-- (:PumlFromJava src/test/java), l'exclusion ne porte que plus bas.
--
-- Lit chaque .java du dossier (récursif) avec le parseur treesitter java,
-- et ouvre le diagramme dans un buffer .puml non sauvé : <A-p> pour le
-- voir, :w pour le garder.
--
-- ---- Pourquoi treesitter plutôt que jdtls ------------------------------
-- jdtls connaît mieux les types, mais ses documentSymbol ne portent pas les
-- modificateurs : ni private/protected, ni static, ni abstract -- soit
-- exactement ce qu'un diagramme de classes affiche. treesitter donne la
-- syntaxe exacte, instantanément, sans attendre que jdtls ait indexé, et
-- sur des fichiers pas encore sauvés. Les noms de types suffisent : un
-- type est « du projet » s'il est déclaré dans un des fichiers lus.
--
-- ---- Règles de traduction (celles du cours) ---------------------------
--   extends                  Parent <|-- Enfant
--   implements               Interface <|.. Classe
--   champ d'un type du projet   association navigable, PAS un attribut :
--       T x                  A --> "1" T : x
--       List<T>, Set<T>, T[]... A --> "*" T : x
--       Optional<T>          A --> "0..1" T : x
--   composition (*--, "1" côté propriétaire) quand le cycle de vie est
--   écrit dans le code, ce que seul JPA fait :
--       @OneToMany/@OneToOne avec orphanRemoval = true ou cascade ALL/REMOVE
--       @Embedded, @ElementCollection
--     sans JPA, rien ne dit qu'un objet meurt avec son propriétaire : la
--     composition reste une décision de conception, à prendre en relisant.
--   JPA bidirectionnel : @OneToMany(mappedBy = "x") d'un côté, le champ x
--   de l'autre -> UNE association, sans flèche, rôle et multiplicité à
--   chaque bout. Sans mappedBy, deux références croisées restent deux
--   flèches : rien ne dit que c'est la même association.
--   type du projet utilisé ailleurs (paramètre, retour, corps, ou argument
--   d'un supertype : JpaRepository<User, Long> -> Repo ..> User)
--                            A ..> T          dépendance
--   visibilité : private -, protected #, public +, rien ~ (paquetage) ;
--   dans une interface, rien = public (règle Java).
--   static -> {static}, abstract -> {abstract}, @Data (Lombok) -> <<@Data>>,
--   @Entity / @Embeddable (JPA) -> <<@Entity>> / <<@Embeddable>>.
-- ============================================================

local M = {}

local COLLECTIONS = {
    List = true, ArrayList = true, LinkedList = true, Set = true, HashSet = true,
    TreeSet = true, LinkedHashSet = true, Collection = true, Iterable = true,
    Queue = true, Deque = true, ArrayDeque = true, Stack = true, Vector = true,
}

local function text(node, src)
    return node and vim.treesitter.get_node_text(node, src) or ""
end

local function child_of_type(node, t)
    for c in node:iter_children() do
        if c:type() == t then
            return c
        end
    end
end

--- Mots-clés et annotations d'un nœud `modifiers`. `annots` est une
--- liste de noms ET une table nom -> texte des arguments ("" si aucun),
--- pour lire @OneToMany(orphanRemoval = true).
local function modifiers(node, src)
    local mods, annots = {}, {}
    local m = child_of_type(node, "modifiers")
    if not m then
        return mods, annots
    end
    for c in m:iter_children() do
        local t = c:type()
        if t == "marker_annotation" or t == "annotation" then
            local name = text(c:field("name")[1], src):match("[^.]+$")
            annots[#annots + 1] = name
            annots[name] = text(c:field("arguments")[1], src)
        elseif not c:named() then
            mods[text(c, src)] = true
        end
    end
    return mods, annots
end

local function visibility(mods, in_interface)
    if mods.private then return "-" end
    if mods.protected then return "#" end
    if mods.public or in_interface then return "+" end
    return "~"
end

local function flat(s)
    return (s:gsub("%s+", " "))
end

--- Tous les identifiants de type (et identifiants tout court, pour les
--- appels statiques comme StemBuilder.FIRST) sous `node`.
local function names_under(node, src, out)
    if not node then
        return out
    end
    local t = node:type()
    if t == "type_identifier" or t == "identifier" then
        out[text(node, src)] = true
    end
    for c in node:iter_children() do
        if c:named() then
            names_under(c, src, out)
        end
    end
    return out
end

--- Le type d'un champ, décomposé : { base = "Verb", mult = "*" } si c'est
--- une référence à UN type (éventuellement dans une collection).
local function target(type_node, src)
    local t = type_node:type()
    if t == "type_identifier" then
        return { base = text(type_node, src), mult = "1" }
    elseif t == "array_type" then
        local el = type_node:field("element")[1]
        if el and el:type() == "type_identifier" then
            return { base = text(el, src), mult = "*" }
        end
    elseif t == "generic_type" then
        local base = text(child_of_type(type_node, "type_identifier"), src)
        local args = child_of_type(type_node, "type_arguments")
        local arg = args and args:named_child(0)
        if args and args:named_child_count() == 1 and arg:type() == "type_identifier" then
            if COLLECTIONS[base] then
                return { base = text(arg, src), mult = "*" }
            elseif base == "Optional" then
                return { base = text(arg, src), mult = "0..1" }
            end
        end
    end
end

local function params(node, src)
    local out = {}
    local ps = node:field("parameters")[1]
    if not ps then
        return ""
    end
    for p in ps:iter_children() do
        if p:type() == "formal_parameter" then
            out[#out + 1] = text(p:field("name")[1], src) .. " : " .. flat(text(p:field("type")[1], src))
        elseif p:type() == "spread_parameter" then
            -- int... xs : pas de champ nommé, le type puis le déclarateur.
            local ty = p:named_child(0)
            local decl = child_of_type(p, "variable_declarator")
            out[#out + 1] = text(decl and decl:field("name")[1], src) .. " : " .. flat(text(ty, src)) .. "..."
        end
    end
    return table.concat(out, ", ")
end

--- Le cycle de vie de la cible est-il lié à celui du porteur ? Seul JPA
--- l'écrit : orphanRemoval (un enfant détaché est supprimé), cascade
--- REMOVE/ALL (supprimer le parent supprime les enfants), et les valeurs
--- embarquées, qui n'ont pas d'existence propre. @ManyToOne est exclu
--- même avec une cascade : là, c'est l'enfant qui la porte, et un enfant
--- ne possède pas son parent.
local function composite(annots)
    if annots.Embedded or annots.ElementCollection then
        return true
    end
    for _, rel in ipairs({ "OneToMany", "OneToOne" }) do
        local args = annots[rel]
        if args and (args:find("orphanRemoval%s*=%s*true") or args:find("%%f[%%w]ALL%%f[%%W]") or args:find("%%f[%%w]REMOVE%%f[%%W]")) then
            return true
        end
    end
    return false
end

--- mappedBy = "x" : ce champ est l'autre bout de l'association que porte
--- le champ x du type cible.
local function mapped_by(annots)
    for _, rel in ipairs({ "OneToMany", "OneToOne", "ManyToMany" }) do
        local name = annots[rel] and annots[rel]:match('mappedBy%s*=%s*"([%w_]+)"')
        if name then
            return name
        end
    end
end

local KINDS = {
    class_declaration = "class",
    interface_declaration = "interface",
    enum_declaration = "enum",
    record_declaration = "record",
}

--- Parcourt un fichier : ajoute chaque type déclaré (imbriqués compris)
--- à `types`.
local function collect(src, types)
    local root = vim.treesitter.get_string_parser(src, "java"):parse()[1]:root()
    local pkg = ""
    local pd = child_of_type(root, "package_declaration")
    if pd then
        pkg = text(pd:named_child(0), src)
    end

    local function visit(node, outer)
        local kind = KINDS[node:type()]
        if not kind then
            return
        end
        local name = text(node:field("name")[1], src)
        local full = outer and (outer.name .. "." .. name) or name
        local mods, annots = modifiers(node, src)
        local ty = {
            name = full, pkg = pkg, kind = kind, mods = mods, annots = annots,
            tparams = text(node:field("type_parameters")[1], src),
            extends = {}, implements = {}, fields = {}, methods = {}, constants = {},
            uses = {}, outer = outer,
        }
        types[#types + 1] = ty

        -- Les arguments génériques d'un supertype sont des utilisations :
        -- sans ça, `UserRepository extends JpaRepository<User, Long>` perd
        -- son seul lien avec User, JpaRepository étant hors du projet. Le
        -- supertype lui-même y passe aussi, mais il est déjà une
        -- généralisation et n'en deviendra pas une dépendance.
        names_under(node:field("superclass")[1], src, ty.uses)
        names_under(node:field("interfaces")[1] or child_of_type(node, "extends_interfaces"), src, ty.uses)

        local sc = node:field("superclass")[1]
        if sc then
            local base = sc:named_child(0)
            if base:type() == "generic_type" then
                base = child_of_type(base, "type_identifier")
            end
            ty.extends[#ty.extends + 1] = text(base, src)
        end
        local si = node:field("interfaces")[1] or child_of_type(node, "extends_interfaces")
        if si then
            local list = child_of_type(si, "type_list")
            for c in (list or si):iter_children() do
                if c:named() and c:type() ~= "type_list" then
                    local base = c:type() == "generic_type" and child_of_type(c, "type_identifier") or c
                    -- Une interface qui étend une interface : généralisation.
                    local into = kind == "interface" and ty.extends or ty.implements
                    into[#into + 1] = text(base, src)
                end
            end
        end

        -- Record : ses composants sont ses champs (privés, finals).
        if kind == "record" then
            local ps = node:field("parameters")[1]
            for p in ps:iter_children() do
                if p:type() == "formal_parameter" then
                    ty.fields[#ty.fields + 1] = {
                        vis = "-", name = text(p:field("name")[1], src),
                        type = flat(text(p:field("type")[1], src)), target = target(p:field("type")[1], src), mods = {},
                    }
                end
            end
        end

        local body = node:field("body")[1]
        if not body then
            return
        end
        local members = {}
        for c in body:iter_children() do
            if c:type() == "enum_constant" then
                ty.constants[#ty.constants + 1] = text(c:field("name")[1], src)
            elseif c:type() == "enum_body_declarations" then
                for d in c:iter_children() do
                    members[#members + 1] = d
                end
            else
                members[#members + 1] = c
            end
        end

        local in_iface = kind == "interface"
        for _, c in ipairs(members) do
            local t = c:type()
            if t == "field_declaration" or t == "constant_declaration" then
                local fm, fa = modifiers(c, src)
                -- Une constante d'interface est public static final.
                if t == "constant_declaration" then
                    fm.static = true
                end
                local tnode = c:field("type")[1]
                for _, d in ipairs(c:field("declarator")) do
                    ty.fields[#ty.fields + 1] = {
                        vis = visibility(fm, in_iface), name = text(d:field("name")[1], src),
                        type = flat(text(tnode, src)), target = target(tnode, src), mods = fm,
                        composite = composite(fa),
                        mapped_by = mapped_by(fa),
                    }
                    names_under(d:field("value")[1], src, ty.uses)
                end
            elseif t == "method_declaration" or t == "constructor_declaration" then
                local mm = modifiers(c, src)
                if in_iface and not c:field("body")[1] and not mm.static then
                    mm.abstract = true
                end
                local ret = c:field("type")[1]
                ty.methods[#ty.methods + 1] = {
                    vis = visibility(mm, in_iface), name = text(c:field("name")[1], src),
                    params = params(c, src), ret = ret and flat(text(ret, src)),
                    mods = mm, ctor = t == "constructor_declaration",
                }
                names_under(c:field("parameters")[1], src, ty.uses)
                names_under(ret, src, ty.uses)
                names_under(c:field("body")[1], src, ty.uses)
            elseif KINDS[t] then
                visit(c, ty)
            end
        end
    end

    for c in root:iter_children() do
        visit(c, nil)
    end
end

-- ============================================================
-- Génération
-- ============================================================
local function emit(types)
    -- Deux types du même nom dans deux paquets (un Main par TD, c'est
    -- courant) : PlantUML les fusionnerait. Ceux-là reçoivent un
    -- identifiant qualifié par le paquet ; les autres gardent leur nom.
    local count = {}
    for _, t in ipairs(types) do
        count[t.name] = (count[t.name] or 0) + 1
    end
    local known, by_id = {}, {}
    for _, t in ipairs(types) do
        local id = count[t.name] > 1 and (t.pkg .. "." .. t.name) or t.name
        t.id = id:gsub("%.", "_")
        by_id[t.id] = t
        -- Un type imbriqué est aussi désigné par son nom court.
        -- Pour un type de premier niveau, les deux clés sont le même nom :
        -- l'inscrire deux fois le rendait « ambigu » et coupait toute
        -- relation venue d'un autre paquet.
        local short = t.name:match("[^.]+$")
        for _, key in ipairs(short == t.name and { t.name } or { t.name, short }) do
            known[key] = known[key] or {}
            table.insert(known[key], t)
        end
    end
    --- Comme Java : le type du même paquet d'abord, sinon le seul qui
    --- porte ce nom. Ambigu -> pas de relation plutôt qu'une fausse.
    local function resolve(n, pkg)
        local cands = n and known[n]
        if not cands then
            return nil
        end
        for _, c in ipairs(cands) do
            if c.pkg == pkg then
                return c.id
            end
        end
        return #cands == 1 and cands[1].id or nil
    end

    -- Appariement des deux bouts d'une association JPA bidirectionnelle :
    -- le côté mappedBy dessine la ligne, l'autre côté (`partner`) ne
    -- dessine plus rien, ni flèche ni attribut.
    for _, t in ipairs(types) do
        for _, f in ipairs(t.fields) do
            local other = f.mapped_by and f.target and by_id[resolve(f.target.base, t.pkg) or ""]
            for _, g in ipairs(other and other.fields or {}) do
                if g.name == f.mapped_by and g.target and resolve(g.target.base, other.pkg) == t.id then
                    f.partner, g.merged = g, true
                end
            end
        end
    end

    local L = {
        "@startuml",
        "' Généré par :PumlFromJava depuis le code : à relire, pas à croire.",
        "set separator none",
        "skinparam classAttributeIconSize 0",
        "hide empty members",
        "",
    }
    -- Héritage, puis associations, puis dépendances : l'ordre dans lequel
    -- on lit un diagramme de classes.
    local rel = { gen = {}, assoc = {}, dep = {} }

    local by_pkg, order = {}, {}
    for _, t in ipairs(types) do
        if not by_pkg[t.pkg] then
            by_pkg[t.pkg] = {}
            order[#order + 1] = t.pkg
        end
        table.insert(by_pkg[t.pkg], t)
    end
    local one_pkg = #order == 1

    for _, pkg in ipairs(order) do
        local indent = ""
        if not one_pkg and pkg ~= "" then
            L[#L + 1] = "package " .. pkg .. " {"
            indent = "  "
        end
        for _, t in ipairs(by_pkg[pkg]) do
            local head = t.kind
            if t.kind == "class" and t.mods.abstract then
                head = "abstract class"
            elseif t.kind == "record" then
                head = "class"
            end
            local stereo = {}
            if t.kind == "record" then
                stereo[#stereo + 1] = "<<record>>"
            end
            for _, a in ipairs(t.annots) do
                if a == "Data" or a == "Value" or a == "Builder" or a == "Entity" or a == "Embeddable" then
                    stereo[#stereo + 1] = "<<@" .. a .. ">>"
                end
            end
            -- Le nom entre guillemets seulement s'il le faut (générique, ou
            -- type imbriqué Outer.Inner) : le reste du temps, `class Verb`.
            local decl = (t.tparams == "" and t.id == t.name) and t.name
                or string.format('"%s" as %s', t.name .. flat(t.tparams), t.id)
            L[#L + 1] = string.format("%s%s %s%s%s {", indent, head, decl,
                #stereo > 0 and " " or "", table.concat(stereo, " "))
            for _, c in ipairs(t.constants) do
                L[#L + 1] = indent .. "  " .. c
            end

            local assoc = {}
            for _, f in ipairs(t.fields) do
                local tg = f.target
                local to = tg and resolve(tg.base, t.pkg)
                if f.merged then
                    -- Dessiné par l'autre bout (celui qui porte mappedBy).
                    assoc[to] = true
                elseif to and f.partner then
                    -- Un bout = son rôle (le nom sous lequel l'autre classe le
                    -- voit) et sa multiplicité. Une partie a un seul tout.
                    local g = f.partner
                    local near = string.format("%s %s\\n%s", g.vis, g.name, f.composite and "1" or g.target.mult)
                    local far = string.format("%s %s\\n%s", f.vis, f.name, tg.mult)
                    table.insert(rel.assoc, string.format('%s "%s" %s "%s" %s', t.id, near,
                        f.composite and "*--" or "--", far, to))
                    assoc[to] = true
                elseif to and not f.mods.static and f.composite then
                    -- Une partie a exactement un tout : le "1" est sûr.
                    table.insert(rel.assoc, string.format('%s "1" *-- "%s" %s : %s %s', t.id, tg.mult, to, f.vis, f.name))
                    assoc[to] = true
                elseif to and not f.mods.static then
                    table.insert(rel.assoc, string.format('%s --> "%s" %s : %s %s', t.id, tg.mult, to, f.vis, f.name))
                    assoc[to] = true
                else
                    L[#L + 1] = string.format("%s  %s%s%s : %s", indent, f.mods.static and "{static} " or "",
                        f.vis, f.name, f.type)
                end
            end
            for _, m in ipairs(t.methods) do
                local flags = (m.mods.static and "{static} " or "") .. (m.mods.abstract and "{abstract} " or "")
                L[#L + 1] = string.format("%s  %s%s%s(%s)%s", indent, flags, m.vis, m.name, m.params,
                    m.ret and (" : " .. m.ret) or "")
            end
            L[#L + 1] = indent .. "}"

            for _, p in ipairs(t.extends) do
                local to = resolve(p, t.pkg)
                if to then
                    table.insert(rel.gen, to .. " <|-- " .. t.id)
                    assoc[to] = true
                end
            end
            for _, p in ipairs(t.implements) do
                local to = resolve(p, t.pkg)
                if to then
                    table.insert(rel.gen, to .. " <|.. " .. t.id)
                    assoc[to] = true
                end
            end
            if t.outer then
                table.insert(rel.assoc, t.outer.id .. " +-- " .. t.id)
                assoc[t.outer.id] = true
            end
            local deps = {}
            for n in pairs(t.uses) do
                local to = resolve(n, t.pkg)
                if to and to ~= t.id and not assoc[to] and not deps[to] then
                    deps[to] = true
                end
            end
            local sorted = vim.tbl_keys(deps)
            table.sort(sorted)
            for _, to in ipairs(sorted) do
                table.insert(rel.dep, t.id .. " ..> " .. to)
            end
        end
        if indent ~= "" then
            L[#L + 1] = "}"
        end
        L[#L + 1] = ""
    end

    for _, group in ipairs({ rel.gen, rel.assoc, rel.dep }) do
        if #group > 0 then
            vim.list_extend(L, group)
            L[#L + 1] = ""
        end
    end
    L[#L + 1] = "@enduml"
    return L
end

-- Dossiers sautés SOUS le dossier choisi : tests, sorties de build (où
-- finit le code généré : MapStruct, OpenAPI...), outils.
local EXCLUDED = {
    target = true, build = true, out = true, [".git"] = true, [".idea"] = true,
    [".gradle"] = true, node_modules = true, ["generated-sources"] = true,
}

local function excluded(rel)
    if ("/" .. rel):find("/src/test/", 1, true) then
        return true
    end
    for seg in rel:gmatch("[^/]+") do
        if EXCLUDED[seg] then
            return true
        end
    end
    return false
end

function M.generate(dir)
    if not dir or dir == "" then
        local cur = vim.api.nvim_buf_get_name(0)
        dir = cur:match("%.java$") and vim.fs.dirname(cur) or vim.fn.getcwd()
    end
    dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p")):gsub("/$", "")

    -- La racine d'un projet : son code applicatif, directement.
    local is_root = vim.uv.fs_stat(dir .. "/pom.xml") or vim.uv.fs_stat(dir .. "/build.gradle")
        or vim.uv.fs_stat(dir .. "/build.gradle.kts")
    -- Le diagramme, lui, se range à la racine et porte le nom du projet.
    local home = dir
    if is_root and vim.fn.isdirectory(dir .. "/src/main/java") == 1 then
        dir = dir .. "/src/main/java"
    end

    local files = vim.fs.find(function(name, path)
        return name:match("%.java$") and not excluded(path:sub(#dir + 2) .. "/")
    end, { path = dir, type = "file", limit = math.huge })
    if #files == 0 then
        vim.notify("PumlFromJava : aucun .java sous " .. dir, vim.log.levels.WARN)
        return
    end
    table.sort(files)

    local types = {}
    for _, f in ipairs(files) do
        -- Le buffer s'il est ouvert (même non sauvé), sinon le disque.
        local b = vim.fn.bufnr(f)
        local lines = (b ~= -1 and vim.api.nvim_buf_is_loaded(b)) and vim.api.nvim_buf_get_lines(b, 0, -1, false)
            or vim.fn.readfile(f)
        collect(table.concat(lines, "\n"), types)
    end

    local out = home .. "/" .. vim.fs.basename(home) .. ".puml"
    local buf = vim.fn.bufadd(out)
    vim.fn.bufload(buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, emit(types))
    vim.bo[buf].filetype = "plantuml"
    vim.notify(string.format("PumlFromJava : %d types, %d fichiers (buffer non sauvé : <A-p> pour voir, :w pour garder)",
        #types, #files))
end

return M
