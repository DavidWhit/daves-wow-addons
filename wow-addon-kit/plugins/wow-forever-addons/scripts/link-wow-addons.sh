#!/usr/bin/env bash
# link-wow-addons.sh - macOS twin of Link-WowAddons.ps1 for Macs without PowerShell 7.
#
# Symlinks every addon folder (one holding <Folder>.toc or <Folder>_<Flavor>.toc) into
# <client>/Interface/AddOns of every client folder (_retail_, _classic_beta_, ...) under the
# WoW root. Run it after cloning or pulling. Unlike the PowerShell script it does not read the
# TOC's Interface lines: every addon goes into every client.
#
#   - a symlink to this addon's folder is left alone;
#   - a symlink pointing anywhere else is re-pointed;
#   - a real folder is moved to <client>/Interface/AddOns.backup/<Name>-<timestamp> first.
#   --remove deletes only symlinks that point at these addons; nothing else is touched.
#
# Usage:
#   bash link-wow-addons.sh [--dry-run] [--remove] [--wow-root DIR] [ADDONS_DIR]
#   WOW_ROOT="/Volumes/Games/World of Warcraft" bash link-wow-addons.sh
#
# ADDONS_DIR defaults to the nearest "wowaddons" folder walking up from the current folder,
# then from this script's folder. It may also be one addon folder, to link just that addon.
# WOW_ROOT defaults to /Applications/World of Warcraft.

set -eu

dry_run=0
remove=0
wow_root="${WOW_ROOT:-/Applications/World of Warcraft}"
addons_dir=""

