### ================================================================================================================================
### bios.asm
###
### The Basic Input/Output System (BIOS).  A ROM that provides the initial sequence of instructions when the CPU is reset.  It
### performs the following tasks:
###
### 	(1) Find RAM in the device table.
###	(2) Find the 2nd ROM (presumed to the be the kernel) in the device table.
###	(3) Copy the kernel into RAM.
###	(4) Jump to the kernel in RAM.
### ================================================================================================================================



### ================================================================================================================================
	.Code
### ================================================================================================================================



### ================================================================================================================================
### Initial stub.  No stack yet exists, so this specialized starting code must configure the system for that.
	
__start:	
	## Find RAM.  Start the search at the beginning of the device table.
	lw		t0,		device_table_base			# [t0] dt_current = &device_table[0]
	lw		s0,		none_device_code			# [s0] none_device_code
	lw		s1,		RAM_device_code				# [s1] RAM_device_code
	lw		s2,		dt_entry_size				# [s2] dt_entry_size
	
RAM_search_loop_top:

	## End the search with failure if we've reached the end of the table without finding RAM.
	lw		t1,		0(t0) 					# [t1] device_code = dt_current->type_code
	beq		t1,		s0,		RAM_search_failure 	# if (device_code == none_device_code)

	## If this entry is RAM, then end the loop successfully.
	beq		t1,		s1,		RAM_found 		# if (device_code == RAM_device_code)

	## This entry is not RAM, so advance to the next entry.
	add		t0,		t0,		s2 			# [t0] dt_current += dt_entry_size
	j		RAM_search_loop_top

RAM_search_failure:

	## Record a code to indicate the error, and then halt.
	lw		a0,		RAM_search_failure_code                 # [a0] RAM_search_failure_code
	halt

RAM_found:
	
	## RAM has been found.  Initialize the stack at the limit of RAM.
	lw		sp,		8(t0) 					# [sp] dt_current->limit

	## Create an ad-hoc statics region at the top of the stack, above the first frame, with gp marking its base.
	##   [gp + 0]: dt_console_ptr
	##   [gp + 4]: console_cursor_column
	addi		sp,		sp,		-8			# Allocate statics region
	mv		gp,		sp					# [gp] Statics region base
	sw		zero,		0(gp)					# dt_console_ptr      = 0
	sw		zero,		4(gp)					# console_cursor_column = 0
	
	## With the stack initialized, call main() to begin booting proper.  Pass the base of RAM.
	mv		fp,		sp		  			# Initialize fp = sp
	addi		sp,		sp,		-8 			# Push space for ra, pfp
	mv		a0,		t0		                 	# arg[0] = &dt[RAM]
	sw		fp,		0(sp)		 			# pfp = fp (preserve)
	mv		fp,		sp					# Update fp
	call		_procedure_main

	## We should never be here, but wrap it up properly.
	lw		fp,		0(sp) 					# fp = pfp (restore)
	addi		sp,		sp,		8	                # Pop pfp / ra
	halt
### ================================================================================================================================

	

### ================================================================================================================================
### Procedure: main
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: dt_RAM_ptr (A pointer to the device table entry for RAM)
### Return address:
###   [a0 / fp + 4]
### Return value:
###   <none>
### Locals:
###   [s1]: dt_kernel_ptr (Kernel ROM device table entry pointer)
### Preserved registers:
###   [fp - 4]: a0
###   [fp - 8]: s1
### Perform the primary tasks of the BIOS:
###   (a) Find the ROM that contains the kernel.
###   (b) Copy the kernel into RAM.
###   (c) Vector into the kernel for its initialization.

