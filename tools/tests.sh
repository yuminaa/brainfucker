# tests.sh

chmod +x brainfucker

echo "+>+." > tests/add.bf
echo ",[.,]" > tests/cat.bf
echo "+++++[>+++++[>+++++<-]<-]>>." > tests/A.bf

./build/brainfucker tests/add.bf
./build/brainfucker tests/cat.bf
./build/brainfucker tests/A.bf
./build/brainfucker tests/hello_world.bf