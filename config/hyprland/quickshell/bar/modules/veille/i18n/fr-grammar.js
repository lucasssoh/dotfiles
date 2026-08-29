.pragma library

// FRENCH GRAMMAR -- the pieces grammar.js assembles. Pure data, no logic.
// Read grammar.js's header first: it explains the three levels (pattern /
// fragment / slot) and why the flat catalog in fr.js couldn't get there
// on its own. fr.js is still used, for whole hand-written sentences that
// no grammar would produce -- the two are mixed, see VeilleMessages.qml's
// `curatedRatio`.
//
// FRAGMENT CONTRACT, non-negotiable, checked by tools/veille-lint.mjs:
//   * a complete clause, able to stand between two full stops
//   * lowercase initial (the pattern capitalizes)
//   * NO trailing punctuation (the pattern punctuates)
//   * no internal ". " -- if you need two sentences, that's a pattern
// Breaking any of these produces sentences that look almost right, which
// is worse than obviously wrong: run the linter.
//
// Every field but `t` is optional:
//   tone   -- restrict to these tones; omitted = usable in all five
//   needs  -- every listed facet must be present (see `facets` below)
//   not    -- none of the listed facets may be present
//   when   -- context conditions, ">=3" / "<2" / true / false
//   topic  -- two fragments sharing a topic never land in one sentence
// A {slot} that can't be resolved right now makes the fragment
// ineligible on its own -- that IS the context mechanism, no `when`
// needed for it. See grammar.js's slotValues().

var days = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];

// Elision, applied after the slots are filled -- see grammar.js's
// applyTypography(). A fragment reads "tu es en train de {activite}", and
// {activite} is "coder" for the IDE but "enchaîner des commandes" for the
// terminal: "de enchaîner" is wrong, and no way of writing the fragment
// avoids it, because the vowel only shows up after substitution.
//
// Deliberately as narrow as the problem: "de" alone, before plain vowels
// only. A wider rule is actively harmful here -- an earlier version
// included `que` and produced "on va dire que'oui" (French does not elide
// before "oui"), and including `h` would produce "d'hasard" as readily as
// the correct "d'habitude", since only a dictionary distinguishes an
// aspirated h. Every other elision in this file is in hand-written text,
// where it was simply written correctly the first time. `de` before a
// slot is the one case that can't be.
var typography = [
    [/\b([Dd]e)\s+(?=[aàâeéèêëiîïoôuùû])/g, "$1'"]
];

// Same labels the flat catalog uses -- deliberately generic where one
// family covers several products, so a PyCharm session is never called
// "IntelliJ" (see fr.js's own note).
var appLabels = {
    ide: "l'IDE",
    editor: "l'éditeur",
    terminal: "le terminal",
    browser: "le navigateur",
    reader: "le lecteur",
    media: "le lecteur multimédia",
    chat: "la messagerie",
    game: "le jeu"
};

// What the family lets the whole grammar say, instead of the family
// owning two sentences of its own. `verbe` is 2nd person singular present
// (goes after "tu "), `activite` an infinitive, `objet` a noun phrase
// with its determiner.
var vocab = {
    terminal: { verbe: "tapes",     activite: "enchaîner des commandes", objet: "ce shell" },
    ide:      { verbe: "codes",     activite: "coder",                   objet: "ce fichier" },
    editor:   { verbe: "écris",     activite: "écrire du code",          objet: "ce fichier" },
    browser:  { verbe: "navigues",  activite: "ouvrir des onglets",      objet: "cet onglet" },
    reader:   { verbe: "lis",       activite: "lire",                    objet: "ce document" },
    media:    { verbe: "regardes",  activite: "regarder",                objet: "cet épisode" },
    chat:     { verbe: "discutes",  activite: "discuter",                objet: "cette conversation" },
    game:     { verbe: "joues",     activite: "jouer",                   objet: "cette partie" }
};

// The compatibility layer: this is what stops "le code compile" landing
// on an episode of a series, mechanically rather than by hoping the
// author remembered. An unrecognized window has NO facets, so every
// fragment carrying a `needs` drops out and only the context-free ones
// remain -- the correct degradation, not a special case.
var facets = {
    terminal: ["travail", "actif", "solo", "machine", "texte"],
    ide:      ["travail", "actif", "solo", "machine", "texte", "code"],
    editor:   ["travail", "actif", "solo", "machine", "texte", "code"],
    browser:  ["actif", "solo", "machine", "lecture"],
    reader:   ["passif", "solo", "lecture", "texte"],
    media:    ["loisir", "passif", "solo", "image"],
    chat:     ["loisir", "actif", "social", "texte"],
    game:     ["loisir", "actif", "solo", "image"]
};

