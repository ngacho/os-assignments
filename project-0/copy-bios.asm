# code that copies the second ROM (bios) into the RAM then jumps into the base of the ram
    .Code
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
_start:
    lw a0, dt_kernel_ptr
    lw a1, dt_RAM_ptr
    call procedure_copy_kernel
    lw a1, 4(a1)
    jalr zero, 0(a1) 
    halt

procedure_copy_kernel:
    lw t0, 4(a0) # load the base addr of the second rom to t0
    lw t1, 4(a1) # load the base addr of the RAM
    lw t2, 8(a0) # load the limit of the base addr of the ROM
    sub s2, t2, t0 # (limit - base ) = size
_start_copy:
    # difference in bytes (stop when t1 = t2)
    beqz s2, _finish
    
    # load whatever is in t0 into s3
    # s3 = M[t0+0]
    lw s3, 0(t0)
    # move this value into 
    # M[t1+ 0] = s3
    sw s3, 0(t1)

    # increment t1, t0 by 4
    addi t1, t1, 4
    addi t0, t0, 4

    # decrement s2 by 4
    addi s2, s2, -4
    j _start_copy

_finish:
    ret



    .Numeric

# device table entry (addr to 2nd ROM aka Kerenl)
dt_kernel_ptr: 0x00001024
# device table entry for (addr to RAM)
dt_RAM_ptr: 0x0000100c

