# Makefile for aesdsocket
# Supports cross-compilation via CROSS_COMPILE variable

CC      := $(CROSS_COMPILE)gcc
CFLAGS  := -Wall -Wextra -g
TARGET  := aesdsocket
SRC     := aesdsocket.c

.PHONY: all default clean

all: $(TARGET)
default: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f $(TARGET)
