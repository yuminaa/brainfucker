// Part of Brainfucker JIT compiler.
// Licensed under MIT license. See LICENSE file for details.

.section __TEXT,__text
.align 4

.extern _malloc
.extern _free
.extern _strlen
.extern _pthread_jit_write_protect_np

.set SYS_exit,      0x1
.set SYS_read,      0x3
.set SYS_write,     0x4
.set SYS_open,      0x5
.set SYS_close,     0x6
.set SYS_mmap,      0xC5
.set SYS_munmap,    0xC7
.set SYS_mprotect,  0x4A
.set SYS_lseek,     0x11

.set PROT_READ,     0x1
.set PROT_WRITE,    0x2
.set PROT_EXEC,     0x4
.set MAP_PRIVATE,   0x0002
.set MAP_ANON,      0x1000
.set MAP_JIT,       0x0800

.set O_RDONLY,      0x0
.set SEEK_SET,      0x0
.set SEEK_END,      0x2

.section __DATA,__const
.align 4
.const_code_size:       .long 1000000    // 1MB for JIT buffer
.const_mem_size:        .long 30000      // 30KB for BF tape
.const_ret_insn:        .long 0xD65F03C0 // RET instruction
.const_ldrb_insn:       .long 0x39400001 // LDRB W1, [X0]
.const_cbnz_insn:       .long 0x35000000 // CBNZ base instruction
.const_b_insn:          .long 0x54000000 // B base instruction

.section __DATA,__data
.align 4
err_usage:      .ascii  "Usage: ./bf <input_file>\n\0"
err_alloc:      .ascii  "Memory allocation failed\n\0"
err_file:       .ascii  "File operation failed\n\0"
err_compile:    .ascii  "Compilation failed\n\0"

.align 4
template_inc_ptr:   .long 0x91000400      // add x0, x0, #1
template_dec_ptr:   .long 0xD1000400      // sub x0, x0, #1
template_inc_val:
    .long 0x39400001      // ldrb w1, [x0]
    .long 0x11000421      // add w1, w1, #1
    .long 0x39000001      // strb w1, [x0]
template_dec_val:
    .long 0x39400001      // ldrb w1, [x0]
    .long 0x51000421      // sub w1, w1, #1
    .long 0x39000001      // strb w1, [x0]
template_putchar:
    .long 0xF81F0FE0      // str x0, [sp, #-16]!
    .long 0xD2800008      // mov x8, #SYS_write
    .long 0xD2800001      // mov x0, #1
    .long 0xAA0003E1      // mov x1, x0
    .long 0xD2800002      // mov x2, #1
    .long 0xD4000001      // svc #0
    .long 0xF84107E0      // ldr x0, [sp], #16

// NOTE: Optimizable
template_getchar:
    .long 0xF81F0FE0      // str x0, [sp, #-16]!
    .long 0xD2800008      // mov x8, #SYS_read
    .long 0xD2800000      // mov x0, #0
    .long 0xAA0003E1      // mov x1, x0
    .long 0xD2800002      // mov x2, #1
    .long 0xD4000001      // svc #0
    .long 0xF84107E0      // ldr x0, [sp], #16

.section __BSS,__bss
.align 4
loop_stack:     .space 8000        // Space for 1000 nested loops
loop_depth:     .space 8           // Current nested loop level

.section __TEXT,__text
.globl _main
.align 2

