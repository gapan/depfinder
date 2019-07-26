CFLAGS?=-g -Wall -Wextra
CC=gcc
TESTOBJS=test.o

run: test
	./test

test: $(TESTOBJS)
	$(CC) $(CFLAGS) -o test $(TESTOBJS) -lcheck
.PHONY: test

$(TESTOBJS):

