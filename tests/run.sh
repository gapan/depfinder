#!/bin/bash
#
# Test suite for depfinder.
#
# Everything is built from scratch in a temporary directory: small ELF
# binaries and libraries, test packages, a fake set of "installed"
# libraries and a fake package database. depfinder is pointed at the
# fake database with DEPFINDERPKGDB, so the results don't depend on what
# is installed on the system running the tests.
#
# Usage: tests/run.sh [-v]     (run from anywhere; needs gcc, tar, xz)
#   -v   show depfinder's output for failing tests
#
# Tests for known bugs are marked as expected failures (XFAIL). When a
# bug is fixed its test reports XPASS: remove the xfail marker then.

TOPDIR=$(cd "$(dirname "$0")/.." && pwd)
VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1

SEARCH="$TOPDIR/depfinder-search/depfinder-search"
if [ ! -x "$SEARCH" ]; then
	echo "ERROR: $SEARCH not found, run make first" >&2
	exit 2
fi
for tool in gcc tar xz; do
	if ! command -v $tool >/dev/null; then
		echo "ERROR: $tool is required to run the tests" >&2
		exit 2
	fi
done

# Use the same library directory names as the system
if [ -d /usr/lib64 ] && [ ! -h /usr/lib64 ]; then
	SUF=64
else
	SUF=""
fi
LIB=usr/lib$SUF

