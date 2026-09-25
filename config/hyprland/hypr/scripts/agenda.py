#!/usr/bin/env python3
"""Agenda: add/delete khal events from fuzzel, and export them for the bar.

    agenda.py           interactive (Super+A): one fuzzel line to type the
                        event in French, then a checklist of reminders.
                        Picking an existing event from the list offers to
                        delete it instead.
    agenda.py export    JSON on stdout for quickshell's CalendarState:
                        [{uid, title, allDay, start, end, alarms: [ms]}]

Storage is khal's own vdir (config/hyprland/khal/config), so an event is a
plain .ics with its VALARMs -- this script never keeps a file of its own.
Reminders are NOT fired from here: the bar compares `alarms` against the
wall clock on its existing minute tick (see services/CalendarState.qml),
so nothing runs in the background.

Input grammar (case-insensitive, any order, the rest is the title):
    date   auj | demain | après-demain | lun..dim | 3/10 | 3/10/27 |
           3 oct | le 3 | dans 2h | dans 30min | dans 3j
    time   14h | 14h30 | 14:30 | 14h-15h30 (default duration 1h;
           no time at all = all-day event)
    alarm  !1s !3j !1j !1h !15m !0   (skips the reminder checklist)
"""

import datetime as dt
import json
import os
import re
import subprocess
import sys

KHAL_CAL = "personal"
KHAL_CONFIG = os.path.expanduser("~/.config/khal/config")
# khal prints `start`/`end` with the config's own formats -- these two are
# the repo's (config/hyprland/khal/config: dateformat / datetimeformat).
KHAL_DATE = "%d/%m/%Y"
KHAL_DATETIME = "%d/%m/%Y %H:%M"
EXPORT_SPAN = "60d"

APP = "Agenda"
ICON = "x-office-calendar"

WEEKDAYS = {
    "lun": 0, "lundi": 0, "mar": 1, "mardi": 1, "mer": 2, "mercredi": 2,
    "jeu": 3, "jeudi": 3, "ven": 4, "vendredi": 4, "sam": 5, "samedi": 5,
    "dim": 6, "dimanche": 6,
}
MONTHS = {
    "jan": 1, "janv": 1, "janvier": 1, "fev": 2, "fevr": 2, "fevrier": 2,
    "mars": 3, "avr": 4, "avril": 4, "mai": 5, "juin": 6, "juil": 7,
    "juillet": 7, "aout": 8, "sep": 9, "sept": 9, "septembre": 9,
    "oct": 10, "octobre": 10, "nov": 11, "novembre": 11, "dec": 12,
    "decembre": 12,
}
JOURS = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]


class ParseError(Exception):
    pass


def fold(s):
    """Lowercase and strip French accents, for matching keywords only."""
    table = str.maketrans("àâäéèêëîïôöùûüç", "aaaeeeeiioouuuc")
    return s.lower().translate(table).rstrip(".,")


# ---- reminders -----------------------------------------------------------

def parse_offset(s):
    """'1s' / '3j' / '2h' / '15m' / '0' -> minutes before start."""
    m = re.fullmatch(r"(\d+)\s*(s|sem|semaines?|j|jours?|d|h|m|min)?", fold(s))
    if not m:
        return None
    n, unit = int(m.group(1)), (m.group(2) or "m")
    if unit.startswith("s"):
        return n * 7 * 24 * 60
    if unit[0] in "jd":
        return n * 24 * 60
    if unit == "h":
        return n * 60
    return n


def offset_label(minutes, all_day):
    if all_day:
        # All-day reminders ring at 09:00: `minutes` counts back from
        # 09:00 of the day itself, so 0 is "le jour même à 9h".
        days = minutes // (24 * 60)
        if days == 0:
            return "Le jour même à 9h"
        if days == 1:
            return "La veille à 9h"
        if days % 7 == 0:
            w = days // 7
            return f"{w} semaine{'s' if w > 1 else ''} avant (9h)"
        return f"{days} jours avant (9h)"
    if minutes == 0:
        return "À l'heure"
    if minutes % (7 * 24 * 60) == 0:
        w = minutes // (7 * 24 * 60)
        return f"{w} semaine{'s' if w > 1 else ''} avant"
    if minutes % (24 * 60) == 0:
        d = minutes // (24 * 60)
        return f"{d} jour{'s' if d > 1 else ''} avant"
    if minutes % 60 == 0:
        return f"{minutes // 60} h avant"
    return f"{minutes} min avant"


