### ================================================================================================================================
### kernel.asm
###
### The assembly core that perform the basic initialization of the kernel, bootstrapping the installation of trap handlers and
### configuring the kernel's memory space.
### ================================================================================================================================


### ================================================================================================================================
	.Code
### ================================================================================================================================



### ================================================================================================================================
### Entry point.

__start:	
	## Find RAM.  Start the search at the beginning of the device table.
	lw		t0,		_static_device_table_base		# [t0] dt_current = &device_table[0]
	lw		s0,		_static_none_device_code		# [s0] none_device_code
	lw		s1,		_static_RAM_device_code			# [s1] RAM_device_code
	
RAM_search_loop_top:

	## End the search with failure if we've reached the end of the table without finding RAM.
	lw		t1,		0(t0) 					# [t1] device_code = dt_current->type_code
	beq		t1,		s0,		RAM_search_failure 	# if (device_code == none_device_code)

	## If this entry is RAM, then end the loop successfully.
	beq		t1,		s1,		RAM_found 		# if (device_code == RAM_device_code)

	## This entry is not RAM, so advance to the next entry.
	addi		t0,		t0,		12 			# [t0] dt_current += dt_entry_size
	j		RAM_search_loop_top

RAM_search_failure:

	## Record a code to indicate the error, and then halt.
	lw		a0,		_static_kernel_error_RAM_not_found
	halt

RAM_found:
	
	## RAM has been found.  If it is big enough, create a stack.
	lw		t1,		4(t0) 					# [t1] RAM_base  = dt_RAM->base
	lw		t2,		8(t0)					# [t2] RAM_limit = dt_RAM->limit
	sub		t0,		t2,		t1			# [t0] |RAM| = RAM_limit - RAM_base
	lw		t3,		_static_min_RAM				# [t3] |min_RAM|
	blt		t0,		t3,		RAM_too_small		# if (|RAM| < |min_RAM|) ...
	lw		t3,		_static_kernel_size			# [t3] ksize
	add		sp,		t1,		t3			# [sp] klimit = RAM_base + ksize : new stack
	mv		fp,		sp					# Initialize fp

	## Copy the RAM and kernel bases and limits to statically allocated spaces.
	sw		t1,		_static_RAM_base,	t6
	sw		t2,		_static_RAM_limit,	t6
	sw		t1,		_static_kernel_base,	t6	
	sw		sp,		_static_kernel_limit,	t6

	## With the stack initialized, call main() to begin booting proper.
	addi		sp,		sp,		-8			# Push pfp / ra
	sw		fp,		0(sp)					# Preserve fp
	mv		fp,		sp					# Update fp
	call		_procedure_main

	## Wrap up and halt.  Termination code has already been returned by main() in a0.
	lw		fp,		0(sp)					# Restore fp
	addi		sp,		sp,		8			# Pop pfp / ra
	halt

RAM_too_small:

	## Set an error code and halt.
	lw		a0,		_static_kernel_error_small_RAM
	halt
### ================================================================================================================================



### ================================================================================================================================	
### Procedure: find_device
### Parameters:
###   [a0]: type     -- The device type to find.
###   [a1]: instance -- The instance of the given device type to find (e.g., the 3rd ROM).
### Caller preserved registers:
###   [%FP + 0]: FP
### Return address (preserved if needed):
###   [%FP + 4 / ra]
### Return value:
###   [a0]: If found, a pointer to the correct device table entry, otherwise, null.
### Locals:
###   [t0]: current_ptr  -- The current pointer into the device table.
###   [t1]: current_type -- The current entry's device type.
###   [t2]: none_type    -- The null device type code.

_procedure_find_device:

	## Prologue: Initialize the locals.
	lw		t0,		_static_device_table_base			# current_ptr = dt_base
	lw		t2,		_static_none_device_code			# none_type
	
