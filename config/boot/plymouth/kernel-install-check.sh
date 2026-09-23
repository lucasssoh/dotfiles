#!/usr/bin/env bash
# 99-coucou-splash.install -- check, on every kernel install, that the new
# initramfs actually carries the boot splash.
#
# Nothing here BUILDS anything, and that is deliberate. The splash already
# survives a kernel update on its own: /etc/dracut.conf.d/90-coucou-splash
# .conf is read by every dracut run, and kernel-install's 50-dracut.install
# invokes a plain `dracut -f` with no --no-conf or --confdir, so a new
# kernel picks the theme up with no help from anyone. Re-running dracut
# from here would be a second builder racing the first.
#
# What was missing was never the building. It was the noticing. This
# module spent an afternoon on a boot splash that did not appear, with no
# error message anywhere, because dracut runs plymouth-populate-initrd
# with `2> /dev/null` and that script silently baked in the wrong theme.
# So this hook is a smoke alarm, not a sprinkler: it looks at what was
# just produced and says so, loudly, into the output of the very dnf
# transaction that produced it.
#
# kernel-install calls plugins as:
#     $0 add KERNEL_VERSION ENTRY_DIR KERNEL_IMAGE INITRD...
# and a non-zero exit aborts the transaction, which a check has no
# business doing. This one always exits 0.

COMMAND="${1:-}"
KERNEL_VERSION="${2:-}"
ENTRY_DIR="${3:-}"

[ "$COMMAND" = add ] || exit 0
[ -n "$KERNEL_VERSION" ] || exit 0

THEME_NAME="coucou"
THEME_FILE="/usr/share/plymouth/themes/$THEME_NAME/$THEME_NAME.plymouth"

say() { echo "coucou-splash: $*" >&2; }

# The initramfs may arrive as an argument, or sit where Fedora puts it.
# Take the first one that exists rather than assuming a layout. The
# initrds start at $5: $4 is the kernel image, which also exists, and
# taking it once had this hook report every new kernel as splash-less.
IMAGE=""
for candidate in "${@:5}" \
                 "/boot/initramfs-$KERNEL_VERSION.img" \
                 "$ENTRY_DIR/initrd"; do
    [ -n "$candidate" ] && [ -f "$candidate" ] && { IMAGE="$candidate"; break; }
done

if [ -z "$IMAGE" ]; then
    say "no initramfs found for $KERNEL_VERSION — cannot check the splash."
    exit 0
fi

# Run by hand rather than by kernel-install, this would otherwise report
# a missing theme when all it hit was /boot being root-only.
if [ ! -r "$IMAGE" ]; then
    say "cannot read $IMAGE (needs root) — check skipped."
    exit 0
fi

if lsinitrd "$IMAGE" -f "$THEME_FILE" 2>/dev/null | grep -q ModuleName; then
    exit 0
fi

# This is the failure that is invisible at boot: plymouthd falls back to
# the text splash, which under `quiet` draws nothing at all, and the
# machine looks switched off for the length of the boot.
say ""
say "the initramfs for $KERNEL_VERSION does NOT carry the boot splash theme."
say "  image:  $IMAGE"
say "  wanted: $THEME_FILE"

# The regression that caused this once before, worth naming because the
# symptom gives no clue: plymouth-set-default-theme reads the theme back
# with an unanchored /Theme/ regex, so a commented "#Theme=" line in
# plymouthd.conf concatenates into the value and the whole lookup falls
# through to "text". An updated plymouth package restoring that file is
# all it would take.
REPORTED="$(plymouth-set-default-theme 2>/dev/null)"
if [ "$REPORTED" != "$THEME_NAME" ]; then
    say ""
    say "plymouth-set-default-theme reports '$REPORTED', not '$THEME_NAME'."
    say "check for a commented Theme= line in /etc/plymouth/plymouthd.conf:"
    say "  sudo sed -i -E '/^\\s*#\\s*Theme\\s*=/d' /etc/plymouth/plymouthd.conf"
fi

say ""
say "to repair:  ./config/boot/plymouth/install.sh"
say ""
exit 0
