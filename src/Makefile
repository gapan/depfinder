CFLAGS?=-g -Wall -Wextra
CC=gcc
OBJS=depfinder.o main.o

main: $(OBJS)
	$(CC) $(CFLAGS) -o depfinder $(OBJS)
.PHONY: depfinder

$(OBJS):


valgrind:
	valgrind --leak-check=full \
		--show-leak-kinds=all \
		--track-origins=yes \
		--verbose \
		--log-file=valgrind-out.txt \
		./depfinder

clean:
	rm *.o ./depfinder