find_device_loop_top:

	## End the search with failure if we've reached the end of the table without finding the device.
	lw		t1,		0(t0)						# current_type = current_ptr->type
	beq		t1,		t2,		find_device_loop_failure	# while (current_type == none_type) {

	## If this entry matches the device type we seek, then decrement the instance count.  If the instance count hits zero, then
	## the search ends successfully.
	bne		t1,		a0,		find_device_continue_loop	#   if (current_type == type) {
	addi		a1,		a1,		-1				#     instance--
	beqz		a1,		find_device_loop_success			#     if (instance == 0) break }
	
find_device_continue_loop:	

	## Advance to the next entry.
	addi		t0,		t0,		12				#   current_ptr++
	j		find_device_loop_top						# }

find_device_loop_failure:

	## Set the return value to a null pointer.
	li		a0,		0						# rv = null
	j		find_device_return

find_device_loop_success:

	## Set the return pointer into the device table that currently points to the given iteration of the given type.
	mv		a0,		t0						# rv = current_ptr
	## Fall through...
	
find_device_return:

	## Epilogue: Return
	ret
### ================================================================================================================================



### ================================================================================================================================
### Procedure: print
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: str_ptr -- A pointer to the beginning of a null-terminated string.
### Return address:
###   [ra / fp + 4]
### Return value:
###   <none>
### Preserved registers:
###   [fp -  4]: a0
###   [fp -  8]: s1
###   [fp - 12]: s2
###   [fp - 16]: s3
###   [fp - 20]: s4
###   [fp - 24]: s5
###   [fp - 28]: s6
### Locals:
###   [s1]: current_ptr        -- Pointer to the current position in the string.
###   [s2]: console_buffer_end -- The console buffer's limit.
###   [s3]: cursor_column      -- The current cursor column (always on the bottom row).
###   [s4]: newline_char       -- A copy of the newline character.
###   [s5]: cursor_char        -- A copy of the cursor character.
###   [s6]: console_width      -- The console's width.
	
_procedure_print:

	## Callee prologue: Push preserved registers.
	sw		ra,		4(fp)					# Preserve ra
	## fp = 0x00012ff8
	## sp = 0x00012fec
	addi		sp,		sp,		-28			# Push & preserve a0 / s[1-6]
	sw		a0,		-4(fp)
	sw		s1,		-8(fp)
	sw		s2,		-12(fp)
	sw		s3,		-16(fp)
	sw		s4,		-20(fp)
	sw		s5,		-24(fp)
	sw		s6,		-28(fp)

	## Initialize locals.
	mv		s1,		a0					# current_ptr = str_ptr
	lw		s2,		_static_console_limit			# console_limit
	addi		s2,		s2,		-4			# console_buffer_end = console_limit - |word| (offset portal)
	lw		s3,		_static_cursor_column			# cursor_column
	lb		s4,		_string_newline_char
	lb		s5,		_string_cursor_char
	lw		s6,		_static_console_width

	## Loop through the characters of the given string until the terminating null character is found.
_string_loop_top:
	lb		t0,		0(s1)					# [t0] current_char = *current_ptr

	## The loop should end if this is a null character
	beqz		t0,		_string_loop_end

	## Scroll without copying the character if this is a newline.
	beq		t0,		s4,		_print_scroll_call

	## Assume that the cursor is in a valid location.  Copy the current character into it.
	sub		t1,		s2,		s6			# [t0] = console[limit] - width
	add		t1,		t1,		s3			#      = console[limit] - width + cursor_column
	sb		t0,		0(t1)					# Display current char @t1.
	
	## Advance the cursor, scrolling if necessary.
	addi		s3,		s3,		1			# cursor_column++
	blt		s3,		s6,		_print_scroll_end       # Skip scrolling if cursor_column < width

_print_scroll_call:
	##   Caller prologue...
	sw		s3,		_static_cursor_column,		t6	# Store cursor_column
	addi		sp,		sp,		-8			# Push pfp / ra
	sw		fp,		0(sp)					# Preserve fp
	mv		fp,		sp					# Move fp
	##   Call...
	call		_procedure_scroll_console
	##   Caller epilogue...
	lw		fp,		0(sp)		   			# Restore fp
	addi		sp,		sp,		8			# Pop pfp / ra
	lw		s3,		_static_cursor_column			# Restore cursor_column, which may have changed

