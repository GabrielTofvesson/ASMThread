# Mutlithreading for the Tiva C series
This project is a PoC of an ASM multithreading implementation for ARM Thumb
devices.

## Project contents:
* Threading          (pthread.asm)
    * Start thread:  (threadstart)
    * Stop thread:   (threadexit)
    * Thread fencing:
        * Lock       (threadlock)
        * Unlock     (threadunlock)
* Memory management: (malloc.asm)
    * Malloc_init:   (minit)
    * Malloc:        (gtmalloc)
    * Free:          (free)
    * Memcpy:        (memcpy)
    * Memset:        (memset)

## Some notes:
To make use of threading, malloc has to be enabled (to store a thread's stack).
To enable malloc, simply call *minit*. This prepares the first element in the
double-linked list to cover the entire 32KiB heap aside from the memory
allocated for the stack.

The threading system uses the built-in SysTick system to determine how many
instructions each thread is delegated before a thread-switch operation is
triggered. The amount of instructions allowed can be set by changing the
constant *STRST*.

Thread fencing allows a thread to request extra time-frames for itself. As it
stands at the moment, thread-fencing will always be allowed, since it was
designed as a way to making thread-unsafe operations virtually atomic. I would
be **very** hesitant to use thread-fencing, since, if timed incorrectly in, for
example an infinite loop, it could cause the thread to inexplicably take full
control of the processor by always being fenced when a thread-switch is
triggered, thus preventing any switches. This is why I would heavily reccomend
manually setting the SysTick timer value to 0 after unlocking: so that a
successful thread-switch is attempted (in case one was missed when the thread
was locked).

**SPECIAL NOTE:** The main thread _cannot_ be exited! If you think about it,
it would be unreasonable that the main thread should be exited, since there
would be nowhere for the thread-switcing routine to return to. As such, the
main thread will simply branch to an infinite loop when it calls *threadexit*.
In the future, I hope to implement a flag that declares the main thread as
exited, in which case it is skipped until all other threads have exited. If all
threads have exited, the threading system should reasonably be disabled and the
processor should probably be put into deepsleep indefinitely.

## Thread design:

### Thread flags:

These bits should _under no circumstances_ be set manually. To change them,
call the relevant exported routines.
From LSB to MSB, the thread flag bits are as follows:

    **0:** Thread lock (set to lock, clear to unlock)
    **1:** Thread exit (set to inform thread-switch routine that thread should be killed)
    **2-7:** Reserved

### Thread frame:

Currently, the thread frame system consists of a single component: a pointer.
The pointer points to the thread stack data. When a thread is first started, it
contains (at least) a complete register mapping. The default mapping is that
all registers except *PC*, *PSR* and *SP* are set to *0*. *PC* is set to the
relevant execution address and *PSR* is set to *0x81000000*. On top of the
stack data, the pointer also contains the relevant stack pointer address at the
lowest address pointed to by the frame. The default value for the stack-pointer
is *STACK_BASE - 0x40*: this because it fits the entirety of the default
register values. When the SysTick ISR exits back to the thread, all registers
are popped into their respective registers, as such, a fresh thread's *SP* will
have the value *STACK_BASE*.

### Threading with other interrupts:

As it stands, thread-switching will be postponed in the case that it is
triggered during another ISR. As such, it is important that the system doesn't
have large amounts of interrupts, as this may impede thread-switching.

You may ask why another ISR should prevent thread-switching. Well, we cannot
trigger a thread-switch in an ISR, since that would mean that the thread
switched to would be considered to be a part of said ISR by the processor,
as such the thread would inherently prevent lower-priority interrupts from
being triggered. Additionally, we cannot be sure how large the ISRs stack is,
so there would be no way of replacing the underlying thread's stack without
potentially affecting (or destroying) the ISRs stack.

A possible solution to this would be to include a flag for ISRs to check if
they blocked a thread-switch and thus allowing ISRs to manually switch threads
ad hoc if SysTick wasn't able to. This would additionally solve the problem
of nested interrupts preventing thread-switching, since the switch would be
delegated to the interrupt of lowest priority (i.e. the one that would
otherwise return to the thread).

## TODOS:
* Automatic thread-switching after unlock if a switch was missed
* Smarter malloc
* Dynamic thread-count updating
* Faster thread-switching
* Runtime thread-instruction variability
* Main-thread exiting (auto dsleep)
* ISR-friendly thread-switching solution
* Thread-yielding (manual thread-switch trigger)

## Tested platforms:
* Tiva C-series
    * TM4C123GH6PM (Evaluation board: TM4C123GXL)
