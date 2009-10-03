#! /bin/sh

ccextras="-Wall -Wextra"
name="depfinder-search"	# Name of the executable.
bindir="bin"	# Directory where temporary binary objects are stored.
classes="CWhatProvides"

mkdir "$bindir" 2> /dev/null

for curfile in $classes; do
	if [ "$curfile.cpp" -nt "$bindir/$curfile.o" ] || [ "$curfile.h" -nt "$bindir/$curfile.o" ]; then
		echo "g++ -c $ccextras $CXXFLAGS \"$curfile.cpp\" -o \"$bindir/$curfile.o\""
		g++ -c $ccextras $CXXFLAGS "$curfile.cpp" -o "$bindir/$curfile.o"
	fi
done
for curfile in $classes; do
	linkage="$linkage $bindir/$curfile.o"
done

echo "g++ $ccextras $CXXFLAGS -o \"$name\" main.cpp $linkage"
rm -f "$name"
g++ $ccextras $CXXFLAGS -o "$name" main.cpp $linkage