_print_scroll_end:
	## Place the cursor character in its new position.
	sub		t1,		s2,		s6			# [t1] = console[limit] - width
	add		t1,		t1,		s3			#      = console[limit] - width + cursor_column
	sb		s5,		0(t1)					# Display cursor char @t1.
	
	## Iterate by advancing to the next character in the string.
	addi		s1,		s1,		1
	j		_string_loop_top

_string_loop_end:
	## Callee Epilogue...
	##   Store cursor_column back into statics.
	sw		s3,		_static_cursor_column,		t6	# Store cursor_column (static)
	##   Pop and restore preserved registers, then return.
	lw		s6,		-28(fp)					# Restore & pop a0 / s[1-6]
	lw		s5,		-24(fp)
	lw		s4,		-20(fp)
	lw		s3,		-16(fp)
	lw		s2,		-12(fp)
	lw		s1,		-8(fp)
	lw		a0,		-4(fp)
	addi		sp,		sp,		28
	lw		ra,		4(fp)					# Restore ra
	ret
### ================================================================================================================================

	

### ================================================================================================================================
### Procedure: scroll_console
### Description: Scroll the console and reset the cursor at the 0th column.
### Preserved frame pointer:
###   [fp + 0]: pfp
### Parameters:
###   <none>
### Return address:
###   [fp + 4]
### Return value:
###   <none>
### Locals:
###   [t0]: console_buffer_end / console_offset_ptr
###   [t1]: console_width
###   [t2]: console_buffer_begin
###   [t3]: cursor_column
###   [t4]: screen_size	
	
_procedure_scroll_console:

	## Initialize locals.
	lw		t2,		_static_console_base			# console_buffer_begin = console_base
	lw		t0,		_static_console_limit			# console_limit
	addi		t0,		t0,		-4			# console_buffer_end = console_limit - |word| (offset portal)
	lw		t1,		_static_console_width			# console_width
	lw		t3,		_static_cursor_column			# cursor_column
	lw		t4,		_static_console_height			# t4 = console_height
	mul		t4,		t1,		t4			# screen_size = console_width * console_height
	
	## Blank the top line.
	lw		t5,		_static_device_table_base               # t5 = dt_controller_ptr
	lw		t5,		8(t5)					#    = dt_controller_ptr->limit
	addi		t5,		t5,		-12			# DMA_portal_ptr = dt_controller_ptr->limit - 3*|word|
	la		t6,		_string_blank_line			# t6 = &blank_line
	sw		t6,		0(t5)					# DMA_portal_ptr->src = &blank_line
	sw		t2,		4(t5)					# DMA_portal_ptr->dst = console_buffer_begin
	sw		t1,		8(t5)					# DMA_portal_ptr->len = console_width

	## Clear the cursor if it isn't off the end of the line.
	beq		t1,		t3,		_scroll_console_update_offset	# Skip if width == cursor_column
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width
	add		t5,		t5,		t3			#    = console_buffer_end - width + cursor_column
	lb		t6,		_string_space_char
	sb		t6,		0(t5)

	## Update the offset, wrapping around if needed.
_scroll_console_update_offset:
	lw		t6,		0(t0)					# [t6] offset
	add		t6,		t6,		t1			# offset += column_width
	rem		t6,		t6,		t4			# offset %= screen_size
	sw		t6,		0(t0)					# Set offset in console
	
	## Reset the cursor at the start of the new line.
	li		t3,		0					# cursor_column = 0
	sw		t3,		_static_cursor_column,		t6	# Store cursor_column
	lb		t6,		_string_cursor_char			# cursor_char
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width (cursor_column == 0)	
	sb		t6,		0(t5)
	
	## Return.
	ret
### ================================================================================================================================


