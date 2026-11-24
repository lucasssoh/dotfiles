# Changelog

Versions follow `MAJOR.MINOR.PATCH`, and each release is a git tag (`v1.0.0`). Major releases also get a code name, minor ones their date; patch releases have neither. On the stable channel, `cc-pkg-mng upgrade` moves you from one release to the next.

## Unreleased

### Added
- **Bar, centre island:** five shapes to choose from in `bar-island.json`: the floating island, a rounded notch, a dome, a pill and a flush square. The notch hangs from a thin strip along the screen edge, joined by concave fillets. The insets and corner radii can also be set by hand.
- **Bar, centre island:** `bar-island.json` groups its keys under `shape`, `fill` and `text`. The old flat keys still work.
- **WezTerm:** `~/.config/wezterm/local.lua` overrides any setting: background, font, size…, in both modes or in light or dark only.

### Changed
- **WezTerm:** an opaque terminal by default, dark `#101010` or cream. Transparency and blur are a setting in `local.lua`.

### Fixed
- **Power:** a profile you pick by hand stays until the cable is plugged or unplugged. While charging, it went back to Balanced within a minute.
- **Antenne:** Esc on a channel that doesn't answer, and Backspace to go back to the previous channel, no longer close the app.
- **Antenne:** coming back to its workspace no longer freezes the app, sometimes for good.
- **Antenne:** when you come back to its workspace, the sound goes on without a cut and the picture is back right away.
- **Bar:** with the bar at the top, the network, battery and volume drawers no longer sit lower than with the bar at the bottom.

## 2.7.2

### Fixed
- **Antenne:** with the guide open, a channel that doesn't answer says so over its picture, at the top right, instead of in the middle of the guide.
- **Bar:** the drawers' glass keeps the light mode's tone after Hyprland reloads its configuration.

### Changed
- **Antenne:** opens with a fade instead of growing from the middle of the screen, and the picture rises out of the black.

## 2.7.1

### Fixed
- **Other desktops:** logging into another desktop no longer starts coucou-shell's background services, the warnings that they failed, or a second Bluetooth icon.

### Changed
- **Licence:** coucou-shell is now free software, under the GPL-3.0 or any later version. The coucou wallpapers and bird are under CC BY-SA 4.0.
- **config-extras:** fastfetch shows the coucou bird in place of Rapunzel.

## 2.7.0 (November 23 2026)

### Added
- **Antenne:** a new app, the TV. `Super + G` opens free channels from the countries you pick, with a programme guide, your own playlists and streams, and shows from YouTube, the Internet Archive or your own files. It works with the keyboard, the mouse or a controller. Install it with `cc-pkg-mng install antenne`.
- **Manette:** an app in front, such as Antenne, can take the controller. The Guide button still opens the menu.
- **WezTerm:** `Alt + Shift + B` also goes to the previous tab, next to `Alt + Shift + N` for the next one.
- **WezTerm:** `AltGr` works in place of `Alt + Shift` for panes and tabs: `AltGr + N` goes to the next tab, `AltGr + H` to the pane on the left.
- **config-extras:** lazygit no longer fetches on its own, so no passphrase prompt comes up while you work: `f` fetches.

### Changed
- **config-extras:** fastfetch shows Rapunzel as a grey photo instead of coloured ASCII, next to the summary in the terminal's own colours, without frames or colour dots. The summary starts with Coucou Shell and ends with the cc-pkg-mng version.

### Fixed
- **Prisme:** thumbnails show with the first frame, even on a busy machine.
- **WezTerm:** at a fractional scale such as 125 %, opening a second terminal no longer closes every WezTerm window.
- **Bar, glass popups:** at a fractional scale such as 125 %, the blur behind the volume and brightness dial, the controller pill and the other glass panes no longer shows past their edges as dark stairs.
- **Bar, controller pill:** no more stray line beside the pill's rounded ends.

## 2.6.1

### Fixed
- **Displays:** saving the scale, where the screens sit or which ones are on no longer waits for a reload: it applies at once.
- **Displays:** saving a Hyprland setting no longer blanks the screens for a moment, and an HDR screen stays in HDR.
- **Displays:** plugging in or unplugging the external screen no longer warns that the screens overlap.
- **Shell:** the prompt no longer hides which virtual environment or language version is active: it shows it before the path, in green for an isolated environment and blue for a version manager.
- **cc-pkg-mng:** a failed upgrade no longer leaves the configs on the new release and the apps on the old one. Packages are checked and downloaded before anything moves: if they fail, you stay on the release you had. A unit that fails afterwards is named, and the next `upgrade` finishes it.
- **cc-pkg-mng:** a package conflict is named package by package, with the way out, instead of a bare dnf failure. On a terminal, cc-pkg-mng offers to let dnf replace the packages in the way; `--allow-erasing` does the same without asking.
- **cc-pkg-mng:** an upgrade no longer runs the previous cc-pkg-mng on the new release: it updates cc-pkg-mng first, then carries on with the new one.
- **cc-pkg-mng:** after an upgrade, the apps that changed no longer keep their old version until the next login: their services restart, and the bar restarts on a new Quickshell. A new Hyprland is announced for the next login.
- **cc-pkg-mng:** `status` and `--version` show packages left behind the release, and an upgrade that stopped half-way.
- **cc-pkg-mng:** errors no longer end on a raw command failure: each says what happened and the command that gets out of it.
- **cc-pkg-mng:** two runs at once no longer step on each other: the second one stops and says which one is running.

## 2.6.0 (November 16 2026)

