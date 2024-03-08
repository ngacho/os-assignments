	.Code
	
__start:	

#	THE LABEL length POINTS TO AN INTEGER THAT PROVIDES THE LENGTH
#	OF THE ARRAY -- THAT IS, THE NUMBER OF VALUES TO EXAMINE.  THE
#	LABEL array POINTS TO THE ARRAY OF VALUES THEMSELVES.  WHEN
#	YOUR PROGRAM HAS HAS COMPLETED, THE MAXIMUM OF THE VALUES IN
#	THE ARRAY SHOULD APPEAR IN THE MAIN MEMORY LOCATION AT WHICH
#	result POINTS.

	# Initialization.
	mv		s0,		zero				# [s0] max = 0
	lw		t0,		length				# [t0] length = array.length
	mv		t1,		zero				# [t1] index = 0
	la		t2,		array				# [t2] current_ptr = &array[0]

	# Iterate, ending when we have run through the whole array.
top:
	bge		t1,		t0,		end		# while (index < length) {
	lw		t3,		0(t2)				#   [t3] current = *current_ptr = array[index]
	ble		t3,		s0,		increment       #   if (current > max)
	mv		s0,		t3				#     max = current
increment:
	addi		t1,		t1,		1		#   ++index
	addi		t2,		t2,		4		#   ++current_ptr
	j		top						# }
	
end:
	# The max value should be sitting in s0
	halt
			
	.Numeric

length:		5
array:		3	5	4	10	2
result:		0x3000							# Assume that main memory starts at this address.