### ================================================================================================================================
### Procedure : _syscall_print
### Parameters:
### 	[a0] -> syscall code
###		[a1] -> virtual_addr of the string to print
### 	[a2] -> length of string to print
_syscall_print:
	## save the locals on the stack
	addi sp, sp, -12 # create stack space
	sw a0, 8(sp) 	# syscall code M[sp + 8] = a0
	sw a1, 4(sp) 	# virt_addr M[sp + 4] = a1
	sw a2, 0(sp) 	# length M[sp] = a2

	# add base to a0
	csrr a0, 5
	add a0, a0, a1 		# base + virt_addr
	# call procedure print
	call _procedure_print

	## restore the registers
	lw a0, 8(sp)
	lw a1, 4(sp)
	lw a2, 0(sp)

### ================================================================================================================================


### ================================================================================================================================
### Procedure: _procedure_syscall_handler
### Parameters:
###		[a6] -> holds exit_code
### Locals:
### 	[a7] -> load necessary exit codes to check
### syscalls
### _static_syscall_exit_code : 0xabcd0001 -> exit
### _syscall_exit_program: 0xabcd0002 -> print (expects syscall code [a0], virt_addr [a1], length [a2])
_procedure_syscall_handler:
	# load the kernel sp
	la t0, _static_kernel_sp
	lw sp, 0(t0)

	## check if the value of reg a6 == 0x80
	lw a7, _static_syscall_exit_code
	xor a7, a7, a6 # a7 = val(a6) ^ 0xabcd0001 (exit code)
	beqz a7, _syscall_exit_program

	lw a7, _static_syscall_print_code
	xor a7, a7, a6 # a7 = val(a6) ^ 0xabcd0001 (exit code)
	beqz a7, _syscall_print
	

	halt
_syscall_exit_program:
	# print exiting program successfully.
	la a0, _string_exit_program_success
	call _procedure_print

	la ra, _procedure_jump_to_ROM
	ret

### ================================================================================================================================

### ================================================================================================================================
### Procedure: default_handler

_procedure_default_handler:

	# retrieve sp from statics
	lw sp, _static_kernel_sp

	lw		a0,		_static_kernel_error_unmanaged_interrupt
	halt
### ================================================================================================================================

### ================================================================================================================================
### Procedure save user programs in eai (interrupt buffer)
### Parameters:
### 	[pc] : user_pc
### 	[sp] : user_sp
_procedure_save_interrupt_buffer:
		# save interrupt buffer info?

		ret
### ================================================================================================================================


	
### ================================================================================================================================
### Procedure: init_trap_table
### Caller preserved registers:	
###   [fp + 0]:      pfp
###   [ra / fp + 4]: pra
### Parameters:
###   <none>
### Return value:
###   <none>
### Callee preserved registers:
###   <none>
### Locals:
###   <none>

_procedure_init_trap_table:

	## WRITE THIS PROCEDURE

	# load the address of the label (default handler) into the register
	la t0, _procedure_default_handler
	# load address of static_trap_table into register t1
	la t1, _static_trap_table
	sw t0,  0(t1)
	sw t0,  4(t1)
	sw t0,  8(t1)
	sw t0, 12(t1)
	sw t0, 16(t1)
	sw t0, 20(t1)
	sw t0, 24(t1)  
	sw t0, 28(t1)  
	sw t0, 32(t1)
	la t0, _procedure_syscall_handler  
	sw t0, 36(t1)  
	la t0, _procedure_default_handler
	sw t0, 40(t1)  
	sw t0, 44(t1)  

	# set trap base
	csrw t1, 2
	# set interrupt buffer
	la t1, _static_interrupt_buffer
	csrw t1, 4
	ret
	
### ================================================================================================================================


	
### ================================================================================================================================
### Procedure: main
### Preserved registers:
###   [fp + 0]:      pfp
###   [ra / fp + 4]: pra
### Parameters:
###   <none>
### Return value:
###   [a0]: exit_code
### Preserved registers:
###   <none>
### Locals:
###   <none>

