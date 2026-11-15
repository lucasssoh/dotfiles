# Programme

A study agenda in the bar. It reads your timetable, plans study sessions around your courses and your evenings, rings them, and opens each subject's course when its session starts.

Programme is optional: `init` asks, and `cc-pkg-mng install programme` adds it later.

## In the bar

Right of the clock:

| You see | It means |
|---|---|
| `A&C · 20:30` | The next session and its subject |
| The same, outlined, with a countdown | It starts within 15 minutes |
| `now` | It waits to be started |
| A ring that empties | A session is under way: 25 minutes of work, then a 5-minute break |
| `elsewhere` | A session is under way, and the course isn't in front |

Click it, or press `Super + D`, for the drawer.

## Alerts

A session's start opens in the bar's island, with a chime: `Tonight · A&C`, `20:30 – 22:00 · 1 h 30`, and three buttons, `Start`, `In 30 min` and `Tomorrow`.

The alert stays until you answer. If nothing started, it comes back 15 minutes later. It waits for the end of a fullscreen game or of zen mode.

At the session's end, `A&C · done?` asks for `Done`.

You also get a notification:

- the evening before, with tomorrow's sessions;
- when a course of today or tomorrow is cancelled or moved.

## The drawer

A panel along the left edge of the screen.

| Tab | What it holds |
|---|---|
| **Today** | The session under way with `Launch` and `Done`, the next one with `Start` and `Later`, `Start a session`, the day's courses still ahead with their room, and what comes after |
| **Week** | The seven days ahead: courses with their room, and sessions |
| **More** | Exams and hand-ins, rhythm, subjects, calendars, settings, and the first run again |

## How sessions are planned

- A slot first takes the tutorials to prepare and the tasks you typed. The rest goes to one subject.
- Subjects take turns. Each gets time by the level you gave it and by how close its exam is.
- Projects and hand-ins are spread up to 3 days before they are due.
- A subject gets no session after its last exam and its last course.

## Start a session

`Start`, in the alert or under Today, runs the subject's command. `Launch` runs it again. The browser window that opens Boussole comes to the front.

The session's time counts while the course's window is in front. For a subject with no command, the whole session counts. Notifications keep quiet while the course is in front: find them in the [notification centre](notifications.md).

`Done` ends the session.

To study outside the plan, use `Start a session` under Today: pick a subject, then 30 minutes to an hour and a half. From a terminal:

```bash
programme free 45 A&C
```

## Subjects

In More › Subjects, each subject has a level and a command.

| Level | Gets |
|---|---|
| *Behind* | More time |
| *Shaky*, *Fine* | Its share |
| *Tutorials only* | No session of its own: its tutorials to prepare, its projects and its exams |

A subject's sessions open nothing, [Boussole](https://github.com/lucasssoh/Boussole) on the subject's folder, or a command you type. `{folder}` stands for the subject's folder.

```bash
programme subject level A&C behind
programme subject launch A&C on                                # Boussole
programme subject launch L&MC liseuse {folder}/00_Index.md     # a command of yours
programme subject launch L&MC off
```

## Later

`Later` asks until when: in 30 minutes, in an hour, tomorrow, the day after, or a time or a day you type (`21:30`, `sun`). Until then nothing is planned or rung, and what was planned moves after it. `Back now`, under Today, ends the pause.

```bash
programme later 1h
programme later tomorrow
programme back
```

## The days

| Day | Sessions |
|---|---|
| Monday to Thursday | The evening |
| Friday | None |
| Saturday | Extra: its time isn't counted |
| Sunday | Two blocks |

A school day whose courses end by the midday break gets a 90-minute block in the afternoon. `programme rhythm half_day_minutes 0` turns it off.

Holidays, study weeks and pauses are set in More › Rhythm.

## First run

Under Today, five steps: your language and course folder (one folder per subject), the timetable's iCal link and your groups, which courses go with which folder, your rhythm, ready.

Every setting is in **More** afterwards. `programme help` lists the same from a terminal.

## Quick add

`Super + Shift + D`, or `programme add` in a terminal. Type one line; Programme shows what it understood before keeping it.

| Line | Adds |
|---|---|
| `examen L&MC 18/12` | an exam |
| `cc OC 12/11 14h` | a test |
| `rendu ARGOS 12/11 30h` | a hand-in with its hours of work |
| `indispo sam 14h-18h` | a busy slot |
| `tâche relire TD3 A&C 45m` | a task |
| `candidature Entreprise F` | a company in the running campaign |
| `libre 1h` | a session now |

## Calendars

Sessions and courses show in the [calendar drawer](clock-agenda.md). Your own events (`Super + A`) count as busy.

## Coming from Boussole's planner

`cc-pkg-mng install programme` moves your settings and history over, and removes the old service and its `boussole` command. Your old files are kept in `~/.local/share/programme/from-boussole/`.