W=$(mktemp -d "${TMPDIR:-/tmp}/depfinder-tests.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT

PASS=0; FAIL=0; XFAIL=0; XPASS=0; SKIP=0

# A copy of depfinder set up the same way "make install" sets it up,
# but using the depfinder-search binary from the source tree
DF="$W/depfinder"
sed -e "s|^LIBDIRSUFFIX=.*|LIBDIRSUFFIX=\"$SUF\"|" \
    -e "s|^DEPFINDERSEARCH=.*|DEPFINDERSEARCH=\"$SEARCH\"|" \
    -e "s|^DEPFINDERPYTHON=.*|DEPFINDERPYTHON=\"$TOPDIR/depfinder-python\"|" \
    "$TOPDIR/depfinder" > "$DF"
chmod 755 "$DF"

#
# Fixture helpers
#

# The fake system root, where "installed" libraries live
SYS="$W/sys"
mkdir -p "$SYS/$LIB" "$SYS/py"

# mklib <dir> <name> <major>: builds lib<name>.so.<major>.0.0 with soname
# lib<name>.so.<major> in <dir> and prints the real file name
mklib()
{
	echo "int $2_func(void) { return $3; }" > "$W/src-$2.c"
	gcc -shared -fPIC -Wl,-soname,lib$2.so.$3 \
		-o "$1/lib$2.so.$3.0.0" "$W/src-$2.c" || exit 2
	echo "lib$2.so.$3.0.0"
}

# mkbin <output> <libdirs> <lib>...: builds a binary linked against the
# given libraries (by name, e.g. "bar"), found in <libdirs> (separated
# by colons)
mkbin()
{
	local out=$1 libdirs=$2; shift 2
	local calls="" decls="" links="" l
	for l in "$@"; do
		decls="$decls int ${l}_func(void);"
		calls="$calls ${l}_func();"
		links="$links -l$l"
	done
	echo "$decls int main(void) { $calls return 0; }" > "$W/src-main.c"
	mkdir -p "$(dirname "$out")"
	local ldirs=() d
	IFS=: read -ra d <<< "$libdirs"
	for l in "${d[@]}"; do ldirs+=("-L$l"); done
	gcc -o "$out" "$W/src-main.c" "${ldirs[@]}" $links || exit 2
}

# mkrecord <db> <pkgname> <file>...: writes a package database record.
# Files are given as paths relative to /, like in a real database.
mkrecord()
{
	local db=$1 name=$2 f; shift 2
	mkdir -p "$db"
	{
		echo "PACKAGE NAME:     $name"
		echo "PACKAGE DESCRIPTION:"
		echo "FILE LIST:"
		echo "./"
		for f in "$@"; do echo "$f"; done
	} > "$db/$name"
}

# mkpkg <dir> <file>: makes a package file from a directory the way a
# real build does, with "makepkg -l y -c n". makepkg moves symlinks into
# install/doinst.sh and deletes them, so it packages a copy of the
# directory.
#
# With "slkbuild" as a third argument it uses slkbuild's
# makepkg_internal instead, which makes packages in GNU tar format. That
# is a function inside /usr/bin/slkbuild, so it is taken from there and
# run (it fails if slkbuild isn't installed). It is always used for .tbr,
# which pkgtools can't make.
mkpkg()
{
	local dir=$1 out=$2 copy tool=/sbin/makepkg rc
	if [ "$3" = slkbuild ] || [ "${out##*.}" = tbr ]; then
		[ -f /usr/bin/slkbuild ] || return 1
		[ "${out##*.}" = tbr ] && ! command -v brotli >/dev/null && return 1
		tool=makepkg_internal
	fi
	copy=$(mktemp -d "$W/mkpkg.XXXXXX")
	cp -a "$dir/." "$copy/"
	(
		cd "$copy" || exit 1
		if [ $tool = makepkg_internal ]; then
			eval "$(sed -n '/^makepkg_internal() {$/,/^}$/p' /usr/bin/slkbuild)"
			type makepkg_internal >/dev/null 2>&1 || exit 1
		fi
		$tool -l y -c n "$out"
	) > "$copy.log" 2>&1
	rc=$?
	if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
		echo "WARNING: $tool failed for $out:" >&2
		sed 's/^/  /' "$copy.log" >&2
		rm -f "$out"
	fi
	rm -rf "$copy" "$copy.log"
	[ -s "$out" ]
}

# Path of a file under $SYS as it appears in a database record
rel() { echo "${SYS#/}/$1"; }

#
# Build the fixtures
#

# Installed libraries:
#   libbar, from package bar
#   libbaz, from both baz and baz-solibs (an "either of" dependency)
BARLIB=$(mklib "$SYS/$LIB" bar 1)
ln -s "$BARLIB" "$SYS/$LIB/libbar.so.1"; ln -s "$BARLIB" "$SYS/$LIB/libbar.so"
BAZLIB=$(mklib "$SYS/$LIB" baz 2)
ln -s "$BAZLIB" "$SYS/$LIB/libbaz.so.2"; ln -s "$BAZLIB" "$SYS/$LIB/libbaz.so"

# libdash, from two packages with several "-" in their names
DASHLIB=$(mklib "$SYS/$LIB" dash 1)
ln -s "$DASHLIB" "$SYS/$LIB/libdash.so.1"; ln -s "$DASHLIB" "$SYS/$LIB/libdash.so"

# A library that is installed but that no package provides (e.g. built
# and installed by hand)
UNOWNEDLIB=$(mklib "$SYS/$LIB" unowned 1)
ln -s "$UNOWNEDLIB" "$SYS/$LIB/libunowned.so.1"
ln -s "$UNOWNEDLIB" "$SYS/$LIB/libunowned.so"

# A library whose package lists it in an "incoming" directory, like
# glibc does (its doinst.sh moves the files to the directory above)
INCLIB=$(mklib "$SYS/$LIB" inc 1)
ln -s "$INCLIB" "$SYS/$LIB/libinc.so.1"; ln -s "$INCLIB" "$SYS/$LIB/libinc.so"

# A library that exists only at build time, so binaries linked against
# it have a missing dependency
mkdir -p "$W/gone"
GONELIB=$(mklib "$W/gone" gone 1)
ln -s "$GONELIB" "$W/gone/libgone.so.1"; ln -s "$GONELIB" "$W/gone/libgone.so"

# Base package database. glibc owns whatever the C library resolves to
# on this system.
DB="$W/db"
mkbin "$W/probe" "$SYS/$LIB"
GLIBC_FILES=$(LANG=C ldd "$W/probe" | sed -n 's|.*=> \(/[^ ]*\) .*|\1|p' | \
	while read -r f; do readlink -e "$f"; done | sed 's|^/||')
mkrecord "$DB" glibc-2.33-x86_64-1 $GLIBC_FILES
mkrecord "$DB" bar-2.0-x86_64-1 "$(rel $LIB/$BARLIB)" usr/doc/bar-2.0/README
mkrecord "$DB" baz-1.0-x86_64-1 "$(rel $LIB/$BAZLIB)"
mkrecord "$DB" baz-solibs-1.0-x86_64-1 "$(rel $LIB/$BAZLIB)"
mkrecord "$DB" a-b-c-d-1.0-x86_64-1 "$(rel $LIB/$DASHLIB)"
mkrecord "$DB" a-b-c-d-solibs-1.0-x86_64-1 "$(rel $LIB/$DASHLIB)"
mkrecord "$DB" inc-1.0-x86_64-1 "$(rel $LIB/incoming/)" "$(rel $LIB/incoming/$INCLIB)"
# Have files whose paths contain the path of libbar, which must not
# make them providers of it
mkrecord "$DB" barbackup-1.0-x86_64-1 "$(rel $LIB/$BARLIB).bak"
mkrecord "$DB" barcopy-1.0-x86_64-1 "opt/copy/$(rel $LIB/$BARLIB)"
# Has file names containing "NOT" and "FOUND"
mkrecord "$DB" decoy-1.0-x86_64-1 usr/doc/decoy/NOTES usr/doc/decoy/FOUNDERS
# python modules installed in a python path directory. Compiled modules
# are named either module.so or module.<tag>.so, with the tag of the
# python that runs the tests (e.g. module.cpython-39-x86_64-linux-gnu.so)
PYEXT=$(python3 -c 'import importlib.machinery as m
print(m.EXTENSION_SUFFIXES[0])' 2>/dev/null)
PYEXT=${PYEXT:-.cpython-39-x86_64-linux-gnu.so}
echo "x = 1" > "$SYS/py/extmod.py"
: > "$SYS/py/cext$PYEXT"
: > "$SYS/py/oldcext.so"
echo "x = 1" > "$SYS/py/timesheet.py"
mkrecord "$DB" pyext-1.0-x86_64-1 "$(rel py/extmod.py)" \
	"$(rel py/cext$PYEXT)" "$(rel py/oldcext.so)"
mkrecord "$DB" timesheet-1.0-x86_64-1 "$(rel py/timesheet.py)"
# The pythons that run python files: python 3 (the real one that runs
# the tests) and python 2.7
PY3EXE=$(python3 -c 'import os, sys
print(os.path.realpath(sys.executable).lstrip("/"))' 2>/dev/null)
mkrecord "$DB" python3-3.9.25-x86_64-1 "${PY3EXE:-usr/bin/python3}"
mkrecord "$DB" python-2.7.18-x86_64-1 usr/bin/python2.7
# A namespace package (no __init__.py), split between two packages
mkdir -p "$SYS/py/nspkg"
echo "x = 1" > "$SYS/py/nspkg/one.py"
echo "x = 1" > "$SYS/py/nspkg/two.py"
mkrecord "$DB" nsone-1.0-x86_64-1 "$(rel py/nspkg/)" "$(rel py/nspkg/one.py)"
mkrecord "$DB" nstwo-1.0-x86_64-1 "$(rel py/nspkg/)" "$(rel py/nspkg/two.py)"
# An installed python distribution, with its metadata
mkdir -p "$SYS/py/ext_dist-1.0.dist-info" "$SYS/py/extdist"
echo "Name: ext-dist" > "$SYS/py/ext_dist-1.0.dist-info/METADATA"
: > "$SYS/py/extdist/__init__.py"
# ... and one with egg-info metadata, without a version in its name
mkdir -p "$SYS/py/plain_egg.egg-info"
echo "Name: plain-egg" > "$SYS/py/plain_egg.egg-info/PKG-INFO"
mkrecord "$DB" python-plainegg-1.0-x86_64-1 "$(rel py/plain_egg.egg-info/PKG-INFO)"
mkrecord "$DB" python-extdist-1.0-x86_64-1 \
	"$(rel py/ext_dist-1.0.dist-info/METADATA)" "$(rel py/extdist/__init__.py)"

# A library to preload, needing libbaz (found through its rpath, so that
# it loads in every program)
echo "int baz_func(void); int preload_func(void) { return baz_func(); }" \
	> "$W/src-preload.c"
gcc -shared -fPIC -o "$W/libpreload.so" "$W/src-preload.c" \
	-L"$SYS/$LIB" -Wl,-rpath,"$SYS/$LIB" -Wl,--no-as-needed -lbaz || exit 2

P="$W/pkgs"
mkdir -p "$P"

# foo: a binary needing libbar
mkbin "$W/foo/usr/bin/foo" "$SYS/$LIB" bar
mkpkg "$W/foo" "$P/foo-1.0-x86_64-1.txz"
# The same package in every format, and as a .tlz from slkbuild
mkdir -p "$P/formats" "$P/slkbuild"
for ext in tgz tbz tlz txz tbr; do
	mkpkg "$W/foo" "$P/formats/foo-1.0-x86_64-1.$ext"
done
mkpkg "$W/foo" "$P/slkbuild/foo-1.0-x86_64-1.tlz" slkbuild

# qux: needs libbaz, available from two packages
mkbin "$W/qux/usr/bin/qux" "$SYS/$LIB" baz
mkpkg "$W/qux" "$P/qux-1.0-x86_64-1.txz"

# outside: an ELF binary outside the standard directories, needing libbar
mkbin "$W/outside/opt/outside/bin/outside" "$SYS/$LIB" bar
mkbin "$W/outside/usr/bin/plain" "$SYS/$LIB"
mkpkg "$W/outside" "$P/outside-1.0-x86_64-1.txz"

# helpers: programs in usr/lib/<name> (also on 64-bit) and usr/games
mkbin "$W/helpers/usr/lib/helpers/helper" "$SYS/$LIB" bar
mkbin "$W/helpers/usr/games/game" "$SYS/$LIB" baz
mkpkg "$W/helpers" "$P/helpers-1.0-x86_64-1.txz"

# clash: has files at the top of the package with the names of
# depfinder's own working files
mkbin "$W/clash/usr/bin/clash" "$SYS/$LIB" bar
for f in pkglist.log FILES LIBS DEPS INCLUDED; do
	echo "nothing" > "$W/clash/$f"
done
mkpkg "$W/clash" "$P/clash-1.0-x86_64-1.txz"

# dashy: needs libdash
mkbin "$W/dashy/usr/bin/dashy" "$SYS/$LIB" dash
mkpkg "$W/dashy" "$P/dashy-1.0-x86_64-1.txz"

# incfoo: needs libinc
mkbin "$W/incfoo/usr/bin/incfoo" "$SYS/$LIB" inc
mkpkg "$W/incfoo" "$P/incfoo-1.0-x86_64-1.txz"

# unowned: needs libbar and libunowned, which no package provides
mkbin "$W/unowned/usr/bin/unowned" "$SYS/$LIB" bar unowned
mkpkg "$W/unowned" "$P/unowned-1.0-x86_64-1.txz"

# broken: needs a library that isn't installed anywhere
mkbin "$W/broken/usr/bin/broken" "$W/gone:$SYS/$LIB" gone bar
mkpkg "$W/broken" "$P/broken-1.0-x86_64-1.txz"

# selfy: ships its own library and a binary using it. makepkg moves the
# soname symlink into doinst.sh, so like in real packages only the real
# library file ends up in the package.
mkdir -p "$W/selfy/$LIB" "$W/selfy/usr/bin"
SELFYLIB=$(mklib "$W/selfy/$LIB" selfy 1)
# Linked against the library file directly, so that no libselfy.so
# symlink is needed in the package
echo "int selfy_func(void); int main(void) { return selfy_func(); }" > "$W/src-selfy.c"
gcc -o "$W/selfy/usr/bin/selfy" "$W/src-selfy.c" "$W/selfy/$LIB/$SELFYLIB" || exit 2
ln -s "$SELFYLIB" "$W/selfy/$LIB/libselfy.so.1"
mkpkg "$W/selfy" "$P/selfy-1.0-x86_64-1.txz"
mkpkg "$W/selfy" "$P/selfy-1.1-x86_64-1.txz"
mkdir -p "$P/package-selfy" && cp -a "$W/selfy/." "$P/package-selfy/"
mkdir -p "$P/package-selfy/install"
echo "selfy: selfy (a test package)" > "$P/package-selfy/install/slack-desc"

# A database and system root where selfy 1.0 is installed
SYS2="$W/sys2"
cp -a "$SYS" "$SYS2"
cp "$W/selfy/$LIB/$SELFYLIB" "$SYS2/$LIB/"
ln -s "$SELFYLIB" "$SYS2/$LIB/libselfy.so.1"
DB2="$W/db2"
cp -a "$DB" "$DB2"
mkrecord "$DB2" selfy-1.0-x86_64-1 "${SYS2#/}/$LIB/$SELFYLIB"
# The records of $DB point to $SYS; point the copies to $SYS2 instead
sed -i "s|^${SYS#/}/|${SYS2#/}/|" "$DB2"/*

# Spaces in paths: a package file and a packaging directory in a
# directory with a space, containing a binary and a python script with
# spaces in their names
mkbin "$W/spacey/usr/bin/foo bar" "$SYS/$LIB" bar
mkdir -p "$W/spacey/usr/share/spacey"
printf '#!/usr/bin/python3\nimport extmod\n' > "$W/spacey/usr/share/spacey/py app"
mkdir -p "$W/with space"
# (makepkg can't write to a path with a space)
mkpkg "$W/spacey" "$P/spacey-1.0-x86_64-1.txz"
cp "$P/spacey-1.0-x86_64-1.txz" "$W/with space/"
cp -a "$W/spacey" "$W/with space/package-spacey"

# pyapp: python scripts, checked with -p
mkdir -p "$W/pyapp/usr/bin" "$W/pyapp/usr/lib$SUF/python3/site-packages"
cat > "$W/pyapp/usr/bin/pyapp" <<'EOF'
#!/usr/bin/python3
import sys
import extmod
import cext
import oldcext
import inpkg
import pkgext
import missingmod
import timesheet
EOF
chmod 755 "$W/pyapp/usr/bin/pyapp"
echo "x = 1" > "$W/pyapp/usr/lib$SUF/python3/site-packages/inpkg.py"
: > "$W/pyapp/usr/lib$SUF/python3/site-packages/pkgext$PYEXT"
mkpkg "$W/pyapp" "$P/pyapp-1.0-x86_64-1.txz"

# pyapp2: imports that a line-based parser gets wrong, optional imports,
# namespace packages, python metadata and a python 2 file
PYSITE="usr/lib$SUF/python3/site-packages"
mkdir -p "$W/pyapp2/usr/share/pyapp2" "$W/pyapp2/$PYSITE/pyapp2-1.0.dist-info"
cat > "$W/pyapp2/usr/share/pyapp2/main.py" <<'PYEOF'
"""Docs mentioning
import notamodule
"""
# import notamodule2
from extmod import (one,
	two)
import helper
from . import relative
import nspkg.two
try:
	import optmissing
	import timesheet
	import json
except ImportError:
	optmissing = None
from extmod import TYPE_CHECKING
if TYPE_CHECKING:
	import typecheckonly
x = "import notamodule3"
import sys
if sys.version_info[0] == 2:
	import py2only1
elif sys.version_info < (3, 0):
	import py2only2
else:
	import extmod
if sys.hexversion < 0x03000000 or not PY3:
	import py2only3
if six.PY2:
	import py2only4
if sys.version_info[:2] >= (3, 0) and PY3:
	pass
else:
	import py2only5
PYEOF
# a module next to the script, which imports optionally a module that
# main.py needs, so it is needed anyway
printf 'try:\n\timport extmod\nexcept ImportError:\n\tpass\n' \
	> "$W/pyapp2/usr/share/pyapp2/helper.py"
printf 'print "python 2"\n' > "$W/pyapp2/usr/share/pyapp2/old.py"
# tests shipped in the package, which need modules that are installed
# (timesheet) or not (testonly), but aren't dependencies
mkdir -p "$W/pyapp2/$PYSITE/pyapp2/tests"
for f in tests/test_main.py tests/helpers.py conftest.py test_it.py it_test.py; do
	printf 'import timesheet\nimport testonly\n' > "$W/pyapp2/$PYSITE/pyapp2/$f"
done
# examples in the documentation, which need a module that isn't
# installed, but isn't a dependency
mkdir -p "$W/pyapp2/usr/doc/pyapp2-1.0/examples" "$W/pyapp2/usr/share/doc/pyapp2"
echo "import docmod" > "$W/pyapp2/usr/doc/pyapp2-1.0/examples/demo.py"
echo "import docmod" > "$W/pyapp2/usr/share/doc/pyapp2/demo.py"
# files for python 2.7, with their metadata
mkdir -p "$W/pyapp2/usr/lib/python2.7/site-packages/pyapp2" \
	"$W/pyapp2/usr/lib/python2.7/site-packages/pyapp2-1.0.dist-info"
for f in __init__.py two.py; do
	printf 'import StringIO\n' > "$W/pyapp2/usr/lib/python2.7/site-packages/pyapp2/$f"
done
# scripts run with python 2 by their #! line (/usr/bin/python is python
# 2), or with python 3
mkdir -p "$W/pyapp2/usr/bin"
printf '#!/usr/bin/python\nimport StringIO\nprint "x"\n' > "$W/pyapp2/usr/bin/old1"
printf '#! /usr/bin/env python2\nimport StringIO\n' > "$W/pyapp2/usr/bin/old2"
printf '#!/usr/bin/env python2.7\nimport StringIO\n' > "$W/pyapp2/usr/bin/old3"
printf '#!/usr/bin/env -S python3 -u\nimport extmod\n' > "$W/pyapp2/usr/bin/new"
# a virtualenv's python, which could be any version
printf '#!/opt/venv/bin/python\nimport timesheet\n' > "$W/pyapp2/usr/bin/venv"
# a python 3 module with an old "#!/usr/bin/env python" line, which
# doesn't count
printf '#!/usr/bin/env python\nimport nspkg.one\n' > "$W/pyapp2/$PYSITE/pyapp2/shebang.py"
chmod 755 "$W/pyapp2/usr/bin/"*
printf 'Name: pyapp2\nRequires-Dist: py2dist\n' \
	> "$W/pyapp2/usr/lib/python2.7/site-packages/pyapp2-1.0.dist-info/METADATA"
cat > "$W/pyapp2/$PYSITE/pyapp2-1.0.dist-info/METADATA" <<'PYEOF'
Metadata-Version: 2.1
Name: pyapp2
Version: 1.0
Requires-Dist: Ext.Dist (>=1.0)
Requires-Dist: missingdist
Requires-Dist: extradist ; extra == "docs"
Requires-Dist: py2only ; python_version < "3"
Requires-Dist: pyapp2

Requires-Dist: in-the-description
PYEOF
mkpkg "$W/pyapp2" "$P/pyapp2-1.0-x86_64-1.txz"

# pyfall: fallback imports, in except ImportError blocks
mkdir -p "$W/pyfall/usr/share/pyfall"
cat > "$W/pyfall/usr/share/pyfall/main.py" <<'PYEOF'
try:
	import extmod
except ImportError:
	import py2fallback	# not needed, extmod is there
try:
	import newmissing
except ImportError:
	import timesheet	# needed, newmissing isn't there
try:
	import newmissing2
except ImportError:
	try:
		import extmod
	except ImportError:
		import deepfallback	# not needed, extmod is there
try:
	import extmod
except AttributeError:
	import notfallback	# not a fallback for a failed import
PYEOF
mkpkg "$W/pyfall" "$P/pyfall-1.0-x86_64-1.txz"

# pyplat: code and modules for other platforms (python's standard
# library is left out, since the fake package database doesn't have it)
mkdir -p "$W/pyplat/usr/share/pyplat"
cat > "$W/pyplat/usr/share/pyplat/main.py" <<'PYEOF'
if sys.platform == "win32":
	import winonly
elif sys.platform.startswith("darwin"):
	import maconly
else:
	import extmod
if os.name == "nt":
	import winonly2
if platform.system() == "Windows":
	import winonly3
import msvcrt
try:
	import winreg
except ImportError:
	import timesheet	# needed, winreg is never there
PYEOF
mkpkg "$W/pyplat" "$P/pyplat-1.0-x86_64-1.txz"

# pyshadow: modules inside a package named like installed modules,
# which don't hide them
mkdir -p "$W/pyshadow/$PYSITE/shadow"
: > "$W/pyshadow/$PYSITE/shadow/__init__.py"
echo "import timesheet" > "$W/pyshadow/$PYSITE/shadow/timesheet.py"
echo "import extmod" > "$W/pyshadow/$PYSITE/shadow/api.py"
: > "$W/pyshadow/$PYSITE/shadow/extmod.py"
mkpkg "$W/pyshadow" "$P/pyshadow-1.0-x86_64-1.txz"

# pyns: a module imported from a namespace package split between
# packages, and a name from a module
mkdir -p "$W/pyns/usr/share/pyns"
printf 'from nspkg import two\nfrom extmod import one, two\n' \
	> "$W/pyns/usr/share/pyns/main.py"
mkpkg "$W/pyns" "$P/pyns-1.0-x86_64-1.txz"

# pysys: a python 3 script that imports only a builtin module, and
# pyold: a python 2 script
mkdir -p "$W/pysys/usr/bin" "$W/pyold/usr/bin"
printf '#!/usr/bin/python3\nimport sys\n' > "$W/pysys/usr/bin/pysys"
printf '#!/usr/bin/python\nimport StringIO\n' > "$W/pyold/usr/bin/pyold"
chmod 755 "$W/pysys/usr/bin/pysys" "$W/pyold/usr/bin/pyold"
mkpkg "$W/pysys" "$P/pysys-1.0-x86_64-1.txz"
mkpkg "$W/pyold" "$P/pyold-1.0-x86_64-1.txz"

# pygen: generated code, nested deeper than python's recursion limit
mkdir -p "$W/pygen/usr/share/pygen"
{
	echo "import extmod"
	printf 'x = "a"'
	for i in $(seq 3000); do printf ' + "a"'; done
	echo
	echo "try:"
	echo "	import optgen"
	echo "except ImportError:"
	echo "	pass"
} > "$W/pygen/usr/share/pygen/gen.py"
mkpkg "$W/pygen" "$P/pygen-1.0-x86_64-1.txz"

# eggy: egg-info metadata without a version in its name, requiring
# itself, an installed distribution, and others only for extras or for
# python 2
mkdir -p "$W/eggy/$PYSITE/eggy.egg-info"
printf '%s\n' eggy Plain.Egg '[docs]' sphinxthing \
	"[:python_version < '3']" py2thing > "$W/eggy/$PYSITE/eggy.egg-info/requires.txt"
mkpkg "$W/eggy" "$P/eggy-1.0-x86_64-1.txz"

#
# Test helpers
#

# rundf <db> <sysroot> <args>...: runs depfinder in a fresh directory
# against the given database, with the given system root's libraries
# and python modules visible. Sets OUT (stdout), ERR (stderr), RC and
# RUNDIR (the directory it ran in, for files created with -f).
rundf()
{
	local db=$1 sys=$2; shift 2
	# (a directory with a space, to check that -f handles that)
	RUNDIR=$(mktemp -d "$W/run dir.XXXXXX")
	OUT=$(cd "$RUNDIR" && DEPFINDERPKGDB="$db" \
		LD_LIBRARY_PATH="$sys/$LIB" DEPFINDERPYTHONPATH="$sys/py" \
		"$DF" "$@" 2>"$RUNDIR/.stderr")
	RC=$?
	ERR=$(cat "$RUNDIR/.stderr"); rm -f "$RUNDIR/.stderr"
}

# check <name> <expected> <actual> [xfail]
check()
{
	local name=$1 expected=$2 actual=$3 xfail=$4
	if [ "$expected" == "$actual" ]; then
		if [ -n "$xfail" ]; then
			echo "XPASS: $name (known bug fixed? remove the xfail marker)"
			XPASS=$((XPASS+1))
		else
			echo "PASS:  $name"
			PASS=$((PASS+1))
		fi
	else
		if [ -n "$xfail" ]; then
			echo "XFAIL: $name"
			XFAIL=$((XFAIL+1))
		else
			echo "FAIL:  $name"
			FAIL=$((FAIL+1))
		fi
		if [ $VERBOSE -eq 1 ] || [ -z "$xfail" ]; then
			echo "       expected: $(printf '%s' "$expected" | sed -n l | tr '\n' ' ')"
			echo "       actual:   $(printf '%s' "$actual" | sed -n l | tr '\n' ' ')"
			[ -n "$ERR" ] && echo "       stderr:   $ERR"
		fi
	fi
}

skip()
{
	echo "SKIP:  $1"
	SKIP=$((SKIP+1))
}

#
# The tests
#

# Basic dependency detection
rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "txz package" "bar,glibc" "$OUT"
check "exit status 0" "0" "$RC"

rundf "$DB" "$SYS" -s "$P/foo-1.0-x86_64-1.txz"
check "-s adds version information" \
	"$(printf 'bar >= 2.0-x86_64-1\nglibc >= 2.33-x86_64-1')" "$OUT"

rundf "$DB" "$SYS" -j4 "$P/foo-1.0-x86_64-1.txz"
check "-j4 gives the same result" "bar,glibc" "$OUT"
rundf "$DB" "$SYS" -j 08 "$P/foo-1.0-x86_64-1.txz"
check "-j with a leading zero" "bar,glibc" "$OUT"
rundf "$DB" "$SYS" -j 200 "$P/foo-1.0-x86_64-1.txz"
check "-j 200" "bar,glibc" "$OUT"
check "-j 200: no errors" "" "$ERR"
rundf "$DB" "$SYS" -j 0 "$P/foo-1.0-x86_64-1.txz"
check "-j 0: exit status 1" "1" "$RC"
check "-j 0: reported" "1" "$(echo "$ERR" | grep -c "at least 1")"
rundf "$DB" "$SYS" -j abc "$P/foo-1.0-x86_64-1.txz"
check "-j abc: exit status 1" "1" "$RC"
check "-j abc: reported" "1" "$(echo "$ERR" | grep -c "needs a number")"

for ext in tgz tbz tlz txz tbr; do
	pkg="$P/formats/foo-1.0-x86_64-1.$ext"
	name="$ext package"
	[ $ext = tbr ] && name="tbr package (as made by slkbuild)"
	if [ -s "$pkg" ]; then
		rundf "$DB" "$SYS" "$pkg"
		check "$name" "bar,glibc" "$OUT"
	else
		skip "$name (compression tool not installed)"
	fi
done
if [ -s "$P/slkbuild/foo-1.0-x86_64-1.tlz" ]; then
	rundf "$DB" "$SYS" "$P/slkbuild/foo-1.0-x86_64-1.tlz"
	check "tlz package (as made by slkbuild)" "bar,glibc" "$OUT"
else
	skip "tlz package (as made by slkbuild) (slkbuild not installed)"
fi

# Preloaded libraries aren't dependencies of the package
LD_PRELOAD="$W/libpreload.so" rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "LD_PRELOAD is ignored" "bar,glibc" "$OUT"

# A library provided by more than one package
rundf "$DB" "$SYS" "$P/qux-1.0-x86_64-1.txz"
check "either-of dependency" "baz|baz-solibs,glibc" "$OUT"

# Package names with several "-" in them
rundf "$DB" "$SYS" "$P/dashy-1.0-x86_64-1.txz"
check "package names with several -" "a-b-c-d|a-b-c-d-solibs,glibc" "$OUT"
rundf "$DB" "$SYS" -s "$P/dashy-1.0-x86_64-1.txz"
check "package names with several -, -s" \
	"$(printf 'a-b-c-d >= 1.0-x86_64-1|a-b-c-d-solibs >= 1.0-x86_64-1\nglibc >= 2.33-x86_64-1')" \
	"$OUT"

# Output files
rundf "$DB" "$SYS" -f "$P/foo-1.0-x86_64-1.txz"
check "-f prints nothing" "" "$OUT"
check "-f writes a .dep file" "bar,glibc" \
	"$(cat "$RUNDIR/foo-1.0-x86_64-1.dep" 2>&1)"

# Only the extension at the end of the name is removed
cp "$P/foo-1.0-x86_64-1.txz" "$P/foo.tbz2-1.0-x86_64-1.txz"
rundf "$DB" "$SYS" -f "$P/foo.tbz2-1.0-x86_64-1.txz"
check "-f with an extension-like part in the name" "bar,glibc" \
	"$(cat "$RUNDIR/foo.tbz2-1.0-x86_64-1.dep" 2>&1)"
echo "x" > "$W/foo-1.0-x86_64-1.tbrx"
rundf "$DB" "$SYS" "$W/foo-1.0-x86_64-1.tbrx"
check "unknown extension: reported" "1" \
	"$(echo "$ERR" | grep -c "is not a package file")"

rundf "$DB" "$SYS" -f -s "$P/foo-1.0-x86_64-1.txz"
check "-f -s writes slack-required" \
	"$(printf 'bar >= 2.0-x86_64-1\nglibc >= 2.33-x86_64-1')" \
	"$(cat "$RUNDIR/slack-required" 2>&1)"

# -a
rundf "$DB" "$SYS" "$P/outside-1.0-x86_64-1.txz"
check "ELF files outside standard dirs are ignored" "glibc" "$OUT"
rundf "$DB" "$SYS" -a "$P/outside-1.0-x86_64-1.txz"
check "-a checks all files" "bar,glibc" "$OUT"
rundf "$DB" "$SYS" "$P/helpers-1.0-x86_64-1.txz"
check "programs in usr/lib/<name> and usr/games" \
	"bar,baz|baz-solibs,glibc" "$OUT"

# Missing libraries
rundf "$DB" "$SYS" "$P/broken-1.0-x86_64-1.txz"
check "missing library: exit status 1" "1" "$RC"
check "missing library: no dependency list" "" "$OUT"
check "missing library: reported" "1" \
	"$(echo "$ERR" | grep -c "libgone\.so\.1")"

# The working directory
rundf "$DB" "$SYS" "$P/clash-1.0-x86_64-1.txz"
check "package files named like depfinder's working files" "bar,glibc" "$OUT"
mkdir "$W/tmp"
TMPDIR="$W/tmp" rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "TMPDIR is used and cleaned up" "bar,glibc:" "$OUT:$(ls "$W/tmp")"
TMPDIR="$W/tmp" DEPFINDERDEBUG=1 rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "DEPFINDERDEBUG=1 keeps the working directory" "1" \
	"$(ls "$W/tmp" | grep -c "^depfinder\.")"
rm -rf "$W/tmp"
mkdir "$W/tmp"
# (DEBUG is used by other programs, e.g. DEBUG='*' for node's debug)
TMPDIR="$W/tmp" DEBUG=1 rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "DEBUG is ignored" "bar,glibc::" "$OUT:$ERR:$(ls "$W/tmp")"
TMPDIR="$W/tmp" DEPFINDERDEBUG='*' rundf "$DB" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "DEPFINDERDEBUG other than 1 is ignored" "bar,glibc::" \
	"$OUT:$ERR:$(ls "$W/tmp")"
rm -rf "$W/tmp"

# Killed while depfinder-search runs: the working directory is removed.
# (A depfinder-search that only signals that it started and waits.)
mkdir "$W/tmp"
printf '#!/bin/sh\ntouch "%s"\nsleep 5\n' "$W/started" > "$W/slow-search"
chmod 755 "$W/slow-search"
sed "s|^DEPFINDERSEARCH=.*|DEPFINDERSEARCH=\"$W/slow-search\"|" "$DF" > "$W/df-slow"
chmod 755 "$W/df-slow"
TMPDIR="$W/tmp" DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$W/df-slow" "$P/foo-1.0-x86_64-1.txz" > /dev/null 2>&1 &
pid=$!
for i in $(seq 50); do [ -e "$W/started" ] && break; sleep 0.1; done
kill -TERM $pid
wait $pid
RC=$?; ERR=""
check "killed: exit status 143" "143" "$RC"
check "killed: working directory removed" "" "$(ls "$W/tmp")"
rm -rf "$W/tmp"

# A library listed in an "incoming" directory in its package record
rundf "$DB" "$SYS" "$P/incfoo-1.0-x86_64-1.txz"
check "library in an incoming directory" "glibc,inc" "$OUT"
check "library in an incoming directory: no warning" "" "$ERR"

# Libraries that no package provides
rundf "$DB" "$SYS" "$P/unowned-1.0-x86_64-1.txz"
check "unowned library: other deps listed" "bar,glibc" "$OUT"
check "unowned library: exit status 0" "0" "$RC"
check "unowned library: warning" \
	"WARNING: no installed package provides $SYS/$LIB/libunowned.so.1" "$ERR"

DEPFINDERNOEXIT=1 rundf "$DB" "$SYS" "$P/broken-1.0-x86_64-1.txz"
check "DEPFINDERNOEXIT=1: lists the deps that were found" "bar,glibc" "$OUT"

# A package shipping its own library
rundf "$DB" "$SYS" "$P/selfy-1.0-x86_64-1.txz"
check "own library, package not installed" "glibc" "$OUT"
# (in a locale whose readelf output is translated)
FRLOCALE=$(locale -a 2>/dev/null | grep -i -m 1 '^fr_FR\.utf-\?8$')
if [ -n "$FRLOCALE" ]; then
	LC_ALL=$FRLOCALE rundf "$DB" "$SYS" "$P/selfy-1.0-x86_64-1.txz"
	check "own library, package not installed, LC_ALL=$FRLOCALE" "glibc" "$OUT"
else
	skip "own library in a translated locale (no fr_FR.utf8 locale)"
fi

rundf "$DB2" "$SYS2" "$P/selfy-1.0-x86_64-1.txz"
check "own library, same version installed" "glibc" "$OUT"

rundf "$DB2" "$SYS2" -s "$P/selfy-1.0-x86_64-1.txz"
check "own library, same version installed, -s" \
	"glibc >= 2.33-x86_64-1" "$OUT"

rundf "$DB2" "$SYS2" "$P/selfy-1.1-x86_64-1.txz"
check "own library, older version installed" "glibc" "$OUT"

rundf "$DB2" "$SYS2" "$P/package-selfy"
check "own library, packaging directory" "glibc" "$OUT"
rundf "$DB2" "$SYS2" -f "$P/package-selfy"
check "-f on a directory: .dep named from slack-desc" "glibc" \
	"$(cat "$RUNDIR/selfy.dep" 2>&1)"

# Python dependencies
if command -v python3 >/dev/null; then
	rundf "$DB" "$SYS" -p "$P/pyapp-1.0-x86_64-1.txz"
	check "-p finds installed python modules" "pyext" \
		"$(echo "$OUT" | tr ',' '\n' | grep -x pyext)"
	# Only missingmod is really missing: the others are either in the
	# package or installed, including compiled (.so) modules
	check "-p warns only about missing modules" \
		"WARNING: python module missingmod not found." "$ERR"
	check "-p: modules containing a builtin module name" \
		"pyext,python3,timesheet" "$OUT"
	rundf "$DB" "$SYS" "$P/pyapp-1.0-x86_64-1.txz"
	check "without -p python is ignored" "" "$OUT"

	rundf "$DB" "$SYS" -p "$P/pyapp2-1.0-x86_64-1.txz"
	# (timesheet is installed, but only imported optionally, and json,
	# from python's standard library, isn't listed as optional)
	check "-p: imports, namespace packages, metadata and the pythons" \
		"nsone,nstwo,pyext,python,python-extdist,python3,timesheet" "$OUT"
	check "-p: warnings" "$(printf '%s\n' \
		"WARNING: could not parse usr/share/pyapp2/old.py as python 3." \
		"WARNING: not checking 2 python files, which are for python 2." \
		"WARNING: not checking 3 python files, which are for python 2.7." \
		"NOTE: optional python modules, not added as dependencies: optmissing" \
		"WARNING: not checking the requirements of pyapp2, which is for python 2.7." \
		"WARNING: python package missingdist, required by pyapp2, not found.")" \
		"$ERR"

	rundf "$DB" "$SYS" -p "$P/pyfall-1.0-x86_64-1.txz"
	check "-p: fallback imports" "pyext,python3,timesheet" "$OUT"
	check "-p: fallback imports: messages" "$(printf '%s\n' \
		"WARNING: python module notfallback not found." \
		"NOTE: optional python modules, not added as dependencies: newmissing, newmissing2")" \
		"$ERR"

	rundf "$DB" "$SYS" -p "$P/pyplat-1.0-x86_64-1.txz"
	check "-p: other platforms" "pyext,python3,timesheet" "$OUT"
	check "-p: other platforms: no warnings" "" "$ERR"

	rundf "$DB" "$SYS" -p "$P/pyshadow-1.0-x86_64-1.txz"
	check "-p: modules inside a package don't hide installed ones" \
		"pyext,python3,timesheet" "$OUT"

	rundf "$DB" "$SYS" -p "$P/pyns-1.0-x86_64-1.txz"
	check "-p: from a namespace package import a module" "nstwo,pyext,python3" "$OUT"
	check "-p: from a namespace package import a module: no warnings" \
		"" "$ERR"

	rundf "$DB" "$SYS" -p "$P/pysys-1.0-x86_64-1.txz"
	check "-p: python 3 scripts need python 3" "python3" "$OUT"
	rundf "$DB" "$SYS" -p "$P/pyold-1.0-x86_64-1.txz"
	check "-p: python 2 scripts need python 2.7" "python" "$OUT"
	check "-p: python 2 scripts need python 2.7: messages" \
		"WARNING: not checking 1 python file, which is for python 2." "$ERR"

	rundf "$DB" "$SYS" -p "$P/pygen-1.0-x86_64-1.txz"
	check "-p: deeply nested code" "pyext,python3" "$OUT"
	check "-p: deeply nested code: messages" \
		"NOTE: optional python modules, not added as dependencies: optgen" "$ERR"

	rundf "$DB" "$SYS" -p "$P/eggy-1.0-x86_64-1.txz"
	check "-p: egg-info metadata" "python-plainegg" "$OUT"
	check "-p: egg-info metadata: no warnings" "" "$ERR"
	# (in a packaging directory that is itself in a directory named
	# like one for another python version)
	mkdir -p "$W/python3.1"
	cp -a "$W/eggy" "$W/python3.1/"
	rundf "$DB" "$SYS" -p "$W/python3.1/eggy"
	check "-p: metadata in a directory inside python3.1/" \
		"python-plainegg" "$OUT"
	check "-p: metadata in a directory inside python3.1/: no warnings" \
		"" "$ERR"

	# Files that can't be read (a packaging directory owned by someone
	# else; root can read anything)
	if [ "$(id -u)" -ne 0 ]; then
		mkdir -p "$W/package-unread/usr/share/unread" \
			"$W/package-unread/$PYSITE/unread-1.0.dist-info"
		echo "import extmod" > "$W/package-unread/usr/share/unread/ok.py"
		echo "import timesheet" > "$W/package-unread/usr/share/unread/secret.py"
		echo "Requires-Dist: missingdist" \
			> "$W/package-unread/$PYSITE/unread-1.0.dist-info/METADATA"
		chmod 000 "$W/package-unread/usr/share/unread/secret.py" \
			"$W/package-unread/$PYSITE/unread-1.0.dist-info/METADATA"
		rundf "$DB" "$SYS" -p "$W/package-unread"
		check "-p: unreadable files are skipped" "pyext,python3" "$OUT"
		check "-p: unreadable files are reported" "$(printf '%s\n' \
			"WARNING: could not read usr/share/unread/secret.py." \
			"WARNING: could not read $PYSITE/unread-1.0.dist-info/METADATA.")" \
			"$ERR"
	else
		skip "-p: unreadable files (running as root)"
	fi

	# Modules installed in the user's home are not used
	mkdir -p "$W/home"
	USERSITE=$(HOME="$W/home" python3 -c \
		'import site; print(site.getusersitepackages())')
	case "$USERSITE" in
		"$W/home/"*)
			mkdir -p "$USERSITE"
			echo "x = 1" > "$USERSITE/missingmod.py"
			HOME="$W/home" rundf "$DB" "$SYS" -p "$P/pyapp-1.0-x86_64-1.txz"
			check "-p: modules in the user's home are ignored" \
				"WARNING: python module missingmod not found." "$ERR"
			;;
		*)
			skip "-p: modules in the user's home (no user site directory)"
			;;
	esac
	# ... and neither are the ones in PYTHONPATH
	mkdir -p "$W/pythonpath"
	echo "x = 1" > "$W/pythonpath/missingmod.py"
	PYTHONPATH="$W/pythonpath" rundf "$DB" "$SYS" -p "$P/pyapp-1.0-x86_64-1.txz"
	check "-p: modules in PYTHONPATH are ignored" \
		"WARNING: python module missingmod not found." "$ERR"

	# Without python3 (a PATH with everything else)
	mkdir -p "$W/nopython"
	for f in /usr/bin/* /bin/*; do
		case "${f##*/}" in python*) continue ;; esac
		[ -e "$W/nopython/${f##*/}" ] || ln -s "$f" "$W/nopython/"
	done
	PATH="$W/nopython" rundf "$DB" "$SYS" -p "$P/pyapp-1.0-x86_64-1.txz"
	check "-p without python3: exit status 1" "1" "$RC"
	check "-p without python3: reported" "1" \
		"$(echo "$ERR" | grep -c "python3 is needed")"
else
	skip "python tests (python3 not installed)"
fi

# Spaces in paths
rundf "$DB" "$SYS" "$W/with space/spacey-1.0-x86_64-1.txz"
check "spaces: package file" "bar,glibc" "$OUT"
rundf "$DB" "$SYS" "$W/with space/package-spacey"
check "spaces: packaging directory" "bar,glibc" "$OUT"
if command -v python3 >/dev/null; then
	rundf "$DB" "$SYS" -p "$W/with space/spacey-1.0-x86_64-1.txz"
	check "spaces: python script" "bar,glibc,pyext,python3" "$OUT"
fi
rundf "$DB" "$SYS" -f "$W/with space/spacey-1.0-x86_64-1.txz"
check "spaces: -f writes a .dep file" "bar,glibc" \
	"$(cat "$RUNDIR/spacey-1.0-x86_64-1.dep" 2>&1)"
rundf "$DB" "$SYS" -f "$W/with space/package-spacey"
check "spaces: -f on a directory without slack-desc" "bar,glibc" \
	"$(cat "$RUNDIR/package-spacey.dep" 2>&1)"
# (given as ".", from inside it)
( cd "$W/with space/package-spacey" && DEPFINDERPKGDB="$DB" \
	LD_LIBRARY_PATH="$SYS/$LIB" "$DF" -f . 2>/dev/null )
check "-f on . is named after the directory" "bar,glibc" \
	"$(cat "$W/with space/package-spacey/package-spacey.dep" 2>&1)"
rm -f "$W/with space/package-spacey/"*.dep
rundf "$DB" "$SYS" -f -s "$W/with space/spacey-1.0-x86_64-1.txz"
check "spaces: -f -s writes slack-required" \
	"$(printf 'bar >= 2.0-x86_64-1\nglibc >= 2.33-x86_64-1')" \
	"$(cat "$RUNDIR/slack-required" 2>&1)"

# -f in a directory that can't be written to (root can write anywhere)
if [ "$(id -u)" -ne 0 ]; then
	mkdir "$W/readonly"
	chmod 555 "$W/readonly"
	for opt in -f "-f -s"; do
		OUT=$(cd "$W/readonly" && DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
			"$DF" $opt "$P/foo-1.0-x86_64-1.txz" 2>&1)
		RC=$?; ERR=""
		check "$opt in a read-only directory: exit status 1" "1" "$RC"
		check "$opt in a read-only directory: reported" "1" \
			"$(echo "$OUT" | grep -c "ERROR: could not write")"
	done
	chmod 755 "$W/readonly"
else
	skip "-f in a read-only directory (running as root)"
fi

# A package path starting with "-" (given after "--")
mkdir "$W/dash"
cp "$P/foo-1.0-x86_64-1.txz" "$W/dash/-foo-1.0-x86_64-1.txz"
OUT=$(cd "$W/dash" && DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$DF" -- -foo-1.0-x86_64-1.txz 2>&1)
ERR=""
check "package path starting with -" "bar,glibc" "$OUT"
OUT=$(cd "$W/dash" && DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$DF" -f -- -foo-1.0-x86_64-1.txz 2>&1)
check "package path starting with -, -f" "bar,glibc" \
	"$(cat "$W/dash/-foo-1.0-x86_64-1.dep" 2>&1)"

# Options and errors
rundf "$DB" "$SYS" "$P/does-not-exist.txz"
check "missing package: exit status 1" "1" "$RC"
rundf "$DB" "$SYS" "$W/src-main.c"
check "not a package: exit status 1" "1" "$RC"
echo "garbage" > "$W/corrupt-1.0-x86_64-1.txz"
rundf "$DB" "$SYS" "$W/corrupt-1.0-x86_64-1.txz"
check "package that can't be extracted: exit status 1" "1" "$RC"
check "package that can't be extracted: reported" "1" \
	"$(echo "$ERR" | grep -c "could not extract")"
rundf "$W/no-such-db" "$SYS" "$P/foo-1.0-x86_64-1.txz"
check "missing package database: exit status 1" "1" "$RC"
check "missing package database: reported" "1" \
	"$(echo "$ERR" | grep -c "package database")"
# depfinder-search and depfinder-python in a directory with a space
mkdir -p "$W/lib exec"
cp "$SEARCH" "$TOPDIR/depfinder-python" "$W/lib exec/"
sed -e "s|^DEPFINDERSEARCH=.*|DEPFINDERSEARCH=\"$W/lib exec/depfinder-search\"|" \
    -e "s|^DEPFINDERPYTHON=.*|DEPFINDERPYTHON=\"$W/lib exec/depfinder-python\"|" \
	"$DF" > "$W/df-space"
chmod 755 "$W/df-space"
OUT=$(DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" DEPFINDERPYTHONPATH="$SYS/py" \
	"$W/df-space" -p "$W/with space/spacey-1.0-x86_64-1.txz" 2>&1)
ERR=""
check "helpers in a directory with a space" "bar,glibc,pyext,python3" "$OUT"

# depfinder-search missing, or failing
sed "s|^DEPFINDERSEARCH=.*|DEPFINDERSEARCH=\"$W/no-such-search\"|" "$DF" > "$W/df-nosearch"
printf '#!/bin/sh\nexit 1\n' > "$W/failing-search"
chmod 755 "$W/failing-search"
sed "s|^DEPFINDERSEARCH=.*|DEPFINDERSEARCH=\"$W/failing-search\"|" "$DF" > "$W/df-failsearch"
chmod 755 "$W/df-nosearch" "$W/df-failsearch"
OUT=$(DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$W/df-nosearch" "$P/foo-1.0-x86_64-1.txz" 2>&1)
RC=$?; ERR=""
check "depfinder-search missing: exit status 1" "1" "$RC"
check "depfinder-search missing: reported" "1" "$(echo "$OUT" | grep -c "no-such-search not found")"
OUT=$(DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$W/df-failsearch" "$P/foo-1.0-x86_64-1.txz" 2>&1)
RC=$?
check "depfinder-search failing: exit status 1" "1" "$RC"
check "depfinder-search failing: reported" "1" "$(echo "$OUT" | grep -c "could not look up")"

# depfinder-python missing (only needed with -p)
sed "s|^DEPFINDERPYTHON=.*|DEPFINDERPYTHON=\"$W/no-such-python\"|" "$DF" > "$W/df-nopython"
chmod 755 "$W/df-nopython"
if command -v python3 > /dev/null; then
	OUT=$(DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
		"$W/df-nopython" -p "$P/foo-1.0-x86_64-1.txz" 2>&1)
	RC=$?; ERR=""
	check "depfinder-python missing: exit status 1" "1" "$RC"
	check "depfinder-python missing: reported" "1" \
		"$(echo "$OUT" | grep -c "no-such-python not found")"
else
	skip "depfinder-python missing (no python3)"
fi
OUT=$(DEPFINDERPKGDB="$DB" LD_LIBRARY_PATH="$SYS/$LIB" \
	"$W/df-nopython" "$P/foo-1.0-x86_64-1.txz" 2>/dev/null)
check "depfinder-python missing: not needed without -p" "bar,glibc" "$OUT"

rundf "$DB" "$SYS" -3 -p "$P/foo-1.0-x86_64-1.txz"
check "-3 is not an option any more" "1" "$RC"
rundf "$DB" "$SYS" -v
check "-v exit status" "0" "$RC"
check "-v shows the version" "1" "$(echo "$OUT" | grep -c "depfinder version")"
rundf "$DB" "$SYS" -h
check "-h exit status" "0" "$RC"
check "-h shows the usage" "1" "$(echo "$OUT" | grep -c "^usage:")"
rundf "$DB" "$SYS" -x "$P/foo-1.0-x86_64-1.txz"
check "unknown option: exit status 1" "1" "$RC"
check "unknown option: reported" "ERROR: unknown option -x" "$ERR"
rundf "$DB" "$SYS" -j
check "-j without a number: exit status 1" "1" "$RC"
check "-j without a number: reported" "ERROR: -j needs a number of jobs" "$ERR"
rundf "$DB" "$SYS" -p
check "options without a package: exit status 1" "1" "$RC"
check "options without a package: reported" \
	"ERROR: No package or packaging directory given" "$ERR"

echo
echo "$PASS passed, $FAIL failed, $XFAIL expected failures," \
	"$XPASS unexpected passes, $SKIP skipped"
[ $FAIL -eq 0 ] && [ $XPASS -eq 0 ]
