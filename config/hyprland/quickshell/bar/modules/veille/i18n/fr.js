.pragma library

// French message catalog for Veille. Pure data, no logic -- VeilleMessages.qml
// is the only thing that reads this. Slots a template may use: {app}
// (from appLabels below, keyed by the family VeilleContext.qml detected),
// {token} (a sanitized filename/title fragment, withToken pools only),
// {time} (current HH:mm), {hours} (hours elapsed since the "late"
// threshold -- see VeilleMessages.qml's header comment for why that's
// what it means, not "time spent in this app").
//
// appLabels stays deliberately generic for families that cover several
// concrete apps under one regex (see veille.json's appFamilies) --
// "l'IDE" rather than a guessed product name, so a PyCharm session never
// gets called "IntelliJ".
var catalog = {
    appLabels: {
        ide: "l'IDE",
        editor: "l'éditeur",
        terminal: "le terminal",
        browser: "le navigateur",
        reader: "le lecteur",
        media: "le lecteur multimédia",
        chat: "la messagerie",
        game: "le jeu"
    },

    generic: {
        serious: [
            "Le sommeil n'est pas du temps perdu.",
            "Tu n'as pas besoin d'être épuisé pour avoir besoin de dormir.",
            "Il est tard. Ton cerveau le sait déjà.",
            "Tu peux continuer demain.",
            "Dormir, ce n'est pas abandonner la journée. C'est la terminer.",
            "Ton corps compte les heures, même si toi tu ne les comptes plus.",
            "Le repos fait partie du travail, pas sa punition.",
            "Une bonne nuit vaut plus qu'une bonne heure de plus.",
            "Ce que tu ne finis pas ce soir, tu le finiras mieux demain.",
            "Le sommeil est important. Vraiment.",
            "Ton attention a une limite. Elle est probablement déjà dépassée.",
            "La fatigue ne se voit pas toujours dans le miroir.",
            "Rien de ce que tu fais maintenant ne vaut une nuit blanche.",
            "Se coucher maintenant, c'est déjà une bonne décision.",
            "Demain a besoin de toi reposé, pas de toi en avance.",
            "Le temps que tu gagnes ce soir, tu le perds demain."
        ],
        reflective: [
            "Pas fatigué, ou simplement habitué à être fatigué ?",
            "Tu travailles encore. Mais est-ce encore productif ?",
            "Productif, ou simplement incapable de s'arrêter ?",
            "Combien de temps vas-tu encore travailler avant de reconnaître que la journée est terminée ?",
            "Qu'est-ce qui te retient vraiment, là, maintenant ?",
            "Si tu regardes l'heure et que ça te surprend, c'est peut-être une réponse.",
            "Ce que tu fais là, tu l'aurais fait avec autant d'entrain à 15h ?",
            "Tu avances, ou tu tournes juste en rond plus lentement ?",
            "À quel moment 'encore un peu' est devenu 'encore des heures' ?",
            "Est-ce que tu choisis de rester, ou tu n'as juste pas décidé de partir ?",
            "Qu'est-ce que tu perds à arrêter maintenant, vraiment ?",
            "Ton futur toi regarde cette heure-là avec quel regard, à ton avis ?",
            "Ce n'est pas la tâche qui te garde éveillé. C'est autre chose.",
            "Tu restes parce que c'est utile, ou parce que c'est difficile de partir ?",
            "Si quelqu'un d'autre faisait ce que tu fais là, tu lui dirais quoi ?",
            "Ce sera toujours là demain. Toi, un peu moins si tu continues comme ça."
        ],
        provocative: [
            "Encore cinq minutes ? On connaît cette histoire.",
            "Une dernière modification ? Ça fait combien de temps maintenant ?",
            "Tu voulais juste terminer ça. Ça fait combien d'heures ?",
            "Ton futur toi aimerait probablement dormir.",
            "'Juste encore un truc' n'a jamais été juste un truc.",
            "Tu te souviens de la dernière fois où 'presque fini' voulait dire fini bientôt ?",
            "À ce rythme, le lever du soleil va te chronométrer.",
            "Le café de demain matin te dira ce que tu penses de ce choix.",
            "Tu ne négocies pas avec l'heure. Elle avance quand même.",
            "Encore un peu, encore un peu... tu connais la suite.",
            "Ce n'est plus de la persévérance, c'est de l'entêtement.",
            "Tu es sûr que c'est le projet qui a besoin de toi, là, à cette heure ?",
            "Demain-toi va te regarder faire ça et ne pas comprendre.",
            "Il paraît que le sommeil, ça se rattrape. C'est faux, mais vas-y, teste.",
            "Tu tiens un discours que tu ne croirais pas venant de quelqu'un d'autre.",
            "Continue comme ça et demain sera la revanche de cette nuit."
        ],
        humorous: [
            "Ton écran n'a pas sommeil. Toi, si.",
            "Le code compile. Ton cerveau, lui, demande une pause.",
            "Encore une tâche. Puis une autre. Et soudain il est 1h du matin.",
            "À cette heure-ci, même les bugs devraient dormir.",
            "Ton clavier commence à ressembler à un oreiller.",
            "Il y a un monde où tu dors déjà. Ce monde a l'air bien.",
            "Ta chaise a de meilleures habitudes de sommeil que toi.",
            "Statistiquement, personne n'a jamais dit 'quelle bonne idée de rester debout si tard' le lendemain.",
            "Ton café du matin n'est pas encore prêt à pardonner ça.",
            "Il paraît qu'il existe une vie après minuit. Elle s'appelle demain.",
            "À ce stade, ton lit a des raisons de se sentir délaissé.",
            "Les yeux qui piquent, c'est ton corps qui essaie de te dire un truc poliment.",
            "Ton navigateur a plus d'onglets ouverts que toi d'heures de sommeil prévues.",
            "Une dernière chose. Toujours une dernière chose.",
            "Même une horloge de sensibilisation au sommeil pense que tu devrais dormir, là.",
            "À cette heure, ta motivation carbure surtout à l'entêtement."
        ]
    },

    // Pool dédié au passage 23:59:59 -> 00:00:00 -- déclenché une fois,
    // en court-circuitant le cooldown normal (voir VeilleMessages.qml).
    midnight: [
        "Minuit. Une nouvelle journée commence, et toi tu n'as pas fini l'ancienne.",
        "Il est minuit pile. Le bon moment pour t'arrêter, pas pour continuer.",
        "00:00. Techniquement, tu es déjà en train de voler du temps à demain.",
        "Minuit vient de sonner. Rien de ce que tu fais maintenant n'était prévu pour cette heure.",
        "Nouvelle date, même fatigue.",
        "Il est minuit. Demain a officiellement commencé sans que tu aies dormi.",
        "00:00:00 -- le compteur repart à zéro. Le tien aussi, si tu veux bien.",
        "Minuit marque une frontière. Tu peux choisir de la respecter.",
        "La journée d'hier est officiellement terminée. La tienne, moins.",
        "Il est minuit quelque part. Ici, il est minuit partout."
    ],

    byFamily: {
        ide: {
            serious: [
                "Tu es toujours dans {app}. Le code n'ira nulle part cette nuit.",
                "{app} tournera encore demain matin, avec toi reposé devant."
            ],
            reflective: [
                "Tu es toujours dans {app}. Tu voulais vraiment travailler jusqu'à cette heure ?",
                "Ce bug dans {app} sera toujours là demain, probablement moins agaçant."
            ],
            provocative: [
                "Encore du code dans {app} ? Ton cerveau n'est probablement plus aussi performant qu'à 20h.",
                "{app} est ouvert depuis un moment. Toi aussi, visiblement, beaucoup trop longtemps."
            ],
            humorous: [
                "{app} et toi, une histoire d'amour qui devrait se reposer un peu.",
                "Même {app} a fini par arrêter de te suggérer du café, à cette heure."
            ]
        },
        editor: {
            serious: [
                "Tu modifies encore un fichier dans {app}. Le fichier peut attendre demain.",
                "{app} reste ouvert. Ta nuit, elle, ne reste pas."
            ],
            reflective: [
                "Ce que tu écris dans {app} maintenant, tu le relirais avec quel regard demain matin ?",
                "Tu es toujours dans {app}. Est-ce encore un choix, ou juste une habitude ?"
            ],
            provocative: [
                "Tu modifies encore ce fichier dans {app}. À ce stade, ce n'est plus du refactoring.",
                "{app} ouvert à cette heure, ce n'est plus de la productivité, c'est de la résistance."
            ],
            humorous: [
                "{app} ne juge pas. Mais s'il pouvait, il serait fatigué pour toi.",
                "Le curseur clignote dans {app}. Toi aussi, un peu, à cette heure."
            ]
        },
        terminal: {
            serious: [
                "Le terminal tourne encore. Toi, tu devrais t'arrêter.",
                "Cette commande peut attendre demain matin."
            ],
            reflective: [
                "Combien de commandes de plus avant de reconnaître que c'est fini pour ce soir ?",
                "Le terminal reste ouvert parce que toi, tu restes ouvert. Pas pour longtemps, visiblement."
            ],
            provocative: [
                "Encore un terminal ouvert à cette heure. La nuit ne va pas se débugger elle-même à ta place.",
                "Tu enchaînes les commandes. Ton sommeil, lui, ne s'enchaîne toujours pas."
            ],
            humorous: [
                "Le terminal ne dort jamais. Toi, tu devrais.",
                "Ctrl+C n'existe pas pour arrêter une nuit blanche. Dommage."
            ]
        },
        browser: {
            serious: [
                "Le navigateur peut rester ouvert. Toi, tu devrais fermer les yeux.",
                "Ce que tu lis là attendra très bien demain."
            ],
            reflective: [
                "Tu es encore dans le navigateur. C'est de la lecture utile, ou juste de l'évitement du coucher ?",
                "Combien d'onglets de plus avant de reconnaître que c'était l'heure de dormir il y a longtemps ?"
            ],
            provocative: [
                "Encore un onglet ? On connaît cette histoire.",
                "Le navigateur reste ouvert. Ta nuit, elle, se ferme toute seule à ce rythme."
            ],
            humorous: [
                "Un onglet de plus, et le navigateur commence à ressembler à ta liste de bonnes résolutions de sommeil.",
                "Le navigateur a plus d'onglets ouverts que toi d'heures de sommeil prévues."
            ]
        },
        reader: {
            serious: [
                "Ce document sera toujours là demain, et toi plus reposé pour le lire.",
                "La lecture peut attendre. Le sommeil, moins."
            ],
            reflective: [
                "Tu lis encore ce document. Est-ce que ça avance, ou est-ce que tu tournes juste les pages ?",
                "Ce chapitre te retient vraiment, ou c'est juste plus facile de continuer que de t'arrêter ?"
            ],
            provocative: [
                "Encore quelques pages ? On connaît cette histoire aussi.",
                "À ce rythme de lecture, à cette heure, rien ne rentre vraiment plus."
            ],
            humorous: [
                "Le document ne va nulle part. Toi non plus, visiblement, mais pour de mauvaises raisons.",
                "Une page de plus, une page de plus... et soudain il est 1h du matin."
            ]
        },
        media: {
            serious: [
                "Ce que tu regardes sera toujours là demain.",
                "Le contenu peut attendre. Le sommeil ne se rattrape pas aussi bien."
            ],
            reflective: [
                "Tu regardes encore quelque chose. C'est du repos, ou juste une autre façon de repousser le coucher ?",
                "Combien de temps de plus avant que ce ne soit plus vraiment un choix ?"
            ],
            provocative: [
                "'Un dernier épisode' n'a jamais été un dernier épisode.",
                "Le lecteur continue tout seul. Toi, tu pourrais faire pareil et t'arrêter."
            ],
            humorous: [
                "Le bouton 'épisode suivant' ne connaît pas l'heure. Toi si.",
                "À ce stade, c'est le lecteur qui décide de ton coucher, pas toi."
            ]
        },
        chat: {
            serious: [
                "Cette conversation peut attendre demain.",
                "Personne n'a besoin d'une réponse à cette heure-ci, probablement même pas toi."
            ],
            reflective: [
                "Tu es encore en train de discuter. C'est important, ou c'est juste difficile de fermer la fenêtre ?",
                "Cette conversation avancerait-elle vraiment moins bien demain matin ?"
            ],
            provocative: [
                "Encore un message ? Il y en aura toujours un autre.",
                "À cette heure, ce n'est plus une conversation, c'est une habitude de ne pas dormir."
            ],
            humorous: [
                "Les trois petits points qui clignotent depuis 5 minutes, c'est un peu toi à cette heure.",
                "Ta liste de conversations est plus active que ton horloge biologique en ce moment."
            ]
        },
        game: {
            serious: [
                "Le jeu sera toujours là demain. C'est même son travail d'attendre.",
                "Jouer tard a le même coût que travailler tard, pour ton sommeil."
            ],
            reflective: [
                "Encore une partie. Mais est-ce encore vraiment amusant à cette heure ?",
                "Une partie de plus t'apporte quoi de plus, comparé à une heure de sommeil de plus ?"
            ],
            provocative: [
                "Une dernière partie ? On connaît cette histoire aussi, et elle ne s'arrête jamais là.",
                "Le jeu continuera très bien sans toi cette nuit."
            ],
            humorous: [
                "Ton personnage peut se reposer. Toi aussi, en théorie.",
                "Même les PNJ ont un cycle jour/nuit plus sain que le tien, là."
            ]
        }
    },

    // Niveau 2 uniquement -- jamais pour browser/chat/media (voir la
    // règle noTokenFamilies de VeilleContext.qml, appliquée en amont).
    withToken: {
        ide: [
            "{token} peut attendre demain.",
            "Tu modifies encore {token}. À ce stade, ce n'est plus du refactoring.",
            "{token} sera toujours là, et toi plus lucide pour le regarder demain.",
            "Ce que tu fais sur {token} là, tu le referais probablement mieux après une nuit de sommeil.",
            "{token} n'a pas de deadline à minuit passé. Toi, tu as un sommeil à rattraper.",
            "Encore {token} ? Ça fait combien de temps maintenant ?"
        ],
        editor: [
            "{token} peut attendre demain.",
            "Tu es encore sur {token}. Ce fichier ne va nulle part.",
            "{token} tiendra bien jusqu'à demain matin.",
            "Ce n'est plus de l'édition de {token}, c'est de l'insomnie déguisée en travail.",
            "{token} sera exactement où tu l'as laissé, demain, avec toi reposé.",
            "Encore ce fichier, {token}. Ça fait combien d'heures maintenant ?"
        ],
        reader: [
            "{token} peut attendre demain.",
            "Tu lis encore {token}. Quelques pages de moins ce soir, ce n'est pas grave.",
            "{token} sera toujours là, et toi plus concentré pour le lire demain.",
            "Ce chapitre de {token} n'ira nulle part pendant la nuit.",
            "Encore {token} ? Ça fait combien de temps que tu es dessus ?",
            "{token} peut attendre. Ton sommeil, moins."
        ]
    }
};
