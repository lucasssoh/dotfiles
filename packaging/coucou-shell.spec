# coucou-shell's binaries: the manager and the native apps, built from
# one tagged source tarball. The configs are not packaged -- `cc-pkg-mng init`
# clones them.
#
#   rpmbuild -bb --define "cc_version 1.0.0" packaging/coucou-shell.spec
#
# packaging/build-rpms.sh does exactly that from a git tag.

%global debug_package %{nil}
# No %%changelog: the release notes live in CHANGELOG.md.
%global source_date_epoch_from_changelog 0

Name:           coucou-shell
Version:        %{?cc_version}%{!?cc_version:0.0.0}
Release:        1%{?dist}
Summary:        coucou-shell, a Fedora + Hyprland desktop
License:        LicenseRef-coucou-shell-personal-use
URL:            https://github.com/lucasssoh/dotfiles
Source0:        coucou-shell-%{version}.tar.gz
ExclusiveArch:  x86_64

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(gtk4-layer-shell-0)

%description
coucou-shell's binaries. Install cc-pkg-mng, then run `cc-pkg-mng init`.

%package -n cc-pkg-mng
Summary:        coucou-shell package manager
Requires:       git-core
Requires:       dnf5
Requires:       sudo

%description -n cc-pkg-mng
Installs, upgrades and rolls back coucou-shell. Start with `cc-pkg-mng init`.

%package -n roue
Summary:        Radial selection wheel for coucou-shell

%description -n roue
The wheel behind coucou-shell's power menu, power profile, display layout and
actions.

%package -n prisme
Summary:        Wallpaper picker for coucou-shell

%description -n prisme
coucou-shell's wallpaper picker, and wallpaper-filter, which fits wallpapers
to each screen.

%package -n balise
Summary:        Network and Bluetooth daemon for coucou-shell
Requires:       NetworkManager
Requires:       bluez

%description -n balise
The daemon behind the Balise drawer of coucou-shell's bar: Wi-Fi, Bluetooth
and Ethernet.

%package -n manette
Summary:        Gamepad daemon for coucou-shell

%description -n manette
The daemon behind the controller popup of coucou-shell's bar: it notices
gamepads as they arrive and opens the popup on the Guide button.

%package -n boussole
Summary:        Study planner for coucou-shell
Requires:       mupdf
Requires:       curl

%description -n boussole
The service behind the Boussole drawer of coucou-shell's bar: it plans study
sessions from a course folder and a timetable, rings their alerts and follows
them through Liseuse.

%package -n sesame
Summary:        Password prompts for coucou-shell
Requires:       polkit

%description -n sesame
The daemon behind coucou-shell's password card: the session's polkit agent,
and the askpass and pinentry that bring ssh, git and gpg prompts to the bar,
with the command that asks.

%prep
%autosetup

%build
for crate in crates/cc-pkg-mng config/hyprland/roue-src config/hyprland/prisme-src config/hyprland/balise-src config/hyprland/manette-src config/hyprland/boussole-src config/hyprland/sesame-src; do
    cargo build --release --locked --manifest-path "$crate/Cargo.toml" --target-dir target
done

%install
install -Dm755 target/release/cc-pkg-mng       %{buildroot}%{_bindir}/cc-pkg-mng
install -Dm755 target/release/roue             %{buildroot}%{_bindir}/roue
install -Dm755 target/release/prisme           %{buildroot}%{_bindir}/prisme
install -Dm755 target/release/wallpaper-filter %{buildroot}%{_bindir}/wallpaper-filter
install -Dm755 target/release/balise           %{buildroot}%{_bindir}/balise
install -Dm755 target/release/manette          %{buildroot}%{_bindir}/manette
install -Dm755 target/release/boussole         %{buildroot}%{_bindir}/boussole
install -Dm755 target/release/sesame           %{buildroot}%{_bindir}/sesame

%files -n cc-pkg-mng
%license LICENSE.md
%{_bindir}/cc-pkg-mng

%files -n roue
%license LICENSE.md
%{_bindir}/roue

%files -n prisme
%license LICENSE.md
%{_bindir}/prisme
%{_bindir}/wallpaper-filter

%files -n balise
%license LICENSE.md LICENSES/MIT-Orbit.txt
%{_bindir}/balise

%files -n manette
%license LICENSE.md
%{_bindir}/manette

%files -n boussole
%license LICENSE.md
%{_bindir}/boussole

%files -n sesame
%license LICENSE.md
%{_bindir}/sesame
