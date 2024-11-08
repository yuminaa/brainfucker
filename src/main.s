.section __TEXT,__text
.globl _main
.align 2

.section __TEXT,__const
syscall_mmap:     .quad 0x20000c5
syscall_munmap:   .quad 0x2000049
syscall_mprotect: .quad 0x200004a
bf_memsize:       .quad 30000
page_size:        .quad 4096
jit_size:         .quad 8192     // Increased JIT size
guard_pages_size: .quad 8192     // 2 * 4096

// Debug messages
.section __TEXT,__cstring
debug_jit_alloc:  .asciz "Attempting JIT allocation...\n"
debug_jit_fail:   .asciz "JIT allocation failed. errno: %d\n"
debug_bf_alloc:   .asciz "Attempting BF memory allocation...\n"
error_msg_alloc:  .asciz "Memory allocation failed\n"
error_msg_bounds: .asciz "Buffer bounds exceeded\n"
error_msg_invalid: .asciz "Invalid program instruction\n"
test_program:     .asciz "++."

.section __TEXT,__const
jit_prologue:
    .long   0xA9BF2FEA     // stp x10, x11, [sp, #-16]!
    .long   0xA9BF27E8     // stp x8, x9, [sp, #-16]!
    .long   0xD2800008     // mov x8, #0

jit_increment:
    .long   0x38686D4A     // ldrb w10, [x9, x8]
    .long   0x11000550     // add w10, w10, #1
    .long   0x38286D4A     // strb w10, [x9, x8]

jit_decrement:
    .long   0x38686D4A     // ldrb w10, [x9, x8]
    .long   0x51000550     // sub w10, w10, #1
    .long   0x38286D4A     // strb w10, [x9, x8]

jit_move_right:
    .long   0x91000508     // add x8, x8, #1
    .long   0xF1007D08     // cmp x8, #30000-1
    .long   0x54000082     // b.cs bounds_error_handler

jit_move_left:
    .long   0xF100050F     // cmp x8, #0
    .long   0x54000064     // b.ls bounds_error_handler
    .long   0xD1000508     // sub x8, x8, #1

jit_output:
    .long   0xD2800020     // mov x0, #1 (stdout)
    .long   0x8B080121     // add x1, x9, x8
    .long   0xD2800001     // mov x0, #0
    .long   0xD2800021     // mov x1, #1
    .long   0xD2800210     // mov x16, #16 (write syscall)
    .long   0xD4001001     // svc #0x80

jit_epilogue:
    .long   0xA8C127E8     // ldp x8, x9, [sp], #16
    .long   0xA8C12FEA     // ldp x10, x11, [sp], #16
    .long   0xD65F03C0     // ret

.section __TEXT,__text
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!

    // Print debug message before JIT allocation
    adrp    x0, debug_jit_alloc@PAGE
    add     x0, x0, debug_jit_alloc@PAGEOFF
    bl      _printf

    // Load JIT size and align to page boundary
    adrp    x26, jit_size@PAGE
    ldr     x26, [x26, jit_size@PAGEOFF]
    add     x26, x26, #4095        // Round up to next page
    and     x26, x26, #~4095       // Align to page boundary

    // Attempt JIT allocation
    mov     x0, #0                  // addr = NULL
    mov     x1, x26                // size
    mov     x2, #0x3               // PROT_READ | PROT_WRITE
    mov     x3, #0x1012            // MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT (0x1000 | 0x0002 | 0x0010)
    mov     x4, #-1                // fd
    mov     x5, #0                 // offset
    
    // Properly load the syscall number using adrp/ldr
    adrp    x16, syscall_mmap@PAGE
    ldr     x16, [x16, syscall_mmap@PAGEOFF]
    svc     #0x80

    // Check allocation result
    cmn     x0, #0
    b.cs    1f

    // Print error if allocation failed
    mov     x1, x0                 // Save error code
    adrp    x0, debug_jit_fail@PAGE
    add     x0, x0, debug_jit_fail@PAGEOFF
    bl      _printf
    b       alloc_error

1:  // JIT allocation succeeded
    mov     x20, x0                // Save JIT buffer address
    mov     x21, x0                // Current JIT position

    // Print debug message before BF memory allocation
    adrp    x0, debug_bf_alloc@PAGE
    add     x0, x0, debug_bf_alloc@PAGEOFF
    bl      _printf

    // Load constants for BF memory
    adrp    x25, bf_memsize@PAGE
    ldr     x25, [x25, bf_memsize@PAGEOFF]
    adrp    x24, guard_pages_size@PAGE
    ldr     x24, [x24, guard_pages_size@PAGEOFF]
    adrp    x23, page_size@PAGE
    ldr     x23, [x23, page_size@PAGEOFF]

    // Allocate BF memory
    mov     x0, #0                  // addr = NULL
    add     x1, x25, x24           // size = BF memory + guard pages
    mov     x2, #0x3               // PROT_READ | PROT_WRITE
    mov     x3, #0x1002            // MAP_PRIVATE | MAP_ANONYMOUS
    mov     x4, #-1                // fd
    mov     x5, #0                 // offset
    adrp    x16, syscall_mmap@PAGE
    ldr     x16, [x16, syscall_mmap@PAGEOFF]
    svc     #0x80

    // Check BF memory allocation
    cmn     x0, #0
    b.cs    1f
    b       alloc_error

