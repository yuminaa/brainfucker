AS = as
LD = ld
ARCH = arm64
SDK_PATH = $(shell xcrun -sdk macosx --show-sdk-path)

SRC_DIR = src
BIN_DIR = bin
BUILD_DIR = build
TEST_DIR = tests

MAIN_OBJ = $(BIN_DIR)/main.o
EXECUTABLE = $(BUILD_DIR)/brainfucker

all: clean $(EXECUTABLE) test

$(BIN_DIR) $(BUILD_DIR):
	mkdir -p $@

$(MAIN_OBJ): $(SRC_DIR)/main.s | $(BIN_DIR)
	$(AS) -arch $(ARCH) $< -o $@

$(EXECUTABLE): $(MAIN_OBJ) | $(BUILD_DIR)
	$(LD) $< -o $@ -lSystem -syslibroot $(SDK_PATH) -arch $(ARCH)
	chmod +x $@

clean:
	rm -rf $(BIN_DIR) $(BUILD_DIR)

test:
	$(EXECUTABLE) $(TEST_DIR)/add.bf
	$(EXECUTABLE) $(TEST_DIR)/cat.bf
	$(EXECUTABLE) $(TEST_DIR)/cat.bf

.PHONY: all clean test create_test_files