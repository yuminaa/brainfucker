// This is an ARM64 assembly implementation of a Brainfuck interpreter.
// The program reads a Brainfuck program from the `test_program` label and executes it.
// It uses mmap to allocate a memory tape of 30,000 bytes and interprets the Brainfuck instructions.

// Global symbols
.global _main
.align 4

// Brainfuck program to be interpreted
test_program:
    .ascii  "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."
    .byte   0

.align 4
_main:
    // Save frame pointer and link register
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // mmap syscall to allocate memory for the tape
    mov     x0, #0                     // addr = NULL (system chooses address)
    mov     x1, #0x7530                // tape size = 30,000 bytes
    mov     x2, #3                     // PROT_READ | PROT_WRITE
    mov     x3, #0x1002                // MAP_PRIVATE | MAP_ANONYMOUS
    mov     x4, #-1                    // fd = -1 (not using a file)
    mov     x5, #0                     // offset = 0
    mov     x16, #197                  // macOS mmap syscall
    svc     #0x80                      // Perform mmap syscall

    // Check if mmap failed
    cbz     x0, error_handler

    // Initialize pointers
    mov     x19, x0                    // x19 = Base pointer
    mov     x20, x0                    // x20 = Current pointer
    mov     x21, #0x7000               // Load the high part
    add     x21, x21, #0x530           // Add the low part
    add     x21, x21, x19              // Add base pointer (x19)
    adr     x22, test_program          // x22 = Instruction pointer

interpret_loop:
    // Load instruction and check for end of program
    ldrb    w23, [x22]
    cbz     w23, cleanup

    // Brainfuck instruction handling
    cmp     w23, #'+'
    b.eq    increment
    cmp     w23, #'-'
    b.eq    decrement
    cmp     w23, #'>'
    b.eq    move_right
    cmp     w23, #'<'
    b.eq    move_left
    cmp     w23, #'.'
    b.eq    output
    cmp     w23, #','
    b.eq    input
    cmp     w23, #'['
    b.eq    loop_start
    cmp     w23, #']'
    b.eq    loop_end

    // Skip invalid instructions
    add     x22, x22, #1
    b       interpret_loop

increment:
    // Increment the value at the current cell
    ldrb    w24, [x20]
    add     w24, w24, #1
    strb    w24, [x20]
    b       advance

decrement:
    // Decrement the value at the current cell
    ldrb    w24, [x20]
    sub     w24, w24, #1
    strb    w24, [x20]
    b       advance

move_right:
    // Move the pointer to the right
    add     x20, x20, #1
    cmp     x20, x21
    b.ge    error_handler
    b       advance

move_left:
    // Move the pointer to the left
    sub     x20, x20, #1
    cmp     x20, x19
    b.lt    error_handler
    b       advance

output:
    // Output the value at the current cell
    mov     x0, #1                     // stdout
    mov     x1, x20                    // current cell
    mov     x2, #1                     // length
    mov     x16, #4                    // write syscall
    svc     #0x80
    b       advance

input:
    // Input a value into the current cell
    mov     x0, #0                     // stdin
    mov     x1, x20
    mov     x2, #1
    mov     x16, #3                    // read syscall
    svc     #0x80
    b       advance

loop_start:
    // Start of a loop
    ldrb    w24, [x20]
    cbz     w24, find_loop_end
    b       advance

find_loop_end:
    // Find the matching ']'
    mov     w25, #1

find_loop_end_inner:
    add     x22, x22, #1
    ldrb    w24, [x22]
    cbz     w24, error_handler
    cmp     w24, #'['
    b.eq    increment_depth
    cmp     w24, #']'
    b.eq    decrement_depth
    b       find_loop_end_inner

increment_depth:
    add     w25, w25, #1
    b       find_loop_end_inner

decrement_depth:
    sub     w25, w25, #1
    cbz     w25, find_loop_end_done
    b       find_loop_end_inner

find_loop_end_done:
    b       advance

loop_end:
    // End of a loop
    ldrb    w24, [x20]
    cbnz    w24, find_loop_start
    b       advance

find_loop_start:
    // Find the matching '['
    mov     w25, #1

find_loop_start_inner:
    sub     x22, x22, #1
    ldrb    w24, [x22]
    cbz     w24, error_handler
    cmp     w24, #']'
    b.eq    increment_depth_back
    cmp     w24, #'['
    b.eq    decrement_depth_back
    b       find_loop_start_inner

increment_depth_back:
    add     w25, w25, #1
    b       find_loop_start_inner

decrement_depth_back:
    sub     w25, w25, #1
    cbz     w25, interpret_loop
    b       find_loop_start_inner

advance:
    // Advance to the next instruction
    add     x22, x22, #1
    b       interpret_loop

cleanup:
    // Cleanup and exit
    mov     x0, x19
    mov     x1, #0x7530
    mov     x16, #73                  // munmap syscall
    svc     #0x80

    mov     x0, #0
    mov     x16, #1                   // exit syscall
    svc     #0x80

error_handler:
    // Error handler
    mov     x0, #1
    mov     x16, #1
    svc     #0x80