def khal_delta(minutes, all_day):
    """Minutes-before-start -> khal's --alarms DELTA (positive = before).
    All-day triggers are relative to 00:00, so the 09:00 anchor is folded
    in here: 'la veille à 9h' is 15h before midnight, 'le jour même à 9h'
    is 9h after it (-9h)."""
    if all_day:
        minutes -= 9 * 60
    return f"{minutes}m"


# ---- event line ----------------------------------------------------------

def parse_line(text, now):
    tokens = text.split()
    date = None
    start_t = end_t = None
    alarms = []
    title = []

    time_re = re.compile(r"(\d{1,2})(?:[h:](\d{2})?)")
    range_re = re.compile(r"(\d{1,2})(?:[h:](\d{2})?)?-(\d{1,2})(?:[h:](\d{2})?)?")

    def hm(h, m):
        h, m = int(h), int(m or 0)
        if h > 23 or m > 59:
            raise ParseError(f"heure invalide : {h}:{m:02d}")
        return dt.time(h, m)

    i = 0
    while i < len(tokens):
        raw = tokens[i]
        t = fold(raw)
        nxt = fold(tokens[i + 1]) if i + 1 < len(tokens) else ""

        if raw.startswith("!") and parse_offset(raw[1:]) is not None:
            alarms.append(parse_offset(raw[1:]))
        elif date is None and t in ("auj", "aujourd'hui", "aujourdhui"):
            date = now.date()
        elif date is None and t == "demain":
            date = now.date() + dt.timedelta(days=1)
        elif date is None and t in ("apres-demain", "apresdemain"):
            date = now.date() + dt.timedelta(days=2)
        elif date is None and t in WEEKDAYS:
            date = now.date() + dt.timedelta(days=(WEEKDAYS[t] - now.weekday()) % 7)
            date = ("weekday", date)
        elif date is None and t == "dans" and nxt:
            # "dans 2h" / "dans 2 h" / "dans 30 min" / "dans 3j"
            span = nxt
            if i + 2 < len(tokens) and re.fullmatch(r"\d+", nxt):
                span = nxt + fold(tokens[i + 2])
                i += 1
            mins = parse_offset(span)
            if mins is None:
                title.append(raw)
            else:
                at = (now + dt.timedelta(minutes=mins)).replace(second=0, microsecond=0)
                date = at.date()
                if not re.search(r"(j|jours?|d|s|sem|semaines?)$", span):
                    start_t = at.time()
                i += 1
        elif date is None and (m := re.fullmatch(r"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?", t)):
            d, mo, y = int(m.group(1)), int(m.group(2)), m.group(3)
            date = ("dm", d, mo, int(y) + (2000 if len(y) == 2 else 0) if y else None)
        elif date is None and re.fullmatch(r"\d{1,2}", t) and nxt in MONTHS:
            y = None
            if i + 2 < len(tokens) and re.fullmatch(r"\d{4}", tokens[i + 2]):
                y = int(tokens[i + 2])
                i += 1
            date = ("dm", int(t), MONTHS[nxt], y)
            i += 1
        elif date is None and t == "le" and re.fullmatch(r"\d{1,2}", nxt):
            date = ("d", int(nxt))
            i += 1
        elif start_t is None and (m := range_re.fullmatch(t)) and ("h" in t or ":" in t):
            start_t = hm(m.group(1), m.group(2))
            end_t = hm(m.group(3), m.group(4))
        elif start_t is None and (m := time_re.fullmatch(t)):
            start_t = hm(m.group(1), m.group(2))
        elif start_t is None and t == "midi":
            start_t = dt.time(12, 0)
        else:
            title.append(raw)
        i += 1

    title = " ".join(title).strip()
    if not title:
        raise ParseError("il manque le titre")

    today = now.date()
    try:
        if date is None:
            if start_t is None:
                raise ParseError("il manque la date ou l'heure")
            date = today
            if dt.datetime.combine(date, start_t) <= now:
                date += dt.timedelta(days=1)
        elif isinstance(date, tuple) and date[0] == "weekday":
            date = date[1]
            # Same weekday as today but already past: next week's.
            if date == today and start_t is not None \
                    and dt.datetime.combine(date, start_t) <= now:
                date += dt.timedelta(days=7)
        elif isinstance(date, tuple) and date[0] == "dm":
            _, d, mo, y = date
            date = dt.date(y or today.year, mo, d)
            if y is None and date < today:
                date = date.replace(year=today.year + 1)
        elif isinstance(date, tuple) and date[0] == "d":
            d = date[1]
            y, mo = today.year, today.month
            if d < today.day:
                mo += 1
                if mo > 12:
                    y, mo = y + 1, 1
            date = dt.date(y, mo, d)
    except ValueError:
        raise ParseError("date invalide")

    all_day = start_t is None
    if all_day:
        if date < today:
            raise ParseError("cette date est passée")
        return {"title": title, "date": date, "allDay": True,
                "start": None, "end": None, "alarms": alarms}

    start = dt.datetime.combine(date, start_t)
    if start <= now:
        raise ParseError("cette heure est passée")
    end = dt.datetime.combine(date, end_t) if end_t else start + dt.timedelta(hours=1)
    if end <= start:
        end += dt.timedelta(days=1)
    return {"title": title, "date": date, "allDay": False,
            "start": start, "end": end, "alarms": alarms}