// ---- patterns -------------------------------------------------------------
// The rhetorical shapes. `weight` is relative; the short ones (a single
// clause, no verdict, no chute) carry a deliberate ~18% of the total mass
// because a message system whose every line is "statement + punchline"
// stays recognizable however many statements you write.
var patterns = [
    { shape: "<constat>. <verdict>.",              weight: 5 },
    { shape: "<constat>. <chute>.",                weight: 5 },
    { shape: "<temps>. <constat_court>.",          weight: 4 },
    { shape: "<question> ?",                       weight: 5 },
    { shape: "<question> ? <relance> ?",           weight: 3 },
    { shape: "<concession>, <retournement>.",      weight: 4 },
    { shape: "<amorce>. <dementi>.",               weight: 4, tone: ["provocative", "humorous"] },
    { shape: "<amorce>, <retournement>.",          weight: 2, tone: ["provocative", "humorous"] },
    { shape: "<constat>, et <consequence>.",       weight: 3 },
    { shape: "<imperatif>. <justification>.",      weight: 4, tone: ["serious", "tender"] },
    { shape: "<constat>. <imperatif>.",            weight: 2, tone: ["serious", "tender"] },
    { shape: "<constat>. <question> ?",            weight: 4 },
    { shape: "<temps>. <verdict>.",                weight: 3 },
    { shape: "<question> ? <chute>.",              weight: 3 },
    { shape: "<constat>. <dementi>.",              weight: 2, tone: ["provocative", "humorous"] },
    { shape: "<consequence>. <justification>.",    weight: 2, tone: ["serious", "reflective", "tender"] },
    { shape: "<temps>. <chute>.",                  weight: 3 },

    // The dry register -- one clause, no landing. Asked for explicitly.
    { shape: "<constat_court>.",                   weight: 4 },
    { shape: "<temps>.",                           weight: 3 },
    { shape: "<constat_court>. <chute>.",          weight: 3 },
    { shape: "<imperatif>.",                       weight: 2, tone: ["serious", "tender"] }
];