1:  mov     x19, x0                // Save base address
    add     x19, x19, x23          // Skip first guard page

    // Protect first guard page
    mov     x0, x19
    sub     x0, x0, x23           // Go back to guard page
    mov     x1, x23               // page size
    mov     x2, #0                // PROT_NONE
    adrp    x16, syscall_mprotect@PAGE
    ldr     x16, [x16, syscall_mprotect@PAGEOFF]
    svc     #0x80

    // Protect second guard page
    add     x0, x19, x25          // End of BF memory
    mov     x1, x23               // page size
    mov     x2, #0                // PROT_NONE
    adrp    x16, syscall_mprotect@PAGE
    ldr     x16, [x16, syscall_mprotect@PAGEOFF]
    svc     #0x80

    // Load program address
    adrp    x22, test_program@PAGE
    add     x22, x22, test_program@PAGEOFF

    // Copy prologue
    adrp    x0, jit_prologue@PAGE
    add     x0, x0, jit_prologue@PAGEOFF
    bl      copy_with_bounds_check

compile_loop:
    ldrb    w23, [x22], #1       // Load next instruction
    cbz     w23, compile_done

    // Validate instruction
    cmp     w23, #'+'
    b.eq    gen_increment
    cmp     w23, #'-'
    b.eq    gen_decrement
    cmp     w23, #'>'
    b.eq    gen_move_right
    cmp     w23, #'<'
    b.eq    gen_move_left
    cmp     w23, #'.'
    b.eq    gen_output
    b       invalid_instruction

gen_increment:
    adrp    x0, jit_increment@PAGE
    add     x0, x0, jit_increment@PAGEOFF
    bl      copy_with_bounds_check
    b       compile_loop

gen_decrement:
    adrp    x0, jit_decrement@PAGE
    add     x0, x0, jit_decrement@PAGEOFF
    bl      copy_with_bounds_check
    b       compile_loop

gen_move_right:
    adrp    x0, jit_move_right@PAGE
    add     x0, x0, jit_move_right@PAGEOFF
    bl      copy_with_bounds_check
    b       compile_loop

gen_move_left:
    adrp    x0, jit_move_left@PAGE
    add     x0, x0, jit_move_left@PAGEOFF
    bl      copy_with_bounds_check
    b       compile_loop

gen_output:
    adrp    x0, jit_output@PAGE
    add     x0, x0, jit_output@PAGEOFF
    bl      copy_with_bounds_check
    b       compile_loop

compile_done:
    // Copy epilogue
    adrp    x0, jit_epilogue@PAGE
    add     x0, x0, jit_epilogue@PAGEOFF
    bl      copy_with_bounds_check

    // Make JIT memory executable
    mov     x0, x20               // JIT buffer address
    mov     x1, x26               // JIT buffer size
    mov     x2, #0x5              // PROT_READ | PROT_EXEC
    adrp    x16, syscall_mprotect@PAGE
    ldr     x16, [x16, syscall_mprotect@PAGEOFF]
    svc     #0x80

    cmn     x0, #0
    b.cs    1f
    b       protection_error
1:
    // Execute generated code
    mov     x9, x19               // Set BF memory pointer
    blr     x20                   // Call generated code

    b       cleanup

copy_with_bounds_check:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Check bounds
    sub     x1, x21, x20
    add     x1, x1, #16
    cmp     x1, x26               // Compare with JIT buffer size
    b.ge    buffer_overflow

    // Copy instructions
    ldp     x1, x2, [x0], #16
    stp     x1, x2, [x21], #16

    ldp     x29, x30, [sp], #16
    ret

bounds_error_handler:
    adrp    x0, error_msg_bounds@PAGE
    add     x0, x0, error_msg_bounds@PAGEOFF
    bl      _puts
    mov     w0, #1
    b       cleanup

alloc_error:
    adrp    x0, error_msg_alloc@PAGE
    add     x0, x0, error_msg_alloc@PAGEOFF
    bl      _puts
    mov     w0, #1
    b       exit

buffer_overflow:
    adrp    x0, error_msg_bounds@PAGE
    add     x0, x0, error_msg_bounds@PAGEOFF
    bl      _puts
    mov     w0, #1
    b       exit

invalid_instruction:
    adrp    x0, error_msg_invalid@PAGE
    add     x0, x0, error_msg_invalid@PAGEOFF
    bl      _puts
    mov     w0, #1
    b       exit

protection_error:
    mov     w0, #1
    b       exit

cleanup:
    // Unmap JIT memory
    mov     x0, x20               // JIT buffer address
    mov     x1, x26               // JIT buffer size
    adrp    x16, syscall_munmap@PAGE
    ldr     x16, [x16, syscall_munmap@PAGEOFF]
    svc     #0x80

    // Unmap all BF memory (including guard pages)
    mov     x0, x19
    sub     x0, x0, x23          // Start from first guard page
    add     x1, x25, x24         // Total size (BF memory + guard pages)
    adrp    x16, syscall_munmap@PAGE
    ldr     x16, [x16, syscall_munmap@PAGEOFF]
    svc     #0x80

    mov     w0, #0               // Success status

exit:
    // Restore registers
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret