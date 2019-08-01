CFLAGS?=-g -Wall -Wextra
CC=gcc
TESTOBJS=test.o

run: test
	./test

test: $(TESTOBJS)
	$(CC) $(CFLAGS) -o test $(TESTOBJS) -lcheck
.PHONY: test

$(TESTOBJS):


valgrind:
	valgrind --leak-check=full \
		--show-leak-kinds=all \
		--track-origins=yes \
		--verbose \
		--log-file=valgrind-out.txt \
		./test