### Added
- **Install, bar:** the central island gets default look settings when you install the bar, unless you already have your own.
- **Bar, centre island:** you can set its colour, opacity and blur, and choose between text that adapts to the wallpaper and a colour of your own, in a settings file described in the docs.
- **Documentation:** every tool has its own guide: each part of the bar, Roue, Prisme, Manette, Sésame, Liseuse, the launcher, Screenshot, the session and the applications. New pages cover displays, wallpapers, the lock screen, and how to write an agenda event or a wheel of your own.
- **Documentation:** *Settings* shows where each setting lives, and how to keep a change through an upgrade.
- **Website:** a new look in the shell's neutral greys, light and dark, with coucou's Aube wallpapers. The home page opens on the boot splash, then shows the film, the three install commands and every tool; the guides follow the same shapes, on phones too.
- **Website:** a new film on the home page, about a minute through Roue, the drawers, notifications, the key sheet, the controller menu, tiling and Prisme, with its music behind a Sound on button.
- **README:** rewritten around the tools, with still images instead of the video, the tested machines, and the licences in a table: what you may do, what you may not, and what belongs to others.

### Changed
- **Bar:** each block prefers the ink with better contrast against its wallpaper; any dark veil fades out two-thirds down the bar. Text and veil follow wallpaper changes over the same fade.
- **Bar, centre island:** long window titles leave more room for workspaces and music. No more dark slab: a light graphite tint, without a border. Window names, titles, workspace marks and music turn light or dark to suit what is behind them (even across mixed backgrounds). Empty workspaces are hollow dots. Veille, the keybinds sheet and Programme reminders open in the same glass as other drawers, light or dark with the system, growing from the island.
- **Bar, battery:** the filled battery gauge replaces the outlined one.
- **Bar, Programme:** on a switch to dark mode, light text replaces the pale veil when it gives better contrast.

### Fixed
- **Balise:** text stays sharp at fractional display scales.
- **Bar:** drawers no longer wait for an exit cascade before closing. Rounded corners on the central island and glass drawers no longer show a light jagged edge while opening or closing. Drawers start and behave correctly at the top or bottom edge.
- **Bar, OSD:** volume, microphone and brightness dials sit centred at the bottom above drawers, with a round blur that follows their edge and no straight side highlights.
- **Bar, drawers:** the light inner edge along the top of glass panes fades out down the sides instead of stopping on a hard cut.
- **Apps, OPL IDE:** CPLEX Studio's launcher appears when you install the extra configs.
- **Wallpapers:** a light and dark wallpaper keeps following light or dark mode after its background helper restarts.
- **Firefox:** closing a tab no longer leaves a gap in the tab strip; searching from the new tab page uses the middle field with suggestions instead of jumping to the address bar.

## 2.5.0 (November 15 2026)