_main:
    stp     x29, x30, [sp, -16]!
    mov     x29, sp

    // Check args count
    cmp     x0, #2
    b.lt    Lusage_error

    // Save input file path
    ldr     x19, [x1, #8]        // argv[1]

    // Enable JIT permissions
    mov     x0, #1
    bl      _pthread_jit_write_protect_np

    // Allocate executable memory for JIT buffer
    mov     x0, #0               // addr hint
    adrp    x1, .const_code_size@PAGE
    add     x1, x1, .const_code_size@PAGEOFF
    ldr     w1, [x1]
    mov     x2, #(PROT_READ | PROT_WRITE | PROT_EXEC)
    mov     x3, #(MAP_PRIVATE | MAP_ANON | MAP_JIT)
    mov     x4, #-1              // fd
    mov     x5, #0               // offset
    mov     x16, #SYS_mmap
    svc     #0

    // Check allocation success
    cmn     x0, #1
    b.eq    Lalloc_error

    // Save code buffer address
    mov     x20, x0              // x20 = code buffer

    // Allocate BF tape memory
    mov     x0, #0
    adrp    x1, .const_mem_size@PAGE
    add     x1, x1, .const_mem_size@PAGEOFF
    ldr     w1, [x1]
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANON)
    mov     x4, #-1
    mov     x5, #0
    mov     x16, #SYS_mmap
    svc     #0

    // Check allocation
    cmn     x0, #1
    b.eq    Lalloc_error

    // Save tape memory address
    mov     x21, x0              // x21 = tape memory

    // Read input file
    mov     x0, x19             // filename
    bl      read_file

    // Check file read success
    cbz     x0, Lfile_error

    // Save input buffer and size
    mov     x19, x0             // x19 = input buffer
    mov     x22, x1             // x22 = input size

    // Compile BF code
    mov     x0, x19             // source
    mov     x1, x22             // length
    mov     x2, x20             // code buffer
    mov     x3, x21             // tape memory
    bl      compile_bf

    // Check compilation success
    cbz     x0, Lcompile_error

    // Execute generated code
    blr     x0                  // Call generated code

    // Cleanup and exit
    mov     x0, x20
    adrp    x1, .const_code_size@PAGE
    add     x1, x1, .const_code_size@PAGEOFF
    ldr     w1, [x1]
    mov     x16, #SYS_munmap
    svc     #0

    mov     x0, x21
    adrp    x1, .const_mem_size@PAGE
    add     x1, x1, .const_mem_size@PAGEOFF
    ldr     w1, [x1]
    mov     x16, #SYS_munmap
    svc     #0

    mov     x0, x19
    bl      _free

    mov     w0, #0
    ldp     x29, x30, [sp], #16
    ret

Lusage_error:
    adrp    x0, err_usage@PAGE
    add     x0, x0, err_usage@PAGEOFF
    bl      print_error
    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

Lalloc_error:
    adrp    x0, err_alloc@PAGE
    add     x0, x0, err_alloc@PAGEOFF
    bl      print_error
    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

Lfile_error:
    adrp    x0, err_file@PAGE
    add     x0, x0, err_file@PAGEOFF
    bl      print_error
    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

Lcompile_error:
    adrp    x0, err_compile@PAGE
    add     x0, x0, err_compile@PAGEOFF
    bl      print_error
    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

// Function to compile BF code
compile_bf:
    stp     x29, x30, [sp, -16]!
    mov     x29, sp
    stp     x19, x20, [sp, -16]!
    stp     x21, x22, [sp, -16]!

    mov     x19, x0              // Save source
    mov     x20, x1              // Save length
    mov     x21, x2              // Save code buffer
    mov     x22, x3              // Save tape memory

    // Generate prologue - mov x0, tape_memory
    mov     x0, x22
    str     x0, [x21], #8

Lcompile_loop:
    cbz     x20, Lcompile_done   // Check if we're done

    ldrb    w0, [x19], #1        // Load next character
    sub     x20, x20, #1         // Decrement length

    // Switch on character
    cmp     w0, #'>'
    b.eq    Ldo_inc_ptr
    cmp     w0, #'<'
    b.eq    Ldo_dec_ptr
    cmp     w0, #'+'
    b.eq    Ldo_inc_val
    cmp     w0, #'-'
    b.eq    Ldo_dec_val
    cmp     w0, #'.'
    b.eq    Ldo_putchar
    cmp     w0, #','
    b.eq    Ldo_getchar
    cmp     w0, #'['
    b.eq    Ldo_loop_start
    cmp     w0, #']'
    b.eq    Ldo_loop_end

    b       Lcompile_loop

Lcompile_done:
    // Generate epilogue - ret
    adrp    x0, .const_ret_insn@PAGE
    add     x0, x0, .const_ret_insn@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4

    mov     x0, x21              // Return code buffer
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

Ldo_inc_ptr:
    adrp    x0, template_inc_ptr@PAGE
    add     x0, x0, template_inc_ptr@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4
    b       Lcompile_loop

Ldo_dec_ptr:
    adrp    x0, template_dec_ptr@PAGE
    add     x0, x0, template_dec_ptr@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4
    b       Lcompile_loop

Ldo_inc_val:
    adrp    x0, template_inc_val@PAGE
    add     x0, x0, template_inc_val@PAGEOFF
    ldp     q0, q1, [x0]
    stp     q0, q1, [x21], #32
    b       Lcompile_loop

