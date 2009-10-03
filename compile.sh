#! /bin/sh

ccextras="-Wall -Wextra"
name="depfinder-search"	# Name of the executable.
bindir="bin"	# Directory where temporary binary objects are stored.
classes="CWhatProvides"

if [ "$1" == "-64" ];then
	export CXXFLAGS=${CXXFLAGS:="-O3 -fPIC -fomit-frame-pointer"}
else
	export CXXFLAGS=${CXXFLAGS:="-O3 -march=i486 -mtune=i686 -fomit-frame-pointer"}
fi

if [ "$1" == "-64" ];then
	sed -i "s/^LIBDIRSUFFIX=.*/LIBDIRSUFFIX=\"64\"/" depfinder
else
	sed -i "s/^LIBDIRSUFFIX=.*/LIBDIRSUFFIX=\"\"" depfinder
fi

# compile depfinder-search
( 
	cd depfinder-search

	mkdir -p "$bindir" 2> /dev/null

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
)

# compile locales
(
	cd locale
	for i in `ls *.po`; do
		echo "Compiling $i"
		msgfmt $i -o `echo $i | sed "s/.po//"`.mo
	done
)