_procedure_main:

	# Callee prologue
	sw		ra,		4(fp)						# Preserve ra

	# Call find_device() to get console info.
	lw		a0,		_static_console_device_code			# arg[0] = console_device_code
	li		a1,		1						# arg[1] = 1 (first instance)
	addi		sp,		sp,		-8				# Push pfp / ra
	sw		fp,		0(sp)						# Preserve fp
	mv		fp,		sp						# Update fp
	call		_procedure_find_device						# [a0] rv = dt_console_ptr
	bnez		a0,		main_with_console				# if (dt_console_ptr == NULL) ...
	lw		a0,		_static_kernel_error_console_not_found		# Return with failure code
	j		main_return

main_with_console:
	# Copy the console base and limit into statics for later use.
	lw		t0,		4(a0)						# [t0] dt_console_ptr->base
	sw		t0,		_static_console_base,		t6
	lw		t0,		8(a0)						# [50] dt_console_ptr->limit
	sw		t0,		_static_console_limit,		t6
	
	# Call print() on the banner and attribution.  (Keep using caller subframe...)
	la		a0,		_string_banner_msg				# arg[0] = banner_msg
	call		_procedure_print
	la		a0,		_string_attribution_msg				# arg[0] = attribution_msg
	call		_procedure_print

	# Call init_trap_table(), then finally restore the frame.
	la		a0,		_string_initializing_tt_msg			# arg[0] = initializing_tt_msg
	call		_procedure_print
	call		_procedure_init_trap_table
	la		a0,		_string_done_msg				# arg[0] = done_msg
	call		_procedure_print
	
	
	lw		fp,		0(sp)						# Restore fp
	addi		sp,		sp,		8				# Pop pfp / ra

## find the place we write the ROM then store it in a static
_procedure_find_ROM_dest:
	## get the RAM
	lw a0, _static_RAM_device_code
	addi a1, zero, 1
	call _procedure_find_device
	
	# create the space where user programs should begin
	lw a2, _static_kernel_size # where RAM space ends.
	# addi a4, a2, 0x100 # add buffer #a4 = 0.5(RAM_size) + buffer (dest for ROM)
	lw  a0,  1(a0) # add this to the beginning of ram
	add a0, a0, a4 # a0 += a4 add the RAM_begin + 0.5(RAM_size) + buffer
	# store dest in statics
	la t0, _static_ROM_destination
	sw a0, 0(t0) # store it in rom dest.

### Procedure: Jump To Rom
### Preserved registers: None
### Parameters:
### 	_static_ROM_device_code: device code
### 	_static_ROM_instance_count: number of ROM we want.
### sp + 4 =  instance of device
### sp + 8 = destination of next copy
### Return value:
###   [a0]: _static_kernel_normal_exit
### Preserved registers:
###   <none>
### Locals:
### t1 = src_ptr
### a2 = dst_ptr
### t0 = length (trigger) 


_procedure_jump_to_ROM:
	### retrieve val from stack
	lw a0, _static_ROM_device_code # a0 = constant of device
	lw a1, _static_ROM_instance_count # a1 = rom isntance count

	call _procedure_find_device
	beqz a0, exit_kernel

	### calculate size of found device 
	addi a0, a0, 1 # increment by 1 (location of the start ptr to kernel (2nd rom))
	lw t1, 0(a0) # a0 => start ptr to kernel
	lw t2, 4(a0) # load value in t2 = M[a0 + 4] # end of device
	lw t1, 0(a0) # load value in t1 = M[a0] # beginning of device
	sub t0, t2, t1
	add s4, t0, zero # store length of program in s4
	
	lw a2, _static_ROM_destination # a2 = destination of copy

	## perform dma copy.
	lw		t4,		_static_device_table_base       # t4 = dt_controller_ptr
	lw		t3,		8(t4)					# t3 = dt_controller_ptr->limit
	addi	t3,		t3,		-12			# DMA_portal_ptr = dt_controller_ptr->limit - 3*|word|

	## Copy the source, destination, and length into the portal.  The last step triggers the DMA copy.
	sw		t1,		0(t3)					# DMA->source      = src_ptr
	sw		a2,		4(t3)					# DMA->destination = dst_ptr
	sw		t0,		8(t3)					# DMA->length      = length (trigger)
	

	# load device instance
	la t1, _static_ROM_instance_count # a1 = M[sp + 4] # instance of device
	lw a1, 0(t1)
	addi a1, a1, 1 # increment it by 1
	sw a1, 0(t1) # store it back on the stack


	# initialize stack for user program
	# save the current sp in text statics
	la a0, _static_kernel_sp
	sw sp, 0(a0)

	# intialize new stack for user program

	## get the RAM
	lw a0, _static_RAM_device_code
	addi a1, zero, 1
	call _procedure_find_device

	lw sp, 2(a0) # end of RAM

	# base
	csrw a2, 5 # set base 
	# limit
	add s4, a2, s4
	csrw s4, 6
	

	##  put dest in ra
	csrw zero, 3
	## enable virtual addressing
	# read the mode into t0
	ori t0, zero, 4
	csrw t0, 1
	
	eret

	# Do something that causes an interrupt!
	div		t0,		t0,		zero				# Divide by zero!
