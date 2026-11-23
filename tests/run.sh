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
# Have files whose paths contain the path of libbar, which must not
# make them providers of it
mkrecord "$DB" barbackup-1.0-x86_64-1 "$(rel $LIB/$BARLIB).bak"
mkrecord "$DB" barcopy-1.0-x86_64-1 "opt/copy/$(rel $LIB/$BARLIB)"
# Has file names containing "NOT" and "FOUND"
mkrecord "$DB" decoy-1.0-x86_64-1 usr/doc/decoy/NOTES usr/doc/decoy/FOUNDERS
# python modules installed in a python path directory
echo "x = 1" > "$SYS/py/extmod.py"
: > "$SYS/py/cext.cpython-39-x86_64-linux-gnu.so"
: > "$SYS/py/oldcext.so"
echo "x = 1" > "$SYS/py/timesheet.py"
mkrecord "$DB" pyext-1.0-x86_64-1 "$(rel py/extmod.py)" \
	"$(rel py/cext.cpython-39-x86_64-linux-gnu.so)" "$(rel py/oldcext.so)"
mkrecord "$DB" timesheet-1.0-x86_64-1 "$(rel py/timesheet.py)"

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
: > "$W/pyapp/usr/lib$SUF/python3/site-packages/pkgext.cpython-39-x86_64-linux-gnu.so"
mkpkg "$W/pyapp" "$P/pyapp-1.0-x86_64-1.txz"

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
		LD_LIBRARY_PATH="$sys/$LIB" PYTHONPATH="$sys/py" \
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

# Missing libraries
rundf "$DB" "$SYS" "$P/broken-1.0-x86_64-1.txz"
check "missing library: exit status 1" "1" "$RC"
check "missing library: no dependency list" "" "$OUT"
check "missing library: reported" "1" \
	"$(echo "$ERR" | grep -c "libgone\.so\.1")"

DEPFINDERNOEXIT=1 rundf "$DB" "$SYS" "$P/broken-1.0-x86_64-1.txz"
check "DEPFINDERNOEXIT=1: lists the deps that were found" "bar,glibc" "$OUT"

# A package shipping its own library
rundf "$DB" "$SYS" "$P/selfy-1.0-x86_64-1.txz"
check "own library, package not installed" "glibc" "$OUT"

rundf "$DB2" "$SYS2" "$P/selfy-1.0-x86_64-1.txz"
check "own library, same version installed" "glibc" "$OUT"

rundf "$DB2" "$SYS2" -s "$P/selfy-1.0-x86_64-1.txz"
check "own library, same version installed, -s" \
	"glibc >= 2.33-x86_64-1" "$OUT"

rundf "$DB2" "$SYS2" "$P/selfy-1.1-x86_64-1.txz"
check "own library, older version installed" "glibc" "$OUT"

rundf "$DB2" "$SYS2" "$P/package-selfy"
check "own library, packaging directory" "glibc" "$OUT"

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
		"pyext,timesheet" "$OUT"
	rundf "$DB" "$SYS" "$P/pyapp-1.0-x86_64-1.txz"
	check "without -p python is ignored" "" "$OUT"
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
	check "spaces: python script" "bar,glibc,pyext" "$OUT"
fi
rundf "$DB" "$SYS" -f "$W/with space/spacey-1.0-x86_64-1.txz"
check "spaces: -f writes a .dep file" "bar,glibc" \
	"$(cat "$RUNDIR/spacey-1.0-x86_64-1.dep" 2>&1)"
rundf "$DB" "$SYS" -f -s "$W/with space/spacey-1.0-x86_64-1.txz"
check "spaces: -f -s writes slack-required" \
	"$(printf 'bar >= 2.0-x86_64-1\nglibc >= 2.33-x86_64-1')" \
	"$(cat "$RUNDIR/slack-required" 2>&1)"

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

echo
echo "$PASS passed, $FAIL failed, $XFAIL expected failures," \
	"$XPASS unexpected passes, $SKIP skipped"
[ $FAIL -eq 0 ] && [ $XPASS -eq 0 ]
