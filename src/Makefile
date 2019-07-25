
depfinder:
	gcc -Wall -g -o depfinder depfinder.c
.PHONY: depfinder

valgrind:
	valgrind --leak-check=full \
		--show-leak-kinds=all \
		--track-origins=yes \
		--verbose \
		--log-file=valgrind-out.txt \
		./depfinder

