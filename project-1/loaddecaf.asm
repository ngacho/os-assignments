    .Code
_start:
    addi a0, a0, 0xcaf
    addi a0, zero, 0xde
    slli a0, a0, 12
    addi a0, a0, 0xcaf
_exit:
    lw	a6,	_syscall_exit_code
    ecall

    .Numeric
_syscall_exit_code: 0xabcd0001