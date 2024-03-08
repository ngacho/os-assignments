# A simple loop through a counter.

	.Code

	lw		t0,		n				# [t0] n
looptop:
	beq		t0,		zero,		loopend		# while (n != 0) {
	addi		t0,		t0,		-1		#   n = n - 1
	j		looptop						# }

loopend:
	halt

	.Numeric

n:	3