_procedure_main:

	## Callee prologue: Set up callee subframe.
	sw		ra,		4(fp)				# Preserve the return address
	addi		sp,		sp,		-8		# Allocate preserved register space
	sw		a0,		-4(fp)		    		# Preserve a0
	sw		s1,		-8(fp)				# Preserve s1

	## Find the console and set the static pointer to its entry.
	##   Caller prologue...
	addi		sp,		sp,		-8 		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	lw		a0,		console_device_code  		# arg[0] = console_code
	li		a1,		1 				# arg[1] = 1 (find 1st instance of the console)
	##   Call...
	call		_procedure_find_device 				# rv = &dt[console]
	##   Caller epilogue...
	sw		a0,		0(gp)				# dt_console_ptr = rv
	lw		fp,		0(sp)				# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra
	beqz		a0,		_main_fail	   		# Fail if a null pointer was returned
	
	## Print the opening messages and then stage1.
	##   Caller prologue...
	addi		sp,		sp,		-8 		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	la		a0,		banner_msg			# arg[0] = &banner
	##   Call...
	call		_procedure_print
	##   Re-use frame and call #2...
	la		a0,		copyright_msg	  		# arg[0] = &copyright
	call		_procedure_print
	##   Re-use frame and call #3...
	la		a0,		stage1_msg 			# arg[0] = &stage1
	call		_procedure_print
	##   Caller epilogue...
	lw		fp,		0(sp)		   		# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra
	
	## (a) Find the ROM that contains the kernel.
	##   Caller prologue...
	addi		sp,		sp,		-8 		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	lw		a0,		ROM_device_code			# arg[0] = ROM_device_code
	li		a1,		2				# arg[1] = 2 (find 2nd instance of ROM)
	##   Call...
	call		_procedure_find_device
	##   Caller epilogue...
	lw		fp,		0(sp)		   		# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra
	mv		s1,		a0				# dt_kernel_ptr = rv
	beqz		s1,		_main_fail	   		# Fail if a null pointer was returned

	## Complete printing previous stage1 message and print the lead to stage2.
	##  Caller prologue...
	addi		sp,		sp,		-8 		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	la		a0,		stage_end_msg			# arg[0] = &stage_end
	##  Call...
	call		_procedure_print
	##  Re-use frame and call #2...
	la		a0,		stage2_msg	  		# arg[0] = &stage2
	call		_procedure_print
	##  Caller epilogue
	lw		fp,		0(sp)		   		# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra

	## (b) Copy the kernel into RAM.
	##   Caller prologue...
	mv		a0,		s1		   		# arg[0] = dt_kernel_ptr
	lw		a1,		-4(fp)		   		# arg[1] = dt_RAM_ptr
	addi		sp,		sp,		-8		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	##   Call...
	call		_procedure_copy_kernel
	##   Caller epilogue...
	lw		fp,		0(sp)		   		# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra
	
	## Complete printing previous stage2 message and print the lead to stage3.
	##  Caller prologue...
	addi		sp,		sp,		-8 		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	la		a0,		stage_end_msg			# arg[0] = &stage_end
	##  Call...
	call		_procedure_print
	##  Re-use frame and call #2...
	la		a0,		stage3_msg	  		# arg[0] = &stage3
	call		_procedure_print
	##  Caller epilogue
	lw		fp,		0(sp)		   		# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra

	## (c) Vector into the kernel.
	lw		a0,		-4(fp)		    		# Restore a0 (dt_RAM_ptr)
	lw		t0,		4(a0)				# [t0] dt_RAM_ptr->base
	jr		t0						# Jump to dt_RAM_ptr->base
	
	## Callee epilogue (which should never happen)...
	lw		s1,		-8(fp)				# Restore s1
	addi		sp,		sp,		8 		# Pop preserved register space
	lw		ra,		4(fp)		  		# Restore ra
	ret

_main_fail:	
	## Print an error message and halt upon failure.
	##   Caller prologue...
	addi		sp,		sp,		-8		# Push pfp / ra
	sw		fp,		0(sp)				# Preserve fp
	mv		fp,		sp				# Move fp
	la		a0,		stage_fail_msg			# arg[0] = &stage_fail_msg
	##   Call...
	call		_procedure_print
	##   Caller epilogue...
	lw		fp,		0(sp)				# Restore fp
	addi		sp,		sp,		8		# Pop pfp / ra
	halt
### ================================================================================================================================


	
### ================================================================================================================================
### Procedure: find_device
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: device_type -- The device type to find.
###   [a1]: instance    -- The instance of the given device type to find (e.g., the 3rd ROM).
### Return address:
###   [a0 / fp + 4]
### Return value:
###   [a0]: The address of the device table entry that matches the request null if no such entry is found.
### Locals:
###   [t0]: current          -- The current pointer into the device table.
###   [t1]: none_device_code -- The device type code for an empty device table entry.
###   [t2]: dt_entry_size    -- The size of each device table entry.	

