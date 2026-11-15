# Programme

A study agenda in the bar, optional (`init` asks). It reads your timetable, plans study sessions around your courses and your evenings, rings them, and opens each subject's course when its session starts: [Boussole](https://github.com/lucasssoh/Boussole) for a subject that is there, any command you choose otherwise. What a session holds is the course's business; Programme says which subject, when and for how long.

**In the bar.** Right of the clock: the next session and its subject (`A&C · 20:30`, `Alternance · 20:30`), outlined with a countdown in its last 15 minutes, then `now` while it waits to be started. During a session, a ring that empties over a 25-minute Pomodoro, with its 5-minute break; `elsewhere` while the course is not in front. Click it, or press `Super + D`, for the drawer.

**Alerts.** A session's start opens in the bar's central island, like Veille, with a chime: `Tonight · A&C`, `20:30 – 22:00 · 1 h 30`, with `Start`, `In 30 min` and `Tomorrow`. It stays until you answer, comes back 15 minutes later if nothing started, and waits out a fullscreen game or zen mode. At the session's end, `A&C · done?` asks for `Done`. The evening before, a notification sums up tomorrow; a course cancelled or moved in the timetable, today or tomorrow, gets one too. Nothing after the latest end of the evening.

**The drawer.** A panel from under the bar to the bottom of the screen, flush with its left edge, sliding in from the left.

| Tab | What it holds |
|---|---|
| **Today** | The session under way with `Launch` and `Done`, the next one with `Start` and `Later`, `Start a session`, the courses of the day still ahead (else the next day's) with their room, and what comes after |
| **Week** | The seven days ahead: courses with their room, and sessions |
| **More** | Exams and hand-ins, rhythm, subjects, calendars, settings, and the first run again |

**Sessions.** A counted slot first takes the tutorials to prepare and the tasks you typed, then the rest of it goes to one subject. Subjects take turns, and share the time by how you rate yourself in each and how close its exam is. Projects and hand-ins are spread up to 3 days before they are due, and a campaign gets its daily time. A subject gets no sessions after its last exam and its last course.

**Starting a session.** `Start` (in the alert or under Today) runs the subject's command; `Launch` runs it again. The browser window that opens Boussole comes to the front, even from another workspace. While the session lasts, its time counts only while the course's window is in front: your default browser on Boussole. Notifications keep quiet there and wait in the history; anywhere else they show as usual. A subject without a command opens nothing and its time is the session's. `Done` ends the session. Under Today, `Start a session` starts one right away: a subject, then 30 minutes to an hour and a half (`programme free 45 A&C`, or `libre 45m` in the quick add).

**Subjects.** In More › Subjects, each subject has a level, *Behind* (more time), *Shaky*, *Fine* or *Tutorials only* (no sessions of its own, only its tutorials to prepare, its projects and its exams), and what its sessions open: nothing, Boussole on the subject's folder (`boussole open {folder} --resume`), or a command you type, `{folder}` standing for the subject's folder. From a terminal: `programme subject level A&C behind`, `programme subject launch A&C on`, `programme subject launch L&MC liseuse {folder}/00_Index.md`, `programme subject launch L&MC off`.

**Later.** `Later` asks until when: in 30 minutes, in an hour, tomorrow, the day after, or a time or a day you type (`21:30`, `sun`). Until then nothing is planned or rung, and what was planned in that time is placed again after it. You can still start a session yourself. `Back now`, under Today, frees what is left. From a terminal: `programme later 1h`, `programme later tomorrow`, `programme back`.

**The days.** Weekday evenings, two blocks on Sunday, Saturday as a bonus that is never counted, and Friday evening free. A school day whose courses end by the midday break gives its afternoon a 90-minute block (`programme rhythm half_day_minutes 0` turns it off). Holidays, study weeks and pauses are periods, in More › Rhythm.

**First run.** Under Today, five steps: language and course folder (one folder per subject), the timetable's iCal link and your groups (ticked, never typed), which courses go with which folder, your rhythm, ready. Every setting is in **More** afterwards, and `programme help` lists the same from a terminal.

**Quick add** (`Super + Shift + D`, or `programme add` in a terminal) reads one line and shows what it understood before keeping it:

| Line | Adds |
|---|---|
| `examen L&MC 18/12` | an exam |
| `cc OC 12/11 14h` | a test |
| `rendu ARGOS 12/11 30h` | a hand-in with its hours of work |
| `indispo sam 14h-18h` | a busy slot |
| `tâche relire TD3 A&C 45m` | a task |
| `candidature Entreprise F` | a company in the running campaign |
| `libre 1h` | a session now, in an hour you did not expect |

**Calendars.** Sessions go to khal's `etude` calendar and your courses to `cours`, so both show in the calendar drawer; your own events (`Super + A`) count as busy.

Settings live in `~/.config/programme/settings.json` and your history in `~/.local/share/programme/`; both are written by the app. The service runs as `systemd --user` (`programme.service`), built from [`programme-src`](../../config/hyprland/programme-src/) on edge and installed as a package on stable.

**Coming from Boussole's planner.** Installing the `programme` unit (`cc-pkg-mng install programme`) moves your settings and history over and removes the old service and its `boussole` command. What Programme no longer reads is kept in `~/.local/share/programme/from-boussole/`, with a copy of each file as it was.
