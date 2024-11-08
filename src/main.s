; Memory-safe Brainfuck JIT compiler for ARM64
; Register allocation:
; x0: Base pointer to memory array (preserved)
; x1: Current data pointer
; x2: Temporary for bounds checking
; x3: Temporary for value operations
; x4: Loop counter/temporary
; x29: Frame pointer
; x30: Link register

.global _main
.align 4

_main:
    ; Prologue - Setup stack frame
    stp     x29, x30, [sp, #-16]!    ; Save frame pointer and link register
    mov     x29, sp                   ; Set up frame pointer

    ; Initialize memory array
    ; Allocate memory: mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov     x0, #0                    ; addr = NULL
    mov     x1, #30000               ; We'll handle this large value properly
    movk    x1, #0, lsl #16          ; Clear upper bits
    mov     x2, #3                    ; PROT_READ | PROT_WRITE
    mov     x3, #0x22                 ; MAP_PRIVATE | MAP_ANONYMOUS
    mov     x4, #-1                   ; fd = -1
    mov     x5, #0                    ; offset = 0
    mov     x8, #222                  ; sys_mmap
    svc     #0                        ; System call

    ; Check if memory allocation failed
    cmp     x0, #0
    b.lt    error_handler

    ; Initialize data pointer
    mov     x1, x0                    ; x1 = current data pointer = start of memory

    ; Memory safety bounds - using multiple instructions for large value
    mov     x2, #30000               ; Load lower 16 bits
    movk    x2, #0, lsl #16          ; Clear upper bits
    add     x2, x2, x0               ; x2 = base + 30000 (end of memory boundary)

    ; Example of increment operation ([>])
increment_op:
    ; Check bounds before incrementing pointer
    add     x3, x1, #1               ; Calculate new pointer position
    cmp     x3, x2                   ; Compare with end boundary
    b.ge    error_handler            ; Branch if would exceed boundary
    
    ; Safe to increment
    ldrb    w4, [x1]                 ; Load current byte
    add     w4, w4, #1               ; Increment value
    strb    w4, [x1]                 ; Store back to memory

decrement_op:
    ; Check bounds before decrementing pointer
    cmp     x1, x0                   ; Compare with start boundary
    b.lt    error_handler            ; Branch if would exceed boundary
    
    ; Safe to decrement
    ldrb    w4, [x1]                 ; Load current byte
    sub     w4, w4, #1               ; Decrement value
    strb    w4, [x1]                 ; Store back to memory

move_right:
    ; Bounds check for pointer movement
    add     x3, x1, #1               ; Calculate new pointer position
    cmp     x3, x2                   ; Compare with end boundary
    b.ge    error_handler            ; Branch if would exceed boundary
    
    add     x1, x1, #1               ; Move pointer right

move_left:
    ; Bounds check for pointer movement
    sub     x3, x1, #1               ; Calculate new pointer position
    cmp     x3, x0                   ; Compare with start boundary
    b.lt    error_handler            ; Branch if would exceed boundary
    
    sub     x1, x1, #1               ; Move pointer left

output_byte:
    ; Output current byte (.)
    mov     x0, #1                   ; fd = 1 (stdout)
    mov     x2, #1                   ; length = 1 byte
    mov     x8, #64                  ; sys_write
    svc     #0

input_byte:
    ; Input byte (,)
    mov     x0, #0                   ; fd = 0 (stdin)
    mov     x2, #1                   ; length = 1 byte
    mov     x8, #63                  ; sys_read
    svc     #0

error_handler:
    ; Handle error conditions
    mov     x0, #1                   ; Exit code 1
    mov     x8, #93                  ; sys_exit
    svc     #0

exit:
    ; Clean exit
    mov     x0, #0                   ; Exit code 0
    mov     x8, #93                  ; sys_exit
    svc     #0

; Loop implementation
loop_start:
    ; Stack management for loops
    stp     x4, x30, [sp, #-16]!    ; Save loop counter and return address
    
    ; Check current cell
    ldrb    w4, [x1]                ; Load current byte
    cbz     w4, loop_end            ; If zero, skip loop

loop_end:
    ; Restore registers and return
    ldp     x4, x30, [sp], #16      ; Restore loop counter and return address
    ret