#!/bin/bash

mkdir -p build bin
as -o bin/main.o src/main.s

ld -o build/brainfucker bin/main.o -lSystem -syslibroot $(xcrun -sdk macosx --show-sdk-path) -e _main -arch arm64

chmod +x build/brainfucker