def describe(ev):
    d = ev["date"]
    head = f"{JOURS[d.weekday()]} {d:%d/%m}"
    if ev["allDay"]:
        return f"{ev['title']} · {head} (journée)"
    return f"{ev['title']} · {head} {ev['start']:%H:%M}–{ev['end']:%H:%M}"


# ---- khal ----------------------------------------------------------------

def khal(*args):
    return subprocess.run(["khal", *args], capture_output=True, text=True)


def khal_new(ev, alarms):
    args = ["new", "-a", KHAL_CAL]
    if alarms:
        args += ["-m", ",".join(khal_delta(a, ev["allDay"]) for a in sorted(alarms, reverse=True))]
    if ev["allDay"]:
        args += [ev["date"].strftime(KHAL_DATE)]
    else:
        args += [ev["start"].strftime(KHAL_DATETIME), ev["end"].strftime("%H:%M")
                 if ev["end"].date() == ev["start"].date()
                 else ev["end"].strftime(KHAL_DATETIME)]
    args.append(ev["title"])
    return khal(*args)


def calendar_dirs():
    dirs = []
    try:
        with open(KHAL_CONFIG) as f:
            for line in f:
                m = re.match(r"\s*path\s*=\s*(.+?)\s*$", line)
                if m and "khal.db" not in m.group(1):
                    dirs.append(os.path.expanduser(m.group(1)))
    except OSError:
        pass
    return dirs


def ics_files():
    for d in calendar_dirs():
        try:
            for name in os.listdir(d):
                if name.endswith(".ics"):
                    yield os.path.join(d, name)
        except OSError:
            continue


def triggers_by_uid():
    """uid -> [timedelta relative to start]. Absolute (DATE-TIME) triggers
    and END-related ones are rare enough in practice to be skipped."""
    from icalendar import Calendar

    out = {}
    for path in ics_files():
        try:
            with open(path, "rb") as f:
                cal = Calendar.from_ical(f.read())
        except Exception:
            continue
        for ev in cal.walk("VEVENT"):
            uid = str(ev.get("UID", ""))
            trig = []
            for alarm in ev.walk("VALARM"):
                t = alarm.get("TRIGGER")
                if t is None or not isinstance(t.dt, dt.timedelta):
                    continue
                if str(t.params.get("RELATED", "START")).upper() != "START":
                    continue
                trig.append(t.dt)
            if trig:
                out[uid] = trig
    return out


def upcoming():
    """khal's own expansion (recurrences, timezones), one dict per
    instance, from today on."""
    res = khal("list", "--once", "--json", "uid", "--json", "title",
               "--json", "start", "--json", "end", "--json", "all-day",
               "today", EXPORT_SPAN)
    events, seen = [], set()
    for line in res.stdout.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        for e in json.loads(line):
            all_day = e["all-day"] == "True"
            fmt = KHAL_DATE if all_day else KHAL_DATETIME
            try:
                start = dt.datetime.strptime(e["start"], fmt)
                end = dt.datetime.strptime(e["end"], fmt)
            except ValueError:
                continue
            if all_day:
                end += dt.timedelta(days=1)   # khal prints the last day, inclusive
            key = (e["uid"], start)
            if key in seen:
                continue
            seen.add(key)
            events.append({"uid": e["uid"], "title": e["title"],
                           "allDay": all_day, "start": start, "end": end})
    events.sort(key=lambda e: e["start"])
    return events


def export():
    trig = triggers_by_uid()
    ms = lambda d: int(d.timestamp() * 1000)
    out = []
    for e in upcoming():
        out.append({
            "uid": e["uid"], "title": e["title"], "allDay": e["allDay"],
            "start": ms(e["start"]), "end": ms(e["end"]),
            "alarms": sorted(ms(e["start"] + t) for t in trig.get(e["uid"], [])),
        })
    json.dump(out, sys.stdout)


def delete(uid):
    for path in ics_files():
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                if f"UID:{uid}" in f.read():
                    os.remove(path)
                    return True
        except OSError:
            continue
    return False