Ldo_dec_val:
    adrp    x0, template_dec_val@PAGE
    add     x0, x0, template_dec_val@PAGEOFF
    ldp     q0, q1, [x0]
    stp     q0, q1, [x21], #32
    b       Lcompile_loop

Ldo_putchar:
    adrp    x0, template_putchar@PAGE
    add     x0, x0, template_putchar@PAGEOFF
    mov     x2, #28              // Template size
Lcopy_putchar:
    ldr     w1, [x0], #4
    str     w1, [x21], #4
    subs    x2, x2, #4
    b.ne    Lcopy_putchar
    b       Lcompile_loop

Ldo_getchar:
    adrp    x0, template_getchar@PAGE
    add     x0, x0, template_getchar@PAGEOFF
    mov     x2, #28              // Template size
Lcopy_getchar:
    ldr     w1, [x0], #4
    str     w1, [x21], #4
    subs    x2, x2, #4
    b.ne    Lcopy_getchar
    b       Lcompile_loop

Ldo_loop_start:
    // Save current position
    adrp    x0, loop_depth@PAGE
    add     x0, x0, loop_depth@PAGEOFF
    ldr     x1, [x0]
    adrp    x2, loop_stack@PAGE
    add     x2, x2, loop_stack@PAGEOFF
    str     x21, [x2, x1, lsl #3]
    add     x1, x1, #1
    str     x1, [x0]

    // Generate conditional branch
    adrp    x0, .const_ldrb_insn@PAGE
    add     x0, x0, .const_ldrb_insn@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4
    adrp    x0, .const_cbnz_insn@PAGE
    add     x0, x0, .const_cbnz_insn@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4
    b       Lcompile_loop

Ldo_loop_end:
    // Get matching loop start
    adrp    x0, loop_depth@PAGE
    add     x0, x0, loop_depth@PAGEOFF
    ldr     x1, [x0]
    sub     x1, x1, #1
    str     x1, [x0]
    adrp    x2, loop_stack@PAGE
    add     x2, x2, loop_stack@PAGEOFF
    ldr     x1, [x2, x1, lsl #3]

    // Calculate and patch forward branch
    sub     x2, x21, x1
    lsr     x2, x2, #2
    adrp    x0, .const_cbnz_insn@PAGE
    add     x0, x0, .const_cbnz_insn@PAGEOFF
    ldr     w0, [x0]
    orr     w0, w0, w2           // Add offset to instruction
    str     w0, [x1]

    // Generate backward branch
    adrp    x0, .const_ldrb_insn@PAGE
    add     x0, x0, .const_ldrb_insn@PAGEOFF
    ldr     w0, [x0]
    str     w0, [x21], #4
    sub     x2, x1, x21
    lsr     x2, x2, #2
    adrp    x0, .const_b_insn@PAGE
    add     x0, x0, .const_b_insn@PAGEOFF
    ldr     w0, [x0]
    orr     w0, w0, w2           // Add offset to instruction
    str     w0, [x21], #4
    b       Lcompile_loop

read_file:
    stp     x29, x30, [sp, -16]!
    mov     x29, sp

    // Open file
    mov     w1, O_RDONLY
    mov     x16, #SYS_open
    svc     #0

    // Check for error
    cmn     x0, #1
    b.eq    Lread_error

    mov     x19, x0              // Save fd

    // Get file size
    mov     x0, x19
    mov     x1, #0
    mov     x2, SEEK_END
    mov     x16, #SYS_lseek
    svc     #0

    mov     x20, x0              // Save file size

    // Reset to start
    mov     x0, x19
    mov     x1, #0
    mov     x2, SEEK_SET
    mov     x16, #SYS_lseek
    svc     #0

    // Allocate buffer
    mov     x0, x20
    bl      _malloc
    cbz     x0, Lread_error

    mov     x21, x0              // Save buffer address

    // Read file
    mov     x0, x19
    mov     x1, x21
    mov     x2, x20
    mov     x16, #SYS_read
    svc     #0

    // Close file
    mov     x0, x19
    mov     x16, #SYS_close
    svc     #0

    mov     x0, x21              // Return buffer
    mov     x1, x20              // Return size
    ldp     x29, x30, [sp], #16
    ret

Lread_error:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

print_error:
    stp     x29, x30, [sp, -16]!
    mov     x29, sp

    bl      _strlen

    mov     x2, x0               // Length
    mov     x1, x0               // String
    mov     x0, #2               // stderr
    mov     x16, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret

.subsections_via_symbols
