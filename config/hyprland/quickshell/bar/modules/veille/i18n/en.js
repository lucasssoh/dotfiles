.pragma library

// English message catalog for Veille -- structural mirror of fr.js, not a
// literal translation of it (tone comes first). See fr.js's header
// comment for the slot list ({app}/{token}/{time}/{hours}) and why
// appLabels stays generic rather than naming a specific product.
var catalog = {
    appLabels: {
        ide: "the IDE",
        editor: "the editor",
        terminal: "the terminal",
        browser: "the browser",
        reader: "the reader",
        media: "the media player",
        chat: "the chat",
        game: "the game"
    },

    generic: {
        serious: [
            "Sleep isn't wasted time.",
            "You don't have to be exhausted to need sleep.",
            "It's late. Your brain already knows that.",
            "You can pick this back up tomorrow.",
            "Sleeping isn't giving up on the day. It's finishing it.",
            "Your body is counting the hours, even if you've stopped.",
            "Rest is part of the work, not a break from it.",
            "A good night is worth more than one more good hour.",
            "Whatever you don't finish tonight, you'll finish better tomorrow.",
            "Sleep matters. Genuinely.",
            "Your attention has a limit. It's probably already past it.",
            "Tiredness doesn't always show up in the mirror.",
            "Nothing you're doing right now is worth an all-nighter.",
            "Going to bed now is already a good decision.",
            "Tomorrow needs you rested, not you ahead of schedule.",
            "The time you save tonight, you lose tomorrow."
        ],
        reflective: [
            "Not tired, or just used to being tired?",
            "You're still working. But is it still productive?",
            "Productive, or just unable to stop?",
            "How much longer will you keep going before admitting the day is over?",
            "What's actually keeping you here, right now?",
            "If the time surprises you when you check it, that might be your answer.",
            "Would you be doing this with the same energy at 3pm?",
            "Are you moving forward, or just circling slower?",
            "At what point did 'a bit longer' become 'hours longer'?",
            "Are you choosing to stay, or did you just never decide to leave?",
            "What do you actually lose by stopping now?",
            "How do you think future-you looks back at this hour?",
            "It's not the task keeping you up. It's something else.",
            "Are you staying because it's useful, or because leaving is hard?",
            "If someone else were doing exactly this, what would you tell them?",
            "This will still be here tomorrow. You'll be a little less here if you keep going."
        ],
        provocative: [
            "Five more minutes? We know how that goes.",
            "One last change? How long has 'one last' been going on?",
            "You just wanted to finish this. How many hours ago was that?",
            "Future-you would probably like some sleep.",
            "'Just one more thing' has never been just one thing.",
            "Remember the last time 'almost done' actually meant done soon?",
            "At this rate, sunrise is going to start timing you.",
            "Tomorrow's coffee will tell you exactly what it thinks of this choice.",
            "You don't get to negotiate with the clock. It moves anyway.",
            "Just a bit more, just a bit more... you know how this ends.",
            "This stopped being persistence a while ago. Now it's just stubbornness.",
            "Are you sure it's the project that needs you, at this hour?",
            "Tomorrow-you is going to watch you do this and not understand it.",
            "They say you can catch up on sleep. You can't, but go ahead, test it.",
            "You're making an argument you wouldn't believe from anyone else.",
            "Keep this up and tomorrow will be tonight's revenge."
        ],
        humorous: [
            "Your screen doesn't get sleepy. You do.",
            "The code compiles. Your brain is filing for a break.",
            "One more task. Then another. And suddenly it's 1am.",
            "At this hour, even the bugs should be asleep.",
            "Your keyboard is starting to look like a pillow.",
            "Somewhere out there, a version of you is already asleep. That version seems fine.",
            "Your chair has better sleep habits than you right now.",
            "Statistically, nobody has ever woken up and said 'what a great call, staying up that late'.",
            "Tomorrow's coffee hasn't forgiven you for this yet.",
            "They say there's life after midnight. It's called tomorrow.",
            "At this point your bed has grounds to feel neglected.",
            "Stinging eyes are your body's polite way of telling you something.",
            "Your browser has more open tabs than you have hours of sleep planned.",
            "One last thing. It's always one last thing.",
            "Even a clock built to remind people to sleep thinks you should sleep now.",
            "At this hour your motivation is running mostly on stubbornness."
        ]
    },

    // Fires once on the 23:59:59 -> 00:00:00 rollover, ahead of the
    // normal cooldown -- see VeilleMessages.qml.
    midnight: [
        "Midnight. A new day just started, and you haven't finished the last one.",
        "It's exactly midnight. Good moment to stop, not to keep going.",
        "00:00. Technically you're already borrowing time from tomorrow.",
        "Midnight just hit. Nothing you're doing now was ever scheduled for this hour.",
        "New date, same tiredness.",
        "It's midnight. Tomorrow has officially started without you having slept.",
        "00:00:00 -- the counter resets. So could yours, if you let it.",
        "Midnight is a line. You get to decide whether to respect it.",
        "Yesterday is officially over. Yours, less so.",
        "It's midnight somewhere. Here, it's midnight everywhere."
    ],

    byFamily: {
        ide: {
            serious: [
                "You're still in {app}. The code isn't going anywhere tonight.",
                "{app} will still be running tomorrow morning, with you rested in front of it."
            ],
            reflective: [
                "You're still in {app}. Did you really mean to work this late?",
                "That bug in {app} will still be there tomorrow, probably less annoying."
            ],
            provocative: [
                "More code in {app}? Your brain probably isn't running at 8pm speed anymore.",
                "{app}'s been open a while. So, clearly, have you -- for way too long."
            ],
            humorous: [
                "You and {app}, a relationship that could use some rest.",
                "Even {app} gave up suggesting more coffee at this hour."
            ]
        },
        editor: {
            serious: [
                "You're still editing a file in {app}. The file can wait until tomorrow.",
                "{app} stays open. Your night doesn't have to."
            ],
            reflective: [
                "What you're writing in {app} right now -- how will it read tomorrow morning?",
                "Are you still in {app} by choice, or just by habit at this point?"
            ],
            provocative: [
                "Still editing that file in {app}? This stopped being refactoring a while ago.",
                "{app} open at this hour isn't productivity anymore, it's resistance."
            ],
            humorous: [
                "{app} doesn't judge. If it could, it'd be tired on your behalf.",
                "The cursor's blinking in {app}. So are you, a little, right about now."
            ]
        },
        terminal: {
            serious: [
                "The terminal's still running. You should probably stop.",
                "That command can wait until morning."
            ],
            reflective: [
                "How many more commands before you admit tonight is over?",
                "The terminal stays open because you do. Not for much longer, by the look of it."
            ],
            provocative: [
                "Another terminal open at this hour. The night isn't going to debug itself for you.",
                "You keep chaining commands. Your sleep still isn't chaining anything."
            ],
            humorous: [
                "The terminal never sleeps. You should.",
                "There's no Ctrl+C for an all-nighter. Shame."
            ]
        },
        browser: {
            serious: [
                "The browser can stay open. You should close your eyes.",
                "Whatever you're reading will keep perfectly well until tomorrow."
            ],
            reflective: [
                "Still in the browser. Is that useful reading, or just avoiding bed?",
                "How many more tabs before you admit it's been bedtime for a while?"
            ],
            provocative: [
                "One more tab? We know this one too.",
                "The browser stays open. Your night is closing itself down at this rate."
            ],
            humorous: [
                "One more tab and the browser starts looking like your list of sleep resolutions.",
                "Your browser has more open tabs than you have hours of sleep planned."
            ]
        },
        reader: {
            serious: [
                "This document will still be here tomorrow, and you'll be more rested for it.",
                "The reading can wait. The sleep can't, not as well."
            ],
            reflective: [
                "Still reading this. Is it sinking in, or are you just turning pages?",
                "Is this chapter really holding you, or is stopping just harder than continuing?"
            ],
            provocative: [
                "A few more pages? We know this one too.",
                "At this reading speed, at this hour, not much of it is actually landing."
            ],
            humorous: [
                "The document isn't going anywhere. Neither are you, clearly, but for worse reasons.",
                "One more page, one more page... and suddenly it's 1am."
            ]
        },
        media: {
            serious: [
                "Whatever you're watching will still be there tomorrow.",
                "The content can wait. Sleep doesn't catch up as well."
            ],
            reflective: [
                "Still watching something. Is that rest, or just another way to delay bed?",
                "How much longer before this stops being a choice?"
            ],
            provocative: [
                "'One more episode' has never been one more episode.",
                "The player just keeps going on its own. You could do the same and stop."
            ],
            humorous: [
                "The 'next episode' button doesn't know what time it is. You do.",
                "At this point the player is deciding your bedtime, not you."
            ]
        },
        chat: {
            serious: [
                "This conversation can wait until tomorrow.",
                "Nobody needs a reply at this hour -- probably not even you."
            ],
            reflective: [
                "Still chatting. Is this important, or just hard to close the window on?",
                "Would this conversation really go worse tomorrow morning?"
            ],
            provocative: [
                "One more message? There's always going to be another one.",
                "At this hour, this isn't a conversation anymore, it's a habit of not sleeping."
            ],
            humorous: [
                "Those three dots that have been blinking for five minutes -- that's kind of you right now.",
                "Your chat list is more active than your circadian rhythm at the moment."
            ]
        },
        game: {
            serious: [
                "The game will still be there tomorrow. Waiting is basically its job.",
                "Gaming late costs your sleep the same way working late does."
            ],
            reflective: [
                "One more match. But is it still actually fun at this hour?",
                "What does one more round get you, compared to one more hour of sleep?"
            ],
            provocative: [
                "One last match? We know this one too, and it never actually stops there.",
                "The game will do just fine without you tonight."
            ],
            humorous: [
                "Your character can rest. So, in theory, can you.",
                "Even the NPCs have a healthier day/night cycle than you right now."
            ]
        }
    },

    // Level 2 only -- never for browser/chat/media (enforced upstream by
    // VeilleContext.qml's noTokenFamilies).
    withToken: {
        ide: [
            "{token} can wait until tomorrow.",
            "Still editing {token}? This stopped being refactoring a while ago.",
            "{token} will still be there, and you'll see it more clearly tomorrow.",
            "Whatever you're doing to {token} right now, you'd probably do it better after some sleep.",
            "{token} doesn't have a deadline past midnight. You have sleep to catch up on.",
            "{token}, again? How long has that been going on now?"
        ],
        editor: [
            "{token} can wait until tomorrow.",
            "Still on {token}. That file isn't going anywhere.",
            "{token} will hold up fine until morning.",
            "This isn't editing {token} anymore, it's insomnia wearing work's clothes.",
            "{token} will be exactly where you left it tomorrow, with you rested.",
            "That file again, {token}. How many hours is that now?"
        ],
        reader: [
            "{token} can wait until tomorrow.",
            "Still reading {token}. A few less pages tonight won't hurt.",
            "{token} will still be there, and you'll be more focused for it tomorrow.",
            "That chapter of {token} isn't going anywhere overnight.",
            "{token}, still? How long have you been on it?",
            "{token} can wait. Your sleep, less so."
        ]
    }
};