// ---- banks ----------------------------------------------------------------
var banks = {

    // Temporal framing. Almost everything here carries topic "heure", so
    // it never doubles up with a constat that also names the hour.
    temps: [
        { t: "il est {time}", topic: "heure" },
        { t: "on est déjà à {time}", topic: "heure" },
        { t: "{time}", topic: "heure" },
        { t: "l'horloge dit {time}", topic: "heure" },
        // {jour} is the CURRENT weekday, so past midnight it names the day
        // that just started, not the evening the user is still in -- "il
        // est 01:20, un samedi" when they mean Friday night. Gated rather
        // than reworded: before midnight it's simply correct.
        { t: "il est {time}, un {jour}", topic: "heure", when: { midnightPassed: false } },
        { t: "on est {jour}, il est {time}", topic: "heure", when: { midnightPassed: false } },
        { t: "il est {time}, si ça t'intéresse", topic: "heure", tone: ["provocative", "humorous"] },
        { t: "il est {time}, ce qui n'est plus vraiment une heure", topic: "heure", tone: ["provocative", "humorous"] },
        { t: "minuit est passé", topic: "heure", when: { midnightPassed: true } },
        { t: "c'est déjà demain", topic: "heure", when: { midnightPassed: true } },
        { t: "on a changé de jour", topic: "heure", when: { midnightPassed: true } },
        { t: "la date a tourné pendant que tu regardais ailleurs", topic: "heure", when: { midnightPassed: true } },
        { t: "la soirée est finie depuis {hours} h", topic: "heure" },
        { t: "ça fait {hours} heures que la journée aurait dû s'arrêter", topic: "heure" },
        { t: "il est plus tard que tu ne crois", topic: "heure" },
        { t: "l'heure raisonnable est loin derrière", topic: "heure" },
        { t: "la nuit est déjà bien avancée", topic: "heure" },
        { t: "{time}, et ça continue", topic: "heure" },
        { t: "il est tard, même pour toi", topic: "heure" },
        { t: "on approche de l'heure où plus rien n'est une bonne idée", topic: "heure", tone: ["provocative", "humorous", "reflective"] },
        { t: "c'est le {soirs}e soir de suite", topic: "serie", when: { streak: ">=3" } },
        { t: "trois heures du matin n'est plus si loin", topic: "heure", when: { midnightPassed: true }, tone: ["provocative", "humorous"] },
        { t: "il est {time}, et c'est calme partout ailleurs", topic: "heure", tone: ["reflective", "tender"] }
    ],

    // Full observational clauses -- the workhorse bank, where most of the
    // context actually lands.
    constat: [
        { t: "tu es encore dans {app}", topic: "app" },
        { t: "tu {verbe} encore", topic: "app" },
        { t: "tu es toujours devant {objet}", topic: "app" },
        { t: "{objet} est toujours ouvert", topic: "app" },
        { t: "ça fait {heuresApp} h que tu es dans {app}", topic: "app" },
        { t: "tu n'as pas quitté {app} depuis {heuresApp} h", topic: "app" },
        { t: "ça fait {heuresApp} h que la même fenêtre est devant toi", topic: "app" },
        { t: "tu es encore sur {token}", topic: "app" },
        { t: "{token} est ouvert depuis un moment", topic: "app" },
        { t: "tu es en train de {activite} à {time}", topic: "app" },

        { t: "tu sautes d'une fenêtre à l'autre sans en finir aucune", topic: "churn", when: { churn: ">=5" } },
        { t: "tu as changé d'écran une dizaine de fois dans la dernière demi-heure", topic: "churn", when: { churn: ">=5" } },
        { t: "tu cherches quelque chose à faire plus que tu ne fais quelque chose", topic: "churn", when: { churn: ">=5" }, tone: ["reflective", "provocative"] },

        { t: "c'est le {soirs}e soir de suite que tu es encore debout à cette heure", topic: "serie", when: { streak: ">=3" } },
        { t: "ça fait {soirs} soirs que la même scène se rejoue", topic: "serie", when: { streak: ">=3" } },
        { t: "tu as pris l'habitude, et ça se voit", topic: "serie", when: { streak: ">=3" }, tone: ["reflective", "provocative", "tender"] },

        { t: "l'écran est la seule chose allumée ici", topic: "ecran" },
        { t: "le silence autour de toi dure depuis un moment", tone: ["reflective", "tender", "serious"] },
        { t: "tu es le seul debout dans cette histoire" },
        { t: "la journée est finie, mais pas toi" },
        { t: "personne ne t'a demandé de finir ce soir", topic: "cesoir" },
        { t: "rien de ce que tu fais là n'était prévu pour cette heure" },
        { t: "tu continues surtout par habitude", tone: ["reflective", "provocative", "serious"] },
        { t: "tu as arrêté de décider il y a un moment", tone: ["reflective", "provocative"] },
        { t: "tes yeux ont lâché avant toi" },
        { t: "tu tiens encore, mais de moins en moins bien" },
        { t: "ton corps compte les heures même si toi tu as arrêté" },
        { t: "la fatigue est déjà là, elle attend juste que tu la remarques", tone: ["reflective", "serious", "tender"] },
        { t: "il y a {hours} heures tu disais que tu arrêtais bientôt", tone: ["provocative", "humorous", "reflective"] },
        { t: "tu confonds être occupé et être utile", tone: ["reflective", "provocative"] },
        { t: "tu es assis là depuis plus longtemps que tu ne crois" },

        { t: "tu relis la même chose depuis un moment", needs: ["lecture"] },
        { t: "tu tapes plus lentement qu'il y a deux heures", needs: ["machine"] },
        { t: "les erreurs que tu fais maintenant, tu ne les faisais pas à 20 h", needs: ["code"] },
        { t: "ça défile devant toi sans que tu suives vraiment", needs: ["passif"] },
        { t: "la conversation tourne au ralenti, comme toi", needs: ["social"] },
        { t: "tu joues moins bien qu'il y a deux heures et tu le sais", needs: ["loisir", "actif"], tone: ["provocative", "humorous", "reflective"] }
    ],

    // Two to six words. These carry the dry register on their own.
    constat_court: [
        { t: "il est tard", topic: "heure" },
        { t: "c'est l'heure", topic: "heure" },
        { t: "tu {verbe} toujours", topic: "app" },
        { t: "{app} peut attendre", topic: "app" },
        { t: "{objet} peut attendre", topic: "app" },
        { t: "{token} peut attendre", topic: "app" },
        { t: "la journée est finie" },
        { t: "c'est fini pour ce soir", topic: "cesoir" },
        { t: "assez pour ce soir", topic: "cesoir" },
        { t: "ça suffit" },
        { t: "tu es fatigué" },
        { t: "tu le sais déjà" },
        { t: "demain existe" },
        { t: "rien ne presse" },
        { t: "personne n'attend" },
        { t: "ça ne rentre plus" },
        { t: "tu n'avances plus" },
        { t: "le lit existe", tone: ["humorous", "provocative", "tender"] },
        { t: "ton cerveau a fermé", tone: ["humorous", "provocative"] },
        { t: "tu tournes en rond", topic: "churn", when: { churn: ">=5" } },
        { t: "c'est déjà trop" },
        { t: "il est trop tard pour ça", topic: "heure" }
    ],

    verdict: [
        // `not: ["loisir"]` rather than `needs: ["travail"]`: a verdict
        // about productivity is wrong on an episode of a series, but it's
        // perfectly fine when the window is unrecognized -- and an
        // unrecognized window has no facets at all, so `needs` would
        // silently drop these from the largest context there is.
        { t: "ce n'est plus du travail", tone: ["serious", "reflective"], not: ["loisir"] },
        { t: "ce n'est plus productif", tone: ["serious"], not: ["loisir"] },
        { t: "le rendement est derrière toi depuis longtemps", tone: ["serious", "provocative"], not: ["loisir"] },
        { t: "ça ne rend service à personne", tone: ["serious"] },
        { t: "rien d'urgent n'existe à cette heure", tone: ["serious", "reflective"], topic: "heure" },
        { t: "le repos fait partie du travail, pas de sa punition", tone: ["serious"] },
        { t: "ce que tu gagnes ici, tu le perds demain", tone: ["serious", "reflective"], topic: "demain" },

        { t: "ce n'est plus une décision, c'est une inertie", tone: ["reflective"] },
        { t: "ce n'est pas la tâche qui te retient", tone: ["reflective"] },
        { t: "il y a une différence entre continuer et ne pas savoir s'arrêter", tone: ["reflective"] },
        { t: "ce n'est pas du courage, c'est de la fatigue déguisée", tone: ["reflective", "provocative"] },
        { t: "l'important n'est plus dans cette fenêtre", tone: ["reflective"], topic: "app" },
        { t: "ce n'est plus un choix, c'est une pente", tone: ["reflective"] },

        { t: "ce n'est plus de la persévérance, c'est de l'entêtement", tone: ["provocative"] },
        { t: "ce n'est plus de la rigueur, c'est de la mise en scène", tone: ["provocative"] },
        { t: "ce n'est plus du travail, c'est de l'évitement", tone: ["provocative"], not: ["loisir"] },
        { t: "tu appelles ça finir, personne d'autre ne le ferait", tone: ["provocative"] },
        { t: "ce n'est plus une session, c'est un siège", tone: ["provocative"] },
        { t: "à ce stade, tu négocies surtout avec toi-même", tone: ["provocative", "reflective"] },

        { t: "à ce stade, c'est de la performance artistique", tone: ["humorous"] },
        { t: "c'est officiellement du sport d'endurance", tone: ["humorous"] },
        { t: "techniquement, c'est de l'insomnie avec un clavier", tone: ["humorous"] },
        { t: "on appelle ça un record, pas un résultat", tone: ["humorous"] },
        { t: "c'est moins une soirée qu'une prise d'otage", tone: ["humorous"] },
        { t: "il n'y a plus de plan, juste de l'élan", tone: ["humorous", "provocative"] },

        { t: "ce n'est pas grave, mais c'est assez", tone: ["tender"] },
        { t: "tu as le droit de t'arrêter là", tone: ["tender"] },
        { t: "ça a été une longue journée", tone: ["tender"] },
        { t: "personne ne te demande plus rien ce soir", tone: ["tender"], topic: "cesoir" },
        { t: "tu en as fait assez", tone: ["tender"] },
        { t: "ce n'est pas de la paresse, c'est du repos", tone: ["tender"] },
        { t: "ça ira mieux demain, sincèrement", tone: ["tender"], topic: "demain" }
    ],

    question: [
        { t: "qu'est-ce qui te retient vraiment", topic: "insistance" },
        { t: "tu comptes t'arrêter quand" },
        { t: "c'est encore utile, ou juste ouvert", topic: "app" },
        { t: "tu restes, ou tu n'as juste pas décidé de partir" },
        { t: "ça avance encore, à ton avis" },
        { t: "tu dirais quoi à quelqu'un d'autre à ta place" },
        { t: "{objet} a vraiment besoin de toi maintenant", topic: "app" },
        { t: "{token} a besoin de toi à {time}", topic: "app" },
        { t: "tu es fatigué, ou juste habitué à l'être" },
        { t: "à quel moment est-ce que ça devient trop" },
        { t: "qu'est-ce que tu perdrais à arrêter là" },
        { t: "tu as commencé ça il y a combien de temps" },
        { t: "tu {verbe} encore par choix, là", topic: "app" },
        { t: "il te faut quoi comme signal" },
        { t: "ça te surprend, l'heure qu'il est", topic: "heure" },
        { t: "c'est encore ce soir, ou c'est déjà demain", topic: "heure" },
        { t: "tu te souviens de ce que tu voulais finir en commençant" },
        { t: "tu regarderas ça demain matin avec quel regard", topic: "demain" },
        { t: "tu es sûr que c'est {app} le problème", topic: "app", tone: ["provocative", "humorous", "reflective"] },
        { t: "combien de fois tu as dit encore cinq minutes ce soir", tone: ["provocative", "humorous"], topic: "cesoir" },
        { t: "il reste quoi à sauver de cette soirée", tone: ["provocative", "reflective"] },
        { t: "qu'est-ce qui se passe si tu fermes maintenant" },
        { t: "ça t'apporte quoi de plus qu'une heure de sommeil" },
        { t: "tu attends quoi, exactement" },
        { t: "tu penses tenir combien de temps comme ça" },
        { t: "{soirs} soirs de suite, tu comptes aller jusqu'où", topic: "serie", when: { streak: ">=3" } },
        { t: "c'est vraiment ce que tu voulais faire de cette nuit", tone: ["reflective", "serious", "tender"] },
        { t: "tu as encore la tête à ça", needs: ["travail"] },
        { t: "ça te détend vraiment, à cette heure", needs: ["loisir"], tone: ["reflective", "provocative"] }
    ],

    // Short second question, only ever after another one.
    // Short second question, only ever after another one. The four bare
    // insistence words share a topic with the questions that already
    // contain one, so "Qu'est-ce qui te retient vraiment ? Vraiment ?"
    // can't happen.
    relance: [
        { t: "vraiment", topic: "insistance" },
        { t: "honnêtement", topic: "insistance" },
        { t: "sincèrement", topic: "insistance" },
        { t: "sans mentir", topic: "insistance" },
        { t: "tu as une réponse" },
        { t: "ou tu fais semblant", tone: ["provocative", "humorous"] },
        { t: "ou tu évites juste d'aller te coucher", tone: ["provocative", "reflective"] },
        { t: "ou tu n'y as pas réfléchi", tone: ["reflective", "provocative"] },
        { t: "ou tu préfères ne pas savoir", tone: ["provocative", "reflective"] },
        { t: "ou c'était rhétorique", tone: ["humorous", "provocative"] },
        { t: "tu veux qu'on en reparle demain matin", tone: ["provocative", "humorous"], topic: "demain" },
        { t: "ça se défend", tone: ["reflective", "tender"] }
    ],

    chute: [
        { t: "ton lit, lui, n'a pas bougé", topic: "lit" },
        { t: "l'écran, lui, s'en fiche", topic: "ecran" },
        { t: "le café de demain n'a rien pardonné", topic: "demain", tone: ["humorous", "provocative"] },
        { t: "demain n'a rien prévu pour compenser", topic: "demain" },
        { t: "le sommeil, lui, ne se rattrape pas", tone: ["serious", "reflective"] },
        { t: "personne ne relira cette heure-ci", topic: "heure" },
        { t: "{app} sera encore là demain", topic: "app" },
        { t: "{objet} sera exactement où tu l'as laissé", topic: "app" },
        { t: "{token} n'a aucune échéance cette nuit", topic: "app" },
        { t: "la nuit avance sans toi de toute façon" },
        { t: "ton réveil, lui, est déjà réglé", topic: "demain" },
        { t: "ta chaise a de meilleures habitudes de sommeil que toi", tone: ["humorous"] },
        { t: "même les bugs se sont couchés", needs: ["code"], tone: ["humorous"] },
        { t: "le clavier commence à ressembler à un oreiller", needs: ["machine"], tone: ["humorous"] },
        { t: "ton horloge biologique a démissionné il y a deux heures", tone: ["humorous", "provocative"] },
        { t: "il paraît que des gens dorment, à cette heure", tone: ["humorous"], topic: "heure" },
        { t: "quelque part, quelqu'un fait le bon choix", tone: ["humorous", "reflective"] },
        { t: "demain-toi n'a pas voix au chapitre, et c'est bien dommage", topic: "demain", tone: ["humorous", "provocative"] },
        { t: "tu peux poser tout ça", tone: ["tender", "serious"] },
        { t: "il n'y a rien à prouver ce soir", tone: ["tender", "serious"], topic: "cesoir" },
        { t: "ça peut s'arrêter là, sans drame", tone: ["tender"] },
        { t: "personne ne compte les points", tone: ["tender", "humorous"] },
        { t: "tu as le droit d'appeler ça fini", tone: ["tender"] },
        { t: "la journée a assez duré", tone: ["tender", "serious"] },
        { t: "c'est déjà bien", tone: ["tender"] },
        { t: "le reste attendra très bien", tone: ["tender", "serious"] },
        { t: "et pourtant tu es toujours là", tone: ["provocative", "reflective"] },
        { t: "l'heure, elle, ne négocie pas", topic: "heure", tone: ["serious", "provocative"] }
    ],

    concession: [
        { t: "d'accord, ça avance", not: ["passif"] },
        { t: "soit, tu es lancé" },
        { t: "admettons que ce soit important" },
        { t: "je veux bien croire que c'est presque fini" },
        { t: "c'est vrai, tu as bien travaillé", needs: ["travail"] },
        { t: "personne ne dit le contraire" },
        { t: "c'est peut-être vrai" },
        { t: "on va dire que oui" },
        { t: "tu tiens peut-être quelque chose" },
        { t: "ça se comprend" },
        { t: "c'était une bonne raison, il y a trois heures", tone: ["provocative", "humorous"] },
        { t: "l'élan est réel" },
        { t: "d'accord, tu es concentré", not: ["passif"] },
        { t: "oui, c'est agréable", needs: ["loisir"] }
    ],

    retournement: [
        { t: "mais toi, tu recules" },
        { t: "mais plus à cette heure", topic: "heure" },
        { t: "mais pas à ce prix" },
        { t: "mais tu le paieras demain", topic: "demain" },
        { t: "mais ce n'est plus le moment" },
        { t: "mais tu ne le sauras qu'au réveil", topic: "demain" },
        { t: "mais l'heure ne négocie pas", topic: "heure" },
        { t: "mais c'est fini quand même" },
        { t: "mais ça attendra demain", topic: "demain" },
        { t: "mais tu n'as plus les moyens de le faire bien" },
        { t: "mais demain sera moins clément", topic: "demain" },
        { t: "mais tu n'es plus au niveau, là", tone: ["provocative", "reflective"] },
        { t: "mais ça ne suffit pas à justifier {time}", topic: "heure", tone: ["provocative"] },
        { t: "mais tu peux poser ça quand même", tone: ["tender"] },
        { t: "mais ça ne t'oblige à rien", tone: ["tender"] }
    ],

    consequence: [
        { t: "demain commencera sans toi", topic: "demain" },
        { t: "tu perdras demain le temps que tu gagnes maintenant", topic: "demain" },
        { t: "la matinée en fera les frais", topic: "demain" },
        { t: "il faudra bien le payer quelque part", topic: "demain" },
        { t: "tu relirais ça demain sans le reconnaître", topic: "demain", needs: ["texte"] },
        { t: "le réveil ne va pas se décaler tout seul", topic: "demain" },
        { t: "il te restera de la fatigue, pas du travail", topic: "demain", not: ["loisir"] },
        { t: "demain sera plus long que ce soir", topic: ["demain", "cesoir"] },
        { t: "tu vas t'en vouloir vers huit heures", topic: "demain", tone: ["provocative", "humorous"] },
        { t: "la nuit sera courte de toute façon" },
        { t: "ce que tu fais là, tu le referas demain", topic: "demain", needs: ["travail"] },
        { t: "tu commenceras demain déjà fatigué", topic: "demain" }
    ],

    imperatif: [
        { t: "ferme ça", tone: ["serious", "tender"] },
        { t: "arrête-toi là", tone: ["serious", "tender"], topic: "arret" },
        { t: "va dormir", tone: ["serious", "tender"] },
        { t: "pose tout", tone: ["serious", "tender"] },
        { t: "laisse {objet} tranquille", topic: "app", tone: ["serious", "tender"] },
        { t: "laisse {app} ouvert et va te coucher", topic: "app", tone: ["serious", "tender"] },
        { t: "sauvegarde et arrête", needs: ["travail"], tone: ["serious"], topic: "arret" },
        { t: "coupe là", tone: ["serious"] },
        { t: "accorde-toi la nuit", tone: ["tender"] },
        { t: "laisse demain faire sa part", topic: "demain", tone: ["tender", "serious"] },
        { t: "fais-toi cette faveur", tone: ["tender"] },
        { t: "arrête pendant que c'est encore un choix", tone: ["serious", "tender"], topic: "arret" },
        { t: "éteins et va te coucher", tone: ["serious"] },
        { t: "range ta soirée", tone: ["tender", "serious"] },
        { t: "souffle un coup et va dormir", tone: ["tender"] }
    ],

    justification: [
        { t: "le reste tiendra jusqu'à demain", topic: "demain" },
        { t: "personne n'attend ça cette nuit" },
        { t: "ce sera toujours là" },
        { t: "rien ne disparaît si tu fermes" },
        { t: "tu le feras mieux reposé", topic: "demain" },
        { t: "ça ne prendra pas plus de temps demain", topic: "demain" },
        { t: "il n'y a pas d'urgence réelle" },
        { t: "tu as déjà fait ta part" },
        { t: "tu as tenu, ça compte" },
        { t: "{app} ne va nulle part", topic: "app" },
        { t: "{token} sera exactement pareil demain", topic: "app" },
        { t: "la nuit t'en apprendra plus que l'heure qui vient", tone: ["reflective", "tender"] },
        { t: "ce n'est pas une défaite" },
        { t: "personne ne saura à quelle heure tu t'es arrêté", topic: "arret" }
    ],

    // Fausses évidences -- la phrase qu'on se dit à soi-même.
    amorce: [
        { t: "encore cinq minutes" },
        { t: "juste un dernier truc" },
        { t: "c'était presque fini" },
        { t: "une dernière et j'arrête" },
        { t: "je finis ça et je me couche" },
        { t: "il reste juste un détail" },
        { t: "c'est bientôt bon" },
        { t: "cinq minutes, pas plus" },
        { t: "je regarde vite fait et j'arrête", needs: ["passif"] },
        { t: "encore une ligne", needs: ["code"] },
        { t: "encore une commande", needs: ["machine"], not: ["code"] },
        { t: "encore un onglet", needs: ["lecture", "machine"] },
        { t: "encore un épisode", needs: ["image", "passif"] },
        { t: "encore une partie", needs: ["loisir", "actif"] },
        { t: "encore un message", needs: ["social"] },
        { t: "encore une page", needs: ["lecture"], not: ["machine"] },
        { t: "je note ça et j'y vais" },
        { t: "je lance juste ça et j'arrête", needs: ["machine"] }
    ],

    dementi: [
        { t: "on connaît la suite" },
        { t: "on connaît cette histoire" },
        { t: "ça fait {hours} h que c'est presque fini", topic: "heure" },
        { t: "personne n'y croit, toi non plus" },
        { t: "ce n'a jamais été juste un truc" },
        { t: "ça n'a jamais voulu dire ça" },
        { t: "tu t'entends" },
        { t: "et il est {time}", topic: "heure" },
        { t: "ça fait {soirs} soirs que tu le dis", topic: "serie", when: { streak: ">=3" } },
        { t: "personne n'est dupe, surtout pas ton réveil", topic: "demain" },
        { t: "et tu es toujours assis là" },
        { t: "la dernière fois non plus, ce n'était pas la dernière" },
        { t: "tu disais déjà ça il y a {hours} heures", topic: "heure" },
        { t: "c'est la version du soir de cette promesse" }
    ]
};

var grammar = {
    days: days,
    typography: typography,
    appLabels: appLabels,
    vocab: vocab,
    facets: facets,
    patterns: patterns,
    banks: banks
};
