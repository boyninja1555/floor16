AS = nasm

SRC = boot.asm
BIN = foor16.bin

all: $(BIN)

$(BIN): $(SRC)
	$(AS) -f bin -o $(BIN) $(SRC)

run: $(BIN)
	qemu-system-x86_64 -m 512M -drive format=raw,file=$(BIN)

clean:
	rm -f $(BIN)
