CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror -pedantic
BIN := build/rg-grep-compat

.PHONY: all test clean install-user uninstall-user
all: $(BIN)

$(BIN): src/rg-grep-compat.c
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

test: $(BIN)
	bash tests/test.sh $(abspath $(BIN))

install-user: $(BIN)
	bash scripts/install-user.sh $(abspath $(BIN))

uninstall-user:
	bash scripts/uninstall-user.sh

clean:
	rm -rf build
