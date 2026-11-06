AS = nasm

SRC = boot.asm
IMG = floor16.img

all: $(IMG)

$(IMG): $(SRC)
	$(AS) -f bin -o $(IMG) $(SRC)

run: $(IMG)
	qemu-system-x86_64 -m 512M -drive format=raw,file=$(IMG)

clean:
	rm -f $(IMG)
