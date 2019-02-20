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

## TODOS:
* Automatic thread-switching after unlock if a switch was missed
* Smarter malloc
* Dynamic thread-count updating
* Faster thread-switching
* Runtime thread-instruction variability
* Main-thread exiting (auto dsleep)

## Tested platforms:
* Tiva C-series
    * TM4C123GH6PM (Evaluation board: TM4C123GXL)