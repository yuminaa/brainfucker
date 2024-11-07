# compile.sh

rm -rf bin
rm -rf build
mkdir bin
mkdir build
as -arch arm64 src/main.s -o bin/main.o
ld main.o -o build/brainfucker -lSystem -syslibroot `xcrun -sdk macosx --show-sdk-path` -arch arm64