# Prints the comment block above (up to the first blank line).
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) dry_run=1 ;;
		--remove) remove=1 ;;
		--wow-root) [ $# -ge 2 ] || { echo "--wow-root needs a folder" >&2; exit 2; }; wow_root="$2"; shift ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) addons_dir="$1" ;;
	esac
	shift
done

# Walks up from $1 looking for a "wowaddons" folder; prints it if found.
find_up() {
	local d="$1"
	while [ -n "$d" ]; do
		if [ -d "$d/wowaddons" ]; then printf '%s\n' "$d/wowaddons"; return 0; fi
		[ "$d" = "/" ] && break
		d="$(dirname "$d")"
	done
	return 1
}

if [ -z "$addons_dir" ]; then
	script_dir="$(cd "$(dirname "$0")" && pwd -P)"
	addons_dir="$(find_up "$(pwd -P)" || find_up "$script_dir" || true)"
	if [ -z "$addons_dir" ]; then
		echo "No wowaddons folder found above the current folder or this script. Pass the addons folder as an argument." >&2
		exit 1
	fi
fi
[ -d "$addons_dir" ] || { echo "Not a folder: $addons_dir" >&2; exit 1; }
addons_dir="$(cd "$addons_dir" && pwd -P)"

if [ ! -f "$wow_root/.build.info" ]; then
	echo "World of Warcraft not found at: $wow_root (no .build.info)." >&2
	echo "Pass --wow-root \"<folder holding .build.info>\" or set WOW_ROOT." >&2
	exit 1
fi

# Does $1 (an addon folder) hold <Name>.toc or <Name>_<Flavor>.toc?
is_addon() {
	local name t
	name="$(basename "$1")"
	[ -f "$1/$name.toc" ] && return 0
	for t in "$1/${name}_"*.toc; do
		[ -f "$t" ] && return 0
	done
	return 1
}

# Resolved physical path of a symlink's target folder, or empty if it is dangling.
link_dest() { (cd "$1" 2>/dev/null && pwd -P) || true; }

run() {
	if [ "$dry_run" -eq 1 ]; then printf 'would run:'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}

# ADDONS_DIR may also be one addon folder: then link just that one.
if is_addon "$addons_dir"; then srcs=("$addons_dir/"); else srcs=("$addons_dir"/*/); fi

stamp="$(date +%Y%m%d-%H%M%S)"
rows=""
failed=0
changed=0
row() {
	local status="$3"
	if [ "$dry_run" -eq 1 ]; then
		case "$status" in Linked) status=WouldLink ;; Relinked) status=WouldRelink ;; Unlinked) status=WouldUnlink ;; esac
	fi
	case "$status" in Linked|Relinked) changed=1 ;; esac
	rows="${rows}$(printf '%-16s %-24s %-14s %s' "$1" "$2" "$status" "${4:-}")"$'\n'
}

found_client=0
for client in "$wow_root"/_*_/; do
	[ -d "$client" ] || continue
	found_client=1
	client="${client%/}"
	cname="$(basename "$client")"
	addons="$client/Interface/AddOns"

	for src in "${srcs[@]}"; do
		[ -d "$src" ] || continue
		src="${src%/}"
		is_addon "$src" || continue
		name="$(basename "$src")"
		dest="$addons/$name"

		if [ "$remove" -eq 1 ]; then
			if [ -L "$dest" ]; then
				if [ "$(link_dest "$dest")" = "$src" ]; then
					if run rm "$dest"; then row "$cname" "$name" "Unlinked"; else row "$cname" "$name" "Failed"; failed=1; fi
				else
					row "$cname" "$name" "Kept" "links to $(readlink "$dest"); left alone"
				fi
			elif [ -e "$dest" ]; then
				row "$cname" "$name" "Kept" "real folder, not a link; left alone"
			else
				row "$cname" "$name" "NotLinked"
			fi
			continue
		fi

		if [ -L "$dest" ]; then
			if [ "$(link_dest "$dest")" = "$src" ]; then
				row "$cname" "$name" "AlreadyLinked"
				continue
			fi
			old="$(readlink "$dest")"
			# rm on the link itself (no trailing slash) removes only the link.
			if run rm "$dest" && run ln -s "$src" "$dest"; then
				row "$cname" "$name" "Relinked" "was -> $old"
			else
				row "$cname" "$name" "Failed" "could not re-point"; failed=1
			fi
		elif [ -e "$dest" ]; then
			backup_dir="$client/Interface/AddOns.backup"
			backup="$backup_dir/$name-$stamp"
			n=1
			while [ -e "$backup" ]; do n=$((n + 1)); backup="$backup_dir/$name-$stamp-$n"; done
			if ! { run mkdir -p "$backup_dir" && run mv "$dest" "$backup"; }; then
				row "$cname" "$name" "Failed" "could not move the real folder to $backup_dir"; failed=1
			elif run ln -s "$src" "$dest"; then
				if [ "$dry_run" -eq 1 ]; then row "$cname" "$name" "Linked" "real folder would move to AddOns.backup first"
				else row "$cname" "$name" "Linked" "real folder moved to $backup"; fi
			else
				row "$cname" "$name" "Failed" "real folder moved to $backup, but the link failed"; failed=1
			fi
		else
			if run mkdir -p "$addons" && run ln -s "$src" "$dest"; then
				row "$cname" "$name" "Linked"
			else
				row "$cname" "$name" "Failed" "could not link"; failed=1
			fi
		fi
	done
done

if [ "$found_client" -eq 0 ]; then
	echo "No client folders (_retail_, _classic_beta_, ...) under $wow_root." >&2
	exit 1
fi

echo "Addons: $addons_dir"
echo "WoW:    $wow_root (symlinks)"
[ "$dry_run" -eq 1 ] && echo "Dry run: nothing was changed."
echo
printf '%-16s %-24s %-14s %s\n' "Client" "Addon" "Status" "Detail"
printf '%-16s %-24s %-14s %s\n' "------" "-----" "------" "------"
printf '%s' "$rows"
echo
if [ "$changed" -eq 1 ] && [ "$dry_run" -eq 0 ]; then
	echo "In game: fully restart the client once so it sees newly linked addons, then enable them in the AddOns list."
fi
exit "$failed"