_procedure_find_device:

	## Initialize locals.  (No callee subframe to create.)
	lw		t0,		device_table_base				# current = device_table_base
	lw		t1,		none_device_code
	lw		t2,		dt_entry_size
	
find_device_loop_top:

	## End the search with failure if we've reached the end of the table without finding the device.
	lw		t3,		0(t0) 						# t3 = current->type
	beq		t1,		t3,		find_device_loop_failure 

	## If this entry matches the device type we seek, then decrement the instance count.  If the instance count hits zero, then
	## the search ends successfully.
	bne		t3,		a0,		find_device_continue_loop	# Not the type sought
	addi		a1,		a1,		-1				# One fewer of this device to find
	beqz		a1,		find_device_loop_success			# And that was the last one to find!
	
find_device_continue_loop:	

	## Advance to the next entry.
	add		t0,		t0,		t2				# ++current
	j		find_device_loop_top

find_device_loop_failure:

	## Set the return value to a null pointer.
	mv		a0,		zero						# rv = 0 (null)
	j		find_device_return

find_device_loop_success:

	## Set the return pointer into the device table that currently points to the given iteration of the given type.
	mv		a0,		t0						# rv = current
	## Fall through...
	
find_device_return:

	## Return.
	ret
### ================================================================================================================================



### ================================================================================================================================
### Procedure: copy_kernel
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: dt_kernel_ptr -- A pointer to the kernel ROM's entry in the device table.
###   [a1]: dt_RAM_ptr    -- A pointer to RAM's (first) entry in the device table.
### Return address:
###   [a0 / fp + 4]
### Return value:
###    <none>
### Locals:

_procedure_copy_kernel:
	### YOUR WORK GOES HERE: COPY THE KERNEL INTO RAM.
    lw t0, 4(a0) # load the base addr of the second rom to t0
    lw t1, 4(a1) # load the base addr of the RAM into t1
    lw t2, 8(a0) # load the limit of the base addr of the ROM into t2
    sub s2, t2, t0 # (limit - base ) = size
_copy_kernel_loop_top:
    # difference in bytes size == 0
    beqz s2, _finish
    
    # load whatever is in t0 into s3
    # s3 = M[t0+0]
    lw s3, 0(t0)
    # move this value into M[t1]
    # M[t1+ 0] = s3
    sw s3, 0(t1)

    # increment t1, t0 by 4
    addi t1, t1, 4
    addi t0, t0, 4

    # decrement s2 by 4
    addi s2, s2, -4
    j _copy_kernel_loop_top

_finish:
    ret
### ================================================================================================================================



### ================================================================================================================================
### Procedure: print
### Preserved registers:
###   [fp + 0]: pfp
### Parameters:
###   [a0]: str_ptr -- A pointer to the beginning of a null-terminated string.
### Return address:
###   [a0 / fp + 4]
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
	lw		s2,		0(gp)					# s2 = dt_console_ptr (static)
	lw		s2,		8(s2)					#   = dt_console_ptr->limit
	addi		s2,		s2,		-4			# console_buffer_end = console_limit - |word| (offset portal)
	lw		s3,		4(gp)					# cursor_column (static)
	lb		s4,		newline_char
	lb		s5,		cursor_char
	lw		s6,		console_width

	## Loop through the characters of the given string until the terminating null character is found.
_string_loop_top:
	lb		t0,		0(s1)					# t0 = current_char = *current_ptr

	## The loop should end if this is a null character
	beqz		t0,		_string_loop_end

	## Scroll without copying the character if this is a newline.
	beq		t0,		s4,		_print_scroll_call

	## Assume that the cursor is in a valid location.  Copy the current character into it.
	sub		t1,		s2,		s6			# t1 = console[limit] - width
	add		t1,		t1,		s3			#    = console[limit] - width + cursor_column
	sb		t0,		0(t1)					# Display current char @t1.
	
	## Advance the cursor, scrolling if necessary.
	addi		s3,		s3,		1			# cursor_column++
	blt		s3,		s6,		_print_scroll_end       # Skip scrolling if cursor_column < width

