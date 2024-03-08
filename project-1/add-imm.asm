# A simple program that adds two numbers.

	.Code

# The entry point.
__start:

	addi	t0,	zero,	13
	addi	t1,	t0,	-7
	
end:	
    # exit
    lw	a6,	_syscall_exit_code
	ecall

    .Numeric
_syscall_exit_code: 0xabcd0001