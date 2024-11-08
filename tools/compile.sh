#!/bin/bash

# Create directories if they don't exist
mkdir -p build bin

# Assemble
as -o bin/main.o src/main.s

# Link
ld -o build/brainfucker bin/main.o -lSystem -syslibroot $(xcrun -sdk macosx --show-sdk-path) -e _main -arch arm64

# Set executable permissions
chmod +x build/brainfucker