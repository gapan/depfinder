ARCH ?= x86_64

CCEXTRAS = -Wall -Wextra
ifeq ($(ARCH),i486)
	CXXFLAGS = -O3 -march=i486 -mtune=i686 -fomit-frame-pointer
else ifeq ($(ARCH),i586)
	CXXFLAGS = -O3 -march=i586 -mtune=i686 -fomit-frame-pointer
else ifeq ($(ARCH),i686)
	CXXFLAGS = -O3 -march=i686 -mtune=i686 -fomit-frame-pointer
else
	CXXFLAGS = -O3 -fPIC -fomit-frame-pointer
endif

depfinder-search:
	g++ -c $(CCEXTRAS) $(CXXFLAGS) CWhatProvides.cpp -o CWhatProvides.o
	g++ $(CCEXTRAS) $(CXXFLAGS) -o depfinder-search main.cpp CWhatProvides.o

clean:
	rm -f CWhatProvides.o
	rm -f depfinder-search
