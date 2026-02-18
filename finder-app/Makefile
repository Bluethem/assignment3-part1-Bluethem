CC ?= $(CROSS_COMPILE)gcc
CFLAGS ?= -g

all: writer

writer: writer.o
	$(CC) $(CFLAGS) writer.o -o writer

writer.o: writer.c
	$(CC) $(CFLAGS) -c writer.c -o writer.o

clean:
	rm -f writer writer.o
