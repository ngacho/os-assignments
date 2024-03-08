# An example of a conditional structure.  Try changing the value at n in the Numerics to control which branch is taken.

	.Code

	# Initialize: load [t0] n so we can use it.
	lw		t0,		n
	
	# Conditional branch.  Note logic inversion, since we jump to the else-branch, but fall through to the then-branch.
	blt		t0,		zero,		else		# if (n >= 0) ...

	# then-branch...
	addi		t1,		t0,		5		# x = n + 5
	j		end						# skip over else-branch

else:	# else-branch
	addi		t1,		t0,		13		# x = n + 13

end:	# Unification point.
	li		t2,		2				# t2 = 2
	mul		t1,		t1,		t2		# x = x * 2
	halt

	.Numeric

n:	-5