_print_scroll_call:
	##   Caller prologue...
	sw		s3,		4(gp)					# Store cursor_column (static)
	addi		sp,		sp,		-8			# Push pfp / ra
	sw		fp,		0(sp)					# Preserve fp
	mv		fp,		sp					# Move fp
	##   Call...
	call		_procedure_scroll_console
	##   Caller epilogue...
	lw		fp,		0(sp)		   			# Restore fp
	addi		sp,		sp,		8			# Pop pfp / ra
	lw		s3,		4(gp)					# Restore cursor_column (static), which may have changed

_print_scroll_end:
	## Place the cursor character in its new position.
	sub		t1,		s2,		s6			# t1 = console[limit] - width
	add		t1,		t1,		s3			#    = console[limit] - width + cursor_column
	sb		s5,		0(t1)					# Display cursor char @t1.
	
	## Iterate by advancing to the next character in the string.
	addi		s1,		s1,		1
	j		_string_loop_top

_string_loop_end:
	## Callee Epilogue...
	##   Store cursor_column back into statics.
	sw		s3,		4(gp)					# Store cursor_column (static)
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
	lw		t5,		0(gp)					# [t5] dt_console_ptr (static)
	lw		t2,		4(t5)					# console_buffer_begin = dt_console_ptr->base
	lw		t0,		8(t5)					# [t0] dt_console_ptr->limit
	addi		t0,		t0,		-4			# console_buffer_end = console_limit - |word| (offset portal)
	lw		t1,		console_width				# console_width
	lw		t3,		4(gp)					# cursor_column
	lw		t4,		console_height				# t4 = console_height
	mul		t4,		t1,		t4			# screen_size = console_width * console_height
	
	## Blank the top line.
	lw		t5,		device_table_base                       # t5 = dt_controller_ptr
	lw		t5,		8(t5)					#    = dt_controller_ptr->limit
	addi		t5,		t5,		-12			# DMA_portal_ptr = dt_controller_ptr->limit - 3*|word|
	la		t6,		blank_line				# t6 = &blank_line
	sw		t6,		0(t5)					# DMA_portal_ptr->src = &blank_line
	sw		t2,		4(t5)					# DMA_portal_ptr->dst = console_buffer_begin
	sw		t1,		8(t5)					# DMA_portal_ptr->len = console_width

	## Clear the cursor if it isn't off the end of the line.
	beq		t1,		t3,		_scroll_console_update_offset	# Skip if width == cursor_column
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width
	add		t5,		t5,		t3			#    = console_buffer_end - width + cursor_column
	lb		t6,		space_char
	sb		t6,		0(t5)

	## Update the offset, wrapping around if needed.
_scroll_console_update_offset:
	lw		t6,		0(t0)					# [t6] offset
	add		t6,		t6,		t1			# offset += column_width
	rem		t6,		t6,		t4			# offset %= screen_size
	sw		t6,		0(t0)					# Set offset in console
	
	## Reset the cursor at the start of the new line.
	li		t3,		0					# cursor_column = 0
	sw		t3,		4(gp)					# Store cursor_column (static)
	lb		t6,		cursor_char				# [t6] cursor_char
	sub		t5,		t0,		t1			# t5 = console_buffer_end - width (cursor_column == 0)	
	sb		t6,		0(t5)
	
	## Return.
	ret
### ================================================================================================================================


	
### ================================================================================================================================
	.Numeric

	## Device table location and codes.
device_table_base:	0x00001000
dt_entry_size:		12
none_device_code:	0
controller_device_code:	1
ROM_device_code:	2
RAM_device_code:	3
console_device_code:	4

	## Error codes.
RAM_search_failure_code:	0xffff0001

	## Constants for printing and console management.
console_width:		80
console_height:		24

### ================================================================================================================================


	
### ================================================================================================================================
	.Text

space_char:	" "
cursor_char:	"_"
newline_char:	"\n"
banner_msg:	"RISC-Fivish-System BIOS r1 2023-12-17\n"
copyright_msg:	"(c) Scott F. Kaplan / sfkaplan@amherst.edu\n"
stage1_msg:	"  Searching device table for kernel..."
stage2_msg:	"  Copying kernel into RAM..."
stage3_msg:	"  Vectoring into kernel.\n"
stage_end_msg:	"done.\n"
stage_fail_msg:	"failed!  Halting now.\n"
blank_line:	"                                                                                "
### ================================================================================================================================