### Fixed
- **Roue:** the top action of a wheel runs with a click or `Enter` right after the wheel opens, without having to aim elsewhere first. Nothing shows as selected until you aim.
- **Bar, battery:** on a light bar, the amber (low while saving power) and blue (charging up to 60 %) are dark enough to read.
- **Neovim:** :bd moves to the next open file, or to the file tree when it was the last one.
- **Bar:** at the bottom edge, it no longer shows too high for an instant when it starts or changes edge.
- **Bar:** at the top edge, the clock, launcher and tools drawers open under the bar again instead of over it.
- **Notifications:** a pop-up that its app updates (a copy's progress, a new status) stays its full time again, instead of leaving on the first one's schedule.
- **Prisme:** the cards of light and dark wallpapers no longer show a light rim at their corners.
- **Prisme:** a light and dark wallpaper opens on the version matching your desktop, without showing the other one for an instant.

### Added
- **Wallpapers:** Nuit, the folds of coucou's Plis under a cold blue light, light and dark.

### Changed
- **Roue:** each action is a round glass button on the blurred desktop, the one you aim at inverted; the name shows in the middle. The wheel follows light or dark mode, the side panel with the key reminder is gone, and the applied profile or display is marked by a dot.
- **Bar, battery:** an outlined battery with the charge inside it, instead of a filled pill; when the charge stops at 60 %, a dotted line marks where.
- **Install:** Fedora's crash reporter (abrt) is turned off, which frees about 90 MB. Crashes are still kept: `coredumpctl list` shows them.
- **Files:** Nemo has a lighter layout in the shell's colours. The current folder shows in full ink with its parent folders quietly beside it, files sit straight on the window without frames, a hairline parts them from the sidebar, and the status shows in a small floating label. A selected name is inverted like the active workspace; a selected row or place is shaded. In light mode it is cream instead of white and blue.
- **Files:** Nemo's dialogs and the file chooser of other apps take the same colours: separate rounded buttons, Delete in a calm red.
- **Files:** the menu bar and status bar are hidden; press Alt to show the menu bar. Nemo is no longer slightly see-through.
- **Files:** the link, lock and read-only badges on icons are sharp, white with a dark mark, instead of blurred grey squares.
- **Files:** the active view is outlined instead of a filled square, the same whether the window has focus or not.
- **Firefox:** along the top, tabs are rounded rectangles of equal width with their title centred. The address reads centred until you click in it, in an outlined field. The page sits as a rounded card in the window.
- **Firefox, new tab:** the search field and, right under it, one glass pane with your pinned shortcuts as icons and your frequent sites as a list. The ground is the new Nuit wallpaper, light or dark, instead of the grid.
- **Neovim:** colour names light up only in stylesheets, where they mean a colour; hex and rgb()/hsl() codes still light up everywhere.
- **Bar:** an app chip opens its drawer on a click, like the other drawers, and no longer on hover; Focus is the drawer's first row.
- **Bar:** drawers start right at the bar's edge, without the 4px gap.
- **Bar:** it slides in and out from its own edge, the same way at the top and at the bottom, while windows make room.
- **Lock screen:** the time stands alone in light ink on black, without the white card; the password field is an outlined rounded rectangle.
- **Notifications:** pop-ups come in with a short slide, one at a time when several arrive together, and the stack no longer jumps when one comes or goes.
- **Notifications:** pop-ups stay while the pointer is on them. Past three, the others wait underneath instead of being dropped.
- **Notifications:** closed with ×, a pop-up slides off the screen; when its time is up, it fades out.
- **Notifications:** pop-ups are rounder, with the app's icon or picture on the left and the app's name above the title. Actions are a row of buttons along the bottom, and × shows when the pointer is on the pop-up.
- **Notifications:** a critical pop-up has an amber edge and title. The pop-ups waiting under the stack show as card edges with their count.
- **Notifications:** messages in a row from the same app and sender share one pop-up, with their count next to the app's name.
- **Notifications:** a screenshot or other wide picture shows in full under the text. The pop-ups waiting under the stack show their apps' icons.
- **Notifications:** a pop-up lightens slightly under the pointer, its text follows it in as it arrives, a pressed action button stays dark as the pop-up leaves, and a critical one flares once.
- **Notification centre:** it matches the pop-ups. × shows under the pointer, in place of the time; a line lightens under the pointer; actions are a row of buttons; a screenshot shows in full; a critical notification is amber.
- **Notification centre:** messages in a row from the same sender show the sender's name once, each message still on its own line. A notification arriving while the centre is open slides in.
- **Notifications:** pop-ups, the centre and the pop-ups waiting under the stack show the app's icon from its desktop entry, even beside a picture.
- **Firefox:** after a crash or a forced quit, it opens as usual instead of on the session restore page. Your last session stays in History.
- **Demo mode:** a made-up track plays in the bar and the notification centre instead of yours.
- **Notification centre:** a lighter layout. A large, thin clock with the day spelled out beside it; Do not disturb is a switch on its own row; the player and the notifications sit on the drawer itself, parted by hairlines. The player shows the track's cover when there is one, and the elapsed and total time as numbers.

## 2.4.0 (November 11 2026)

### Added
- **Terminal:** WezTerm turns light or dark with the desktop. In light mode it is more opaque, so the text stays readable on any wallpaper.
- **Neovim:** the editor follows the desktop's light or dark mode, even while it is open.
- **Bar:** on battery, the power draw in watts appears after memory.
- **Bar:** choose its top or bottom edge; drawers and wallpaper tint follow it.

### Changed
- **Neovim:** the light theme uses the shell's colours, and its status bar is light too.
- **Neovim:** the active tab stands out as a pill, transparent background included.
- **Neovim:** in the file tree, the files on screen are in italic and the one you are editing in the accent colour.
- **Screen corners:** the rounded corners stay above everything, fullscreen windows included.
- **Programme and notifications:** the side panels are rounded like the screen's corners, with a single edge that fades towards the bottom, and their glass is denser lower down.
- **Notifications:** a finer clock, a round Do not disturb button lined up with Programme's tabs, Clear all only when there is something to clear, and a pale bell when the list is empty.
- **Programme:** in Today, the current session's card is outlined, the course under way has a dot, and Coming up is grouped by day.
- **Bar, centre island:** the window title, workspaces and media now float on their own pane on the bar, and what opens under them hangs as a separate pane in the same glass.
- **Key bindings:** holding Super opens a compact keyboard with only the keys that do something, where they sit on yours; Shift shows the second layer.
- **Windows:** the outer gap above a window is now the same as on the sides.
- **Veille:** the card opens at the keybinds sheet's width, so the bar no longer widens further for it.
- **Bar:** changing edges restarts QuickShell instead of moving the bar across the screen. A brief ghost at the old edge remains a known issue.

### Fixed
- **Programme and notifications:** the side panels slide in smoothly, without a jolt as they start.
- **Neovim:** with a transparent background, the status bar no longer shows solid triangles between its sections.
- **Notifications:** during a Programme session, the bell opens the notification centre again on a workspace without Boussole. It stays closed with Boussole in front.
- **Updates:** `cc-pkg-mng upgrade` brings the screenshot editor's new builds too. It used to keep the one first installed.
- **Notifications:** with Veille's clock set or in demo mode, the notification centre shows arrival times by the shell's clock, like the bar.

## 2.3.0 (November 8 2026)

### Fixed
- **Neovim:** commenting a line works again in languages without a syntax parser, Rust included.
- **Neovim:** Tab moves to the next field of an inserted snippet instead of staying stuck in the first one.
- **Bar:** after using an external screen, the central island shows its workspaces again.
- **Screens:** unplugging the external screen while it was the only one on turns the laptop screen back on, instead of leaving it black.
- **Controller:** in light mode, the controller icon and the cover labels can be read again, and the first menu after the shell starts shows its launchers.
- **Files:** on Fedora 45, Open in Terminal opens your terminal again.
- **Prisme:** on Fedora 45, the desktop behind it is blurred again.
- **Wallpapers:** a slideshow stopped at login no longer shows as a failed service.

### Added
- **Neovim, Rust:** errors, completion and syntax colours in Rust files. Type errors show as you type, borrow-checker errors and lints when you save.
- **Installation:** the developer setup also installs Rust's linter, formatter and language server, at the same version as the compiler.
- **Bar:** a demo mode for screenshots, which shows made-up figures instead of your time, battery, system figures, next event and Wi-Fi name.
- **Screenshots:** copying, saving or copying the path shows a short confirmation over the image, fullscreen included. Copying no longer adds a notification; saving still does, with its thumbnail.

### Changed
- **Neovim, C/C++:** finer syntax colours.
- **Controller:** the menu grows from its centre as it opens, instead of appearing all at once.
- **Glass panels:** the blur behind Prisme and the panels fades in and out with them instead of appearing all at once.
- **Terminal:** WezTerm's tab bar is as see-through as the terminal, blur included, instead of an opaque band.
- **Veille:** a time you set for it moves the whole shell's clock, so the bar and Veille always agree. It no longer needs debug mode.
- **Screenshots:** the editor's toolbars match the drawers: flat glass with rounded corners, each tool on its own card.
- **Notifications:** the popups in the top-left corner are frosted glass like the drawers, with the app's name on top, and their buttons are cards.
- **Notifications:** in the notification centre, each app has one card with a line per notification, its time and its own ×. Notifications from the same app no longer fold into a stack.
- **Hyprland:** the Support Hyprland window no longer opens after an update.

## 2.2.0 (November 6 2026)

### Changed
- **Screenshots:** the screenshot editor is called Screenshot in notifications and window titles, with its own icon.
- **Bar, drawers:** a drawer zooms out of its corner, and its cards burst before it closes. Opening a drawer while another is open swaps them in place.
- **Glass panels:** the glass is lighter and the cards see-through. A button that is on keeps its card, with an outline and its icon inverted, instead of turning white. Buttons are larger, closer together and rounder.
- **Neovim:** with the transparent background, the status line and the tabs are see-through too.
- **Terminal:** WezTerm is translucent and uses Google Sans Code.

## 2.1.0 (November 3 2026)

### Added
- **Installation:** coucou-shell's packages are now published for Fedora 45 too, so you can upgrade to it.
- **Neovim, Python:** Ruff linting is installed alongside Pyright, so you can edit and check The Farmer Was Replaced scripts in Neovim.
- **Programme:** starting a session now brings Boussole's page to the front, even when your browser is on another workspace, and a session counts in whichever browser opens your links, not only Firefox.

### Changed
- **Bar:** the texts of Programme, Balise, the mixer and the library are shorter and say what to do.
- **Screenshots:** satty's toolbars are frosted glass in the shell's style, round colour swatches and MiSans, in light and dark alike. Its palette becomes red, amber, blue, black and white.
- **Screenshots:** satty now comes from the coucou-shell repository, in version 0.22.0, and no longer from a COPR.

### Fixed
- **Programme:** every session of a subject now runs that subject's command, whether it's the course, a class to prepare, a project or a reminder, instead of only starting the counter.
- **Programme:** what a session opens (your browser, Boussole) stays open when Programme restarts or updates.

## 2.0.1

### Fixed
- **Password card:** after an update of the bar's program, ssh, git and gpg asked for nothing and failed; the card shows again without restarting the bar.

## 2.0.0 « Partage »

### Changed
- **Programme:** Boussole's study planner is now Programme, in the bar and in the terminal (`programme`), and keeps only the agenda: the timetable, the week, the day, the sessions and their alerts. The courses themselves move to Boussole. Install it with `cc-pkg-mng install programme`: your settings, periods and history come along, and the old `boussole` command and service go.
- **Programme, sessions:** a session is one subject for the rest of its slot, after the tutorials to prepare and your tasks. Subjects take turns and share the time by the level you give them and how close their exam is.
- **Programme, starting a session:** `Start` opens the subject's course: Boussole on the subject, or a command you choose, set in More › Subjects. `Launch` opens it again during the session, `Done` ends it.
- **Programme, the time that counts:** during a session, only the time with Boussole in front counts. Notifications keep quiet there and show anywhere else.
- **Liseuse, library:** `Super + F` lists Liseuse's books and files, where you left off first.

### Removed
- **Programme:** the course folder's files, the library of sheets, Progress, the close form, focus mode and its study workspaces, `I have time` on a file or a project, and the question before a game during a session.
- **Neovim:** no longer tells the planner which file it edits.

## 1.11.1

### Changed
- **Windows:** windows you are not using are no longer darkened. The border around the focused window is the only sign of focus.

## 1.11.0 (October 20 2026)

### Added
- **Prisme:** `q` closes Prisme without changing anything, like `Esc`.

### Changed
- **Prisme:** the wallpaper you land on is previewed live in the middle of the screen, over your blurred desktop, with its name and size below and a strip of straight cards underneath. Prisme fades in and out instead of sliding in.
- **Prisme, light and dark wallpapers:** a small Light | Dark toggle under the preview shows which version you are looking at, and on the card the version on screen takes three quarters of it. `C` switches between the two.

## 1.10.0 (October 18 2026)

### Added
- **Screenshots:** `q` closes satty, like `Esc`.
- **Screen:** the four corners of the screen are rounded, in the same curve as the windows. A fullscreen video or game still fills the whole screen.
- **Boussole, Start a session:** projects with a folder are offered beside the modules. The whole project starts a session on it, its room holding every file of the folder, even once its planned hours are spent (`boussole free 45 --project pendu-tp`).

### Changed
- **Bar, figures:** CPU, memory, temperature and download rate now come from Pouls, a small new service, and are no longer read while the screen is off or the bar is hidden in zen mode, which saves battery.

### Fixed
- **Screenshots:** closing satty no longer flashes the wallpaper before the windows behind it come back.
- **Screenshots:** an image copied in satty stays in the clipboard after you close satty with `Esc`, so you can paste it anywhere.

## 1.9.0 (October 14 2026)

### Changed
- **Bar, popups:** the volume and brightness dial, the battery alert, the library, the password card and the controller popup and banner are now the same blurred glass as the drawers, with their curved edge.
- **Bar, light mode:** the glass of the drawers and popups is a warm grey instead of a milky white, so it no longer disappears over a white page or turns flat grey over a dark window.

## 1.8.0 (October 14 2026)

### Added
- **Boussole, Today:** the timetable at a glance: today's courses still ahead, else those of the next day that has some, with their time and room.
- **Boussole, Week:** each day shows its courses again, with their room, beside the sessions.

## 1.7.0 (October 14 2026)

### Added
- **Liseuse, library:** `Super + F` opens a library you can search: where you left off, what Boussole plans next, and every course file by subject and chapter. Type to search titles and the sections inside each file, a teacher's slides by their titles, filter by kind or subject, and open a file right at the section found. Opening a file never starts a session. Without the bar, the list comes up in fuzzel as before.
- **Boussole, I have time:** choose any course file, not only the next task. Each subject shows its next three steps with their reason, then all its files by chapter with what you have read, and Any course file… searches them all. The drawer says how your choice fits the plan, and the next step stays for the next session. The free-time card offers the same.
- **Boussole, focus mode:** Close also closes the windows left in the study workspaces, so a browser or an app forgotten there no longer holds its memory. An app with unsaved work asks first, on your own workspace. Turn it off with Tidy on Close, in More › Rhythm.
- **Boussole, projects:** a project can own a folder of your course (`boussole project dir ID FOLDER`). Its files leave the course's order: its sessions list them all under Today and in the focus panel, with what you have read, and a click opens any of them, in the study workspaces in focus mode. The files you read in a project session count as read when you close it.
- **Bar, scroll bar:** Boussole's drawer and the library have a thin scroll bar: drag it, or click its track to jump there.

### Changed
- **Boussole, sessions:** a session is one module. Its alert and its card name the module only (`Tonight · A&C`), and what to open is put forward in the room.
- **Boussole, the room:** in focus mode, the panel of the study workspaces is the module's room: its level and folder (touch to change the level), the time left, the file put forward with its reason, and every file of the module by chapter, read or not, to open any. A project's room lists its own files, a campaign's opens its folder (`boussole campaign dir NAME FOLDER`). Starting a session no longer opens a file by itself.
- **Boussole, Save & leave:** Pause becomes Save & leave. A session left without Close, even by shutting the computer down, is saved too. Today puts it first with Continue, the time left and the page you were on; Continue takes you back to the room, Liseuse at that page.
- **Boussole, Close:** only where you stopped and how each exercise went: Solved, With help or Stuck. How it went and the note are gone.
- **Boussole, Today:** the session under way, the ones to continue, the next one with Start and Later, Start a session (which holds the suggestions and I have time), and what comes after. The day's timeline stays in Week.
- **Boussole, More:** exams and hand-ins, rhythm, calendars, new files to sort and settings. The Files tab, Projects, Campaigns and Subjects pages are gone: a module's level is set in its room, the rest from a terminal.
- **Boussole, names:** subjects are called modules.
- **Boussole, Later:** Later asks until when: in 30 minutes, in an hour, tomorrow, the day after, or a time or a day you type. Until then nothing is planned, rung or suggested, and what was planned meanwhile is placed again after it; you can still start a session yourself. Back now frees the rest. Not tonight is gone: Later until tomorrow does it for the whole evening.

### Fixed
- **Bar, drawers:** in light mode, a hovered button no longer flashes grey, and a tight margin in Progress reads as a pale amber.
- **Boussole, plan:** solution folders (`Corriges`, `Solutions`) are no longer planned as course work.
- **Bar, Boussole:** no more "to declare" badge: a session left open is saved, to continue.
- **Boussole, Today:** a session of a later day that you started now shows under Today, with Pause and Close; it was missing from the drawer.
- **Boussole, Close:** a project session no longer pre-ticks the whole step as done after one session; the step is done when its hours are.
- **Boussole, I have time:** picking a subject and a duration starts the session and, in focus mode, takes you to the study workspaces; it only planned it.

## 1.6.1

### Fixed
- **Firefox:** on a machine set up with cc-pkg-mng, Firefox shows the coucou theme and the new tab again; only its settings were installed. Quit Firefox completely and relaunch it after the upgrade.

## 1.6.0 (October 11 2026)

### Added
- **Password card:** passwords asked for outside a terminal, by the system, ssh, git or gpg, are typed on one card in the middle of the screen, which shows the command that asks, for example `claude › git push origin master`. No key is kept in memory: every push waits for you.

### Changed
- **Bar, drawers:** the drawers are frosted glass. What is behind them shows through, blurred, so a drawer takes on the colour of your wallpaper or window: darkened and vivid in dark mode, milky cream in light mode. Their tiles and text stay readable over a white page as over a black terminal.
- **Bar, launchers:** an app that keeps running when you close it, such as Discord or Steam, keeps its chip, dimmed, until it really quits. A click brings its window back, and its actions offer Open window.
- **Balise:** a detail page makes the drawer grow to show it whole, up to 640 px, then scrolls. The lists keep the home's height.

### Fixed
- **System dialogs:** an action that needs administrator rights, outside a terminal, asks for your password again; it used to fail without asking.
- **Boussole:** hovering a button no longer flashes grey.
- **Bar, keybinds sheet:** holding SUPER shows the sheet above Boussole and the notifications when they are open, instead of under them.

## 1.5.0 (October 10 2026)

### Added
- **Boussole, I have time:** pick a subject before the duration, and its next task starts now, in the plan's order.
- **Boussole, free time:** open the drawer with nothing planned, in a free period at school or an evening, and Today starts with what would help most: the nearest tutorial to prepare, the subject furthest behind its exam, a subject you are behind in, or any subject's next task, started in one click. It never shows on its own.
- **Boussole, the programme:** under Progress, one card per subject with its exam, the sessions to spare before it and the hours planned; a week-by-week list; and "What if…", which shows how each lever (a Saturday of blocks, longer evenings, a study week, a subject's level) would change the margins before you apply it. Today says so when a subject no longer fits before its exam.
- **Boussole, study weeks:** a holiday period can be a study week (More › Rhythm › Periods): each weekday gets two blocks on top of its evening.
- **Boussole, subjects:** say how fast a subject's sheets go (quick, as estimated, long), and mark a course subject whose sheets are only read, its exercises left to the exercise files, tutorials and exam subjects.

### Fixed
- **Workspaces:** compacting the workspaces leaves Boussole's study workspaces where they are.
- **Firefox, address bar:** moving through the suggestions with Tab or the arrows highlights the one you are on again; it was invisible.
- **Liseuse:** maths, lists and bold inside a hidden solution (a `<details>` block, "Corrigé") are rendered instead of shown as typed, and so is display maths written between two lines holding a single `$`. Notes already opened are rendered again the next time.

### Changed
- **Firefox, new tab:** the Firefox logo in the middle with the search field just under it, your first six pinned shortcuts in a dock at the bottom with a + to add one, and on the right two short lists, your other pinned sites under Favorites, then your frequent sites; the search field, the dock and the lists are frosted glass, over a faint square grid that fades out towards the edges. The shortcuts you pin are no longer reset at each launch.
- **Firefox, dark mode:** OLED black: the tab strip, the toolbars, the sidebar and the new-tab page are pure black, and only the address bar, menus and the selected tab lift off it. The selected tab catches a thin line of light along its top, in light mode too. Firefox's Light and Dark themes switch between the coucou light and dark; any other theme you pick, and any wallpaper chosen in the new tab's Customize panel, shows as it is.
- **Firefox:** launching it now opens the new-tab page instead of Google's home page.

## 1.4.1

### Added
- **Boussole, focus mode:** starting a session can take you to study workspaces of their own, with its file in Liseuse and the session's panel beside it: the time left, the objective, the evening's files and a Next file button. Your own workspaces stay as they are, and Pause or Close brings you back to them. Notifications keep quiet while you are there. Turn it on in More › Rhythm.
- **Boussole, away from the sheet:** when something outside the study workspaces has the screen for a while during a session, Boussole asks whether it is for the session, sooner when the exam is close or the subject is one you are behind in. A video playing is asked about after 30 seconds, even beside the sheet. Personal time is taken out, and your answer is remembered. Neovim tells it which file you edit.

### Fixed
- **Workspaces:** `Super` + scroll up goes to the next workspace again; both directions used to go back.
- **Boussole:** a session's sheet opens in Liseuse again, rather than in another app; the service could not find Liseuse.

### Changed
- **Liseuse:** in dark mode, books and notes now sit on a dark grey page with softer white text instead of white on pure black, which was tiring to read for long.
- **Firefox:** the selected tab and the focused address bar are now a plain raised surface without the grey ring around the tab and the bright ring around the bar. Keyboard focus keeps its ordinary focus outline, and the coucou palette is otherwise untouched.

## 1.4.0 (October 6 2026)

### Fixed
- **cc-pkg-mng and dnf:** on the day a release comes out, `sudo dnf upgrade` and `cc-pkg-mng upgrade` now see it. dnf used to keep its list of coucou-shell's packages for two days, so the new `cc-pkg-mng` did not show up and an upgrade could fail to find the release's packages. dnf now checks coucou-shell's repository at most an hour after a release, and `cc-pkg-mng upgrade` re-reads it before installing. Your next upgrade updates the repository's settings on your machine.
- **Games, NVIDIA:** games that use DLSS, such as Kingdom Come: Deliverance II or The Witcher 3, start right after boot. Before, they reported an incompatible GPU until you had run `nvidia-smi` once. If you install the NVIDIA driver yourself later, this works from the next restart.

### Added
- **Boussole:** a study planner in the bar, optional. It plans study sessions from your course folder and your timetable, rings them in the bar's central island with a chime, follows them through Liseuse, and replans when you close them. `Super + D` opens its drawer, `Super + Shift + D` adds an exam, a hand-in or a task in one line.
- **Boussole, subjects:** tell it where you stand in each subject. One you are behind in gets more time per sheet and goes first; one where the tutorials are enough has nothing to read, only its tutorials, projects and exams.
- **Boussole, one thing at a time:** each task is its own session, started, put off or said "not tonight" on its own; putting off one no longer takes the rest of the evening with it. A "not tonight" said by mistake can be brought back, and "I have time" starts a session right away, even on an evening you had said no to.
- **Boussole, days:** an afternoon without courses becomes a real study block, and a campaign's daily time goes to the daytime (a free period at school, that afternoon, the morning) before the evening. Friday evening stays free.
- **Wallpapers, light and dark:** a wallpaper that comes in a light and a dark version follows light and dark mode, like on GNOME: switch modes and the desktop fades to the other version. Prisme shows each pair as one card, in the version for the current mode, and opens it on both halves when you land on it. Every GNOME wallpaper is a pair, and so are coucou-shell's own Plis, Soie and Relief, which now have a light version. Name two of your own wallpapers `name.jpg` and `name-dark.jpg` and they pair up too.

### Changed
- **Bar:** drawers, notifications, OSD and the controller popup now follow light and dark mode.
- **Notification centre:** it is now a panel down the right edge of the screen, from under the bar to the bottom, sliding in from the right.
- **Wallpapers:** the default wallpaper on a new install is the Relief pair, light or dark with your mode.

## 1.3.0 (October 3 2026)

### Changed
- **cc-pkg-mng, installing and upgrading:** the work shows as a live list instead of a scroll of lines. Everything to do is listed from the start, the part in progress unfolds with its steps and a spinner, finished parts fold to one line with their time, and a bar at the top counts them with the time elapsed. Package installs show how many packages are done. If something fails, it stays unfolded with its last lines and where the full log is.
- **cc-pkg-mng, help:** `cc-pkg-mng` alone or `--help` shows the coucou logo and the commands grouped by what they are for, from everyday upgrades to setting up a machine.
- **cc-pkg-mng, version:** `cc-pkg-mng --version` also says which release this machine runs, on which channel, whether a newer one is out, and which apps run from your checkout. `-V` still prints the bare version.
- **cc-pkg-mng, init:** setting up a machine opens on the logo and numbers its steps (where, channel, applications, summary), and every question has a clearer look.

## 1.2.2

### Fixed
- **cc-pkg-mng:** a background service that an upgrade adds now starts right away, instead of waiting for your next login. After updating to 1.2.0, Manette stayed off until then, so the controller menu did nothing.

## 1.2.1

### Fixed
- **cc-pkg-mng:** `cc-pkg-mng upgrade` no longer leaves Hyprland's red "hyprland.lua: No such file or directory" banner on screen. Hyprland now reloads once, on the new version, when the upgrade has put it in place. The same goes for `rollback` and for switching channels.

## 1.2.0 (October 3 2026)

### Added
- **Game controllers:** Xbox, PlayStation, Switch and Steam controllers work in the shell, over USB or Bluetooth, and so does any other controller Linux recognises as one. Nothing to set up: plug it in or pair it and it is there.
- **Game controllers, Xbox over USB:** after this update, restart your computer once, so the Xbox controller driver loads. Until then a wired Xbox controller stays off.
- **Game controllers, Xbox over Bluetooth:** if the Xbox button keeps blinking and the controller drops the connection, its firmware is too old for Linux. Update it once from the Xbox Accessories app on Windows or from an Xbox console, and it then pairs and reconnects on its own.
- **Game controllers, arrival:** when a controller connects, a pill at the bottom of the screen shows its name, how it is connected, its battery when it reports one, and which button opens the menu.
- **Bar, right-hand group:** while a controller is connected, its silhouette sits next to `hdr` and fills up from the left like a battery gauge. It turns green while charging and red under 15 %. A wired controller with no battery to report is drawn as an outline, and two controllers show two silhouettes.
- **Controller menu:** the Guide button (the Xbox, PS, Steam or Home logo) opens a menu on the screen you are using. A controller without a Guide button opens it with `Select` + `Start` held together. Guide again, or `B`, closes it.
- **Controller menu, over a game:** while Steam or a fullscreen window has focus, a short press on Guide is left to the game; hold Guide to open the menu. The press that wakes a controller up never opens it.
- **Controller menu, while open:** the game behind receives nothing from the controller, so nothing you do in the menu reaches it. The keyboard (arrows, `Return`, `Esc`, `Tab`) and the mouse work in it too.
- **Controller menu, Continue:** the menu opens on the game you played last, with its artwork, its launcher and when you last played it. `A` starts it.
- **Controller menu, Library:** your other games in one row, Steam and Lutris together with their covers, plus the games other launchers (Heroic, Bottles, itch) add to the applications menu. Each card says where the game comes from. Tools filed as games, such as GOverlay, are left out.
- **Controller menu, Launchers:** a shortcut for each launcher installed among Steam, Lutris, Heroic, Bottles and itch. Steam opens in Big Picture, and Lutris shows how many games it has.
- **Controller menu, System:** Apps, Sleep, and Turn off, which disconnects a Bluetooth controller so it switches off.
- **Controller menu, starting games:** games start straight from the menu. A Lutris game starts without the Lutris window, and Steam starts quietly in the background for its games, without its library.
- **Controller menu, all apps and games:** `Y` opens a grid of every application and game, with a tab for All, one for Games and one for each launcher, each with its count. `LT` `RT` switch tabs, `X` jumps to the next letter, `B` goes back.
- **Controller menu, buttons:** the menu draws the buttons of the controller in your hands: coloured letters on an Xbox controller, the four shapes on a PlayStation one, letters on Switch and Steam controllers, and dots marking the position on a controller it does not know. Shoulder buttons and triggers carry their own names (`LB` `RB`, `L1` `R1`, `L` `R`, `LT` `RT`, `L2` `R2`, `ZL` `ZR`). On every controller the bottom button opens and the right one goes back, so on a Switch controller `B` opens.
- **Controller menu, moving around:** the d-pad or the left stick moves the selection the way the menu is laid out, and holding a direction keeps moving. Each row remembers where you were in it.
- **Controller menu, volume:** `LB` `RB` (or `L1` `R1`, `L` `R`) turn the volume down and up from anywhere in the menu; the level shows in the menu and on the usual dial.
- **Controller menu, key binding:** `qs -c bar ipc call bar controllerMenu` opens or closes the menu without a controller, so you can bind it to a key.
- **Steam and Lutris** can be installed together as the `games` unit. It is not installed by default.
- **cc-pkg-mng:** `cc-pkg-mng dev roue` runs Roue built from the checkout you're working in, in place of the release's, on the stable channel. Your shortcuts and the bar pick it up straight away, with nothing to change in your configuration, and running it again after an edit takes a couple of seconds. `cc-pkg-mng dev` shows what is running, and `cc-pkg-mng dev --off` puts the release's Roue, Prisme and Balise back. It works for Prisme and Balise too.

## 1.1.1

### Fixed
- **Roue, Prisme and Balise on the stable channel:** their shortcuts, the bar's buttons and Balise's background service work again after you install or upgrade. Moving to stable used to remove the copies the session starts them from, so nothing opened.
- **Liseuse:** in a book, `Space` now scrolls exactly one screen instead of jumping to the next page. Before, it landed halfway down the next page and could skip the end of the current one. On slides, `Space` still turns the page.

## 1.1.0 (October 1 2026)

### Added
- **fontview**, a font viewer as simple as imv: open a font file from Nemo or run `fontview FILE`. `←` `→` step through the fonts in the folder, `+` `−` change the size.
- **swayimg** is the image viewer, in the shell's colours, and opens images by default. `←` `→` go through the folder, `Return` shows a gallery, and `e` opens the image in satty to crop or annotate it, saved as a copy next to the original.

### Changed
- **Balise:** pressing Scan now shows it working, a spinning ring and "Scanning" until the results are in, and an empty list reads "Searching…" meanwhile.
- **Bar, centre island:** when a track starts, the media pill opens on its title and artist for a few seconds, then folds back to the wave.
- **Bar, centre island:** while music plays, each bar of the media wave has its own colour, a dusk spectrum from indigo to amber that leans toward the colours of the cover. Paused, the wave goes back to cream like the rest of the bar.
- **mpv** gets a modern interface (uosc) in the shell's colours, with a thumbnail when you hover the timeline (thumbfast). It is now set to open video and audio files, and what it plays shows in the bar's media pill, like any other player.

## 1.0.2

### Fixed
- **Bar, centre island:** right after login, the bar now shows every workspace, 1 to 5 and 6 to 10 on two screens. Before, it sometimes showed only one per screen, and the others appeared one by one as you visited them.

## 1.0.1

### Fixed
- **Bar, centre island:** a workspace no longer looks occupied once its last window is closed. Sometimes the bar missed a window closing (it happened with a Java popup) and kept counting it. It now goes by Hyprland's own window count.

## 1.0.0 « Coucou à tous »

The first version you can install on a fresh Fedora netinstall.

### Install and updates
- **Installed with dnf**, from coucou-shell's own signed repository: add `coucou-shell.repo`, install `cc-pkg-mng`, then run `cc-pkg-mng init`. Roue, Prisme and Balise come prebuilt, so you don't need the Rust toolchain.
- **cc-pkg-mng 2**, coucou-shell's package manager. `init` sets up a new machine, `install` and `remove` add or take away parts, `upgrade` and `rollback` move between releases, `channel` switches between stable (releases) and edge (every commit), and `set` changes one of your answers, like the WezTerm build.
- All the questions come first, your password is asked only once, and every package goes in a single dnf transaction.
- Everything is split into three layers: **core** (the shell itself), **apps** (default applications you can swap out), and **configs** (optional personal setups you can take or leave; any file one would replace is backed up first).
- If you used the previous manager, it picks up your checkout and what was already installed.
- The documentation is now also a website: https://lucasssoh.github.io/dotfiles/.

### Desktop
- **Hyprland**, configured in Lua, with per-machine profiles and an optional private file for your own overrides.
- **The bar** (Quickshell): clock and metrics, workspaces and media, and drawers for network and Bluetooth, power, an audio mixer with a per-application equalizer, notifications, and a calendar with an agenda (`Super + A`). Hold `Super` to see every key binding on a keyboard.
- **Veille**, a big clock that shows up when you're working late.
- **Roue**, a radial wheel for the power menu, power profiles, display layouts and actions.
- **Prisme**, the wallpaper picker. Wallpapers are fitted to the resolution of each connected screen, once at install and again whenever you plug in a new one.
- **Balise**, the network and Bluetooth service behind the bar.
- **Liseuse** (`Super + F`), a reading library for PDF, EPUB, comics and Markdown with maths and PlantUML.
- **Default applications by role**: `Super + Enter`, `Super + B` and `Super + E` open your terminal, browser and file manager, whichever ones you use.
- A GTK theme in the bar's palette, light and dark.
- An optional boot splash and an optional greetd login screen.

### Wallpapers
- Three coucou-shell wallpapers, **Aube · Plis**, **Aube · Soie** and **Aube · Relief**, up to 5K. Relief is the default on a new install.
- The GNOME default wallpapers, light and dark.

### Applications
- Installed by default, and each one can be swapped for another: WezTerm, Firefox, Nemo, Neovim, mpv.
- Optional: Brave, MangoHud, fastfetch, ccnote, ccslide.
- Optional configurations: shell (zsh and bash), WezTerm, Neovim, and a set for mpv, MangoHud, fastfetch and Brave.

### Removed
- Waybar and Rofi, replaced by the bar and fuzzel.
- The KDE Plasma session is no longer offered.

### Requirements
- Fedora 44, x86_64.

### Licence
- coucou-shell is for personal use (see `LICENSE.md`). Third-party parts keep their own licences, listed in `THIRD-PARTY.md`.
