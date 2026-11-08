# satty, the screenshot editor behind Super + S, rebuilt from upstream's
# tagged tarball with three patches: frosted glass behind its toolbars in
# fullscreen (satty-glass.patch), "Screenshot" as its name to the rest
# of the system, with its own id, desktop entry and icon
# (satty-screenshot.patch), and a pill over the image that says what an
# action did, Copied or Saved (satty-toast.patch). The package and the command stay `satty`. Its
# look is ~/.config/satty/overrides.css.
#
# packaging/build-rpms.sh fetches the tarball, checks it against
# satty.sha256 and builds this next to coucou-shell's own RPMs. To move to a
# new satty: bump Version, update satty.sha256, rebase the patches.

%global debug_package %{nil}

Name:           satty
# Above the mineiro/satty COPR's builds, which machines that had it may
# still have enabled: dnf keeps this one whatever the COPR publishes.
Epoch:          1
Version:        0.22.0
Release:        3.coucou%{?dist}
Summary:        Screenshot annotation tool
# satty itself; the Rust crates bundled into the binary are MIT or Apache-2.0.
License:        MPL-2.0
URL:            https://github.com/Satty-org/Satty
Source0:        https://github.com/Satty-org/Satty/archive/v%{version}/Satty-%{version}.tar.gz
Patch0:         satty-glass.patch
Patch1:         satty-screenshot.patch
Patch2:         satty-toast.patch
Source1:        io.github.lucasssoh.Screenshot.desktop
Source2:        io.github.lucasssoh.Screenshot.svg
ExclusiveArch:  x86_64

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1)
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(fontconfig)

%description
Satty annotates screenshots: crop, arrows, text, blur, highlight. This
build frosts the image behind its toolbars in fullscreen, says what an
action did over the image, and shows itself to the system as Screenshot
(io.github.lucasssoh.Screenshot).

%prep
%autosetup -n Satty-%{version} -p1

%build
# ci-release also writes the man page and the shell completions.
cargo build --release --locked --features ci-release

%install
install -Dm755 target/release/satty   %{buildroot}%{_bindir}/satty
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/applications/io.github.lucasssoh.Screenshot.desktop
install -Dm644 %{SOURCE2} %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/io.github.lucasssoh.Screenshot.svg
install -Dm644 man/satty.1            %{buildroot}%{_mandir}/man1/satty.1
install -Dm644 completions/satty.bash %{buildroot}%{_datadir}/bash-completion/completions/satty
install -Dm644 completions/_satty     %{buildroot}%{_datadir}/zsh/site-functions/_satty
install -Dm644 completions/satty.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/satty.fish

%files
%license LICENSE
%doc README.md
%{_bindir}/satty
%{_datadir}/applications/io.github.lucasssoh.Screenshot.desktop
%{_datadir}/icons/hicolor/scalable/apps/io.github.lucasssoh.Screenshot.svg
%{_mandir}/man1/satty.1*
%{_datadir}/bash-completion/completions/satty
%{_datadir}/zsh/site-functions/_satty
%{_datadir}/fish/vendor_completions.d/satty.fish
