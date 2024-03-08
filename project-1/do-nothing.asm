# A test assembly program that does nothing at all.

	.Code

	li	a0,	13
	li	a1,	0x1a2b3c4d
_exit:
    lw	a6,	_syscall_exit_code
    ecall

    .Numeric
_syscall_exit_code: 0xabcd0001