# ---- ui ------------------------------------------------------------------

def fuzzel(lines, *args):
    """Returns (exit code, stdout stripped of the trailing newline)."""
    res = subprocess.run(["fuzzel", "--dmenu", *args], input="\n".join(lines),
                         capture_output=True, text=True)
    return res.returncode, res.stdout.rstrip("\n")


def notify(summary, body="", critical=False):
    cmd = ["notify-send", "-a", APP, "-i", ICON, summary]
    if body:
        cmd.append(body)
    if critical:
        cmd[1:1] = ["-u", "critical"]
    subprocess.run(cmd)


def reload_bar():
    subprocess.run(["qs", "ipc", "-c", "bar", "call", "bar", "reloadEvents"],
                   capture_output=True)


def pick_alarms(ev):
    if ev["allDay"]:
        choices = [7 * 1440, 3 * 1440, 1440, 0]
        checked = {1440, 0}
    else:
        choices = [7 * 1440, 3 * 1440, 1440, 60, 15, 0]
        checked = {1440, 60}
    sel = 0
    while True:
        lines = ["✓ Valider"] + [
            ("☑ " if c in checked else "☐ ") + offset_label(c, ev["allDay"])
            for c in choices
        ]
        code, out = fuzzel(
            lines, "--select-index", str(sel), "--minimal-lines",
            "--match-mode", "exact", "--prompt", "Rappels › ",
            "--placeholder", "Entrée coche · ou tape 2h, 30m, 2j…",
            "--mesg", describe(ev))
        if code != 0:
            return None
        # Matched by text rather than --index: a typed custom offset
        # matches no line, and --index has nothing sensible to print then.
        if out in lines:
            idx = lines.index(out)
            if idx == 0:
                return checked
            checked ^= {choices[idx - 1]}
            sel = idx
            continue
        # Typed text that matched nothing: a custom offset.
        c = parse_offset(out)
        if c is not None:
            if c not in choices:
                choices.append(c)
                choices.sort(reverse=True)
            checked.add(c)
            sel = choices.index(c) + 1


def confirm_delete(e):
    when = f"{JOURS[e['start'].weekday()]} {e['start']:%d/%m}"
    if not e["allDay"]:
        when += f" {e['start']:%H:%M}"
    code, out = fuzzel(["Non", "Supprimer"], "--minimal-lines", "--only-match",
                       "--prompt", "Supprimer ? ", "--mesg", f"{e['title']} · {when}")
    return code == 0 and out == "Supprimer"


def interactive():
    events = upcoming()
    now = dt.datetime.now()
    # Column 1 is the uid, hidden by --with-nth; a typed line has no tab,
    # which is how a new event is told apart from a picked one.
    lines = []
    for e in events:
        if e["end"] <= now:
            continue
        when = f"{JOURS[e['start'].weekday()]} {e['start']:%d/%m}"
        when += "       " if e["allDay"] else f" {e['start']:%H:%M}"
        lines.append(f"{e['uid']}\t{when}   {e['title']}")

    # `exact`, not the default fzf matching: a whole typed line such as
    # "demain 14h30 Dentiste" must not fuzzily match an existing entry and
    # turn an add into a delete.
    code, out = fuzzel(lines, "--with-nth", "2", "--match-mode", "exact",
                       "--prompt", "Agenda › ",
                       "--placeholder", "demain 14h30 Dentiste · ven 9h-10h Réunion !1j")
    if code != 0 or not out.strip():
        return

    if "\t" in out:
        uid = out.split("\t", 1)[0]
        e = next((e for e in events if e["uid"] == uid), None)
        if e and confirm_delete(e):
            if delete(uid):
                notify("Événement supprimé", e["title"])
                reload_bar()
            else:
                notify("Suppression impossible", e["title"], critical=True)
        return

    try:
        ev = parse_line(out, dt.datetime.now())
    except ParseError as err:
        notify("Événement non ajouté", f"{err} — « {out} »", critical=True)
        return

    alarms = set(ev["alarms"]) if ev["alarms"] else pick_alarms(ev)
    if alarms is None:
        return

    res = khal_new(ev, alarms)
    if res.returncode != 0:
        notify("khal a refusé l'événement", res.stderr.strip()[:200], critical=True)
        return
    labels = ", ".join(offset_label(a, ev["allDay"]) for a in sorted(alarms, reverse=True))
    notify("Événement ajouté", describe(ev) + (f"\nRappels : {labels}" if labels else ""))
    reload_bar()


if __name__ == "__main__":
    if sys.argv[1:] == ["export"]:
        export()
    else:
        interactive()
