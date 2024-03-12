# complete a kernel

## [Project 1](https://sfkaplan.people.amherst.edu/courses/2024/spring/COSC-277/assignments/project-1.pdf)

Using the bios from project-0, complete the bios to achieve the following:

### Handle interrupts.

1. **Create and initialize a trap table**: When the kernel begins execution, it should create and set the entries of a trap table. (See Chapter 4 of the Fivish documentation for details on each interrupt.) You may, initially, have all of the entries point to default_handler().

2. **Set the CPU to handle interrupts**: Set the processor’s TBR with the base address of the trap table, and its IBR with the base address of the interrupt buffer. Then test your code to be sure that interrupts trigger a vector to a handler function.

3. Change the system call handler: Write a new procedure meant to handle system calls. The SYSTEM_CALL interrupt should be redirected to this procedure, which should print a message to the console before halting. We will expand this procedure later.

### Create a process.

1. Load the first program: The kernel should find the third ROM—that is, the first user program—and load its contents into a free portion of main memory.

2. Execute the program: Jump from the kernel to the beginning of the loaded user program. This program must execute in user mode (in contrast to the supervisor mode in which the kernel executes).

3. Implement the EXIT system call: The SYSTEM_CALL interrupt should be handled by code that examines a chosen register that contains a system call code. Assign some constant to be the code for the EXIT syscall. The syscall handler should examine this location, determine if an EXIT was requested, and then do it. That is, end the program’s execution by printing a message and then…

4. Execute a sequence of user programs: After one user program properly exits, find the next ROM that holds a user program, and then load and execute that one. When there are no more ROMs, the kernel should print a message and then halt with a success code.