exit_kernel:
	## print procedure.
	la a0, _string_exit_kernel_success
	call _procedure_print

	# Callee epilogue: If we reach here, end the hernel.
	lw		a0,		_static_kernel_normal_exit			# Set the result code
	halt
main_return:	
	lw		ra,		4(fp)						# Restore ra
	ret
### ================================================================================================================================
	

	
### ================================================================================================================================
	.Numeric

	## A special marker that indicates the beginning of the statics.  The value is just a magic cookie, in case any code wants
	## to check that this is the correct location (with high probability).
_static_statics_start_marker:	0xdeadcafe
_static_trap_table: 0 0 0 0 0 0 0 0 0 0 0 0
_static_interrupt_buffer: 0 0

	## Device table location and codes.
_static_device_table_base:	0x00001000
_static_none_device_code:	0
_static_controller_device_code:	1
_static_ROM_device_code:	2
_static_RAM_device_code:	3
_static_console_device_code:	4
_static_block_device_code:	5

	## Error codes.
_static_kernel_normal_exit:			0xffff0000
_static_kernel_error_RAM_not_found:		0xffff0001
_static_kernel_error_small_RAM:			0xffff0002	
_static_kernel_error_console_not_found:		0xffff0003
_static_kernel_error_unmanaged_interrupt:	0xffff0004

	### Syscall codes
_static_syscall_exit_code: 0xabcd0001
_static_syscall_print_code: 0xabcd0002
	
	## Constants for printing and console management.
_static_console_width:		80
_static_console_height:		24

	## Other constants.
_static_min_RAM:		0x10000 # 64 KB = 0x40 KB * 0x400 B/KB
_static_bytes_per_page:		0x1000	# 4 KB/page
_static_kernel_size:		0x8000	# 32 KB = 0x20 KB * 0x4 B/KB taken by the kernel.

	## Statically allocated variables.
_static_cursor_column:		0	# The column position of the cursor (always on the last row).
_static_RAM_base:		0
_static_RAM_limit:		0
_static_console_base:		0
_static_console_limit:		0
_static_kernel_base:		0
_static_kernel_limit:		0
_static_kernel_sp: 	0
	### Variables needed so kernel can run next ROM
_static_ROM_instance_count: 3
_static_ROM_destination: 0
_static_user_sp: 0
_static_user_pc: 0
### ================================================================================================================================



### ================================================================================================================================
	.Text

_string_space_char:		" "
_string_cursor_char:		"_"
_string_newline_char:		"\n"
_string_banner_msg:		"Fivish kernel r1 2024-02-07\n"
_string_attribution_msg:	"COSC-277 : Operating Systems\n"
_string_halting_msg:		"Halting kernel..."
_string_initializing_tt_msg:	"Initializing trap table..."
_string_exit_program_success: "Exited Program\n"
_string_handling_syscall: "Handling syscall\n"
_string_exit_kernel_success: "Exited Kernel Successfully\n"
_string_syscall_error: "Error while executing syscall\n"
_string_done_msg:		"done.\n"
_string_failed_msg:		"failed!\n"
_string_blank_line:		"                                                                                "
### ================================================================================================================================
