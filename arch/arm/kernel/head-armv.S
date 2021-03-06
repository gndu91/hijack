/*
 * linux/arch/arm/kernel/head-armv.S
 *
 * Copyright (C) 1994-1999 Russell King
 *
 * 32-bit kernel startup code for all architectures
 */
#include <linux/config.h>
#include <linux/linkage.h>

#include <asm/assembler.h>

#if (TEXTADDR & 0xffff) != 0x8000
#error TEXTADDR must start at 0xXXXX8000
#endif

#define SWAPPER_PGDIR_OFFSET	0x4000

		.globl	SYMBOL_NAME(swapper_pg_dir)
		.equ	SYMBOL_NAME(swapper_pg_dir),	TEXTADDR - 0x8000 + SWAPPER_PGDIR_OFFSET

		.section ".text.init",#alloc,#execinstr
ENTRY(stext)
ENTRY(_stext)

#ifdef CONFIG_ARCH_NETWINDER
/*
 * Compatability cruft for old NetWinder NeTTroms.  This
 * code is currently scheduled for destruction in 2.5.xx
 */
		.rept	8
		mov	r0, r0
		.endr

		adr	r2, 1f
		ldmdb	r2, {r7, r8}
		and	r3, r2, #0xc000
		teq	r3, #0x8000
		beq	__entry
		bic	r3, r2, #0xc000
		orr	r3, r3, #0x8000
		mov	r0, r3
		mov	r4, #64
		sub	r5, r8, r7
		b	1f

		.word	_stext
		.word	__bss_start

1:
		.rept	4
		ldmia	r2!, {r6, r7, r8, r9}
		stmia	r3!, {r6, r7, r8, r9}
		.endr
		subs	r4, r4, #64
		bcs	1b
		movs	r4, r5
		mov	r5, #0
		movne	pc, r0

		mov	r0, #0
		mov	r1, #5
#endif

/*
 * Entry point.  Entry *must* be called with r0 == 0, with the MMU off.
 *  r1 contains the unique architecture number.  See
 * linux/arch/arm/kernel/setup.c machine_desc[] array for the complete
 * list.  If you require a new number, please follow the instructions
 * given in Documentation/arm/README.
 */
__entry:	teq	r0, #0
		movne	r0, #'i'
		bne	__error
		bl	__lookup_processor_type
		teq	r10, #0				@ invalid processor?
		moveq	r0, #'p'
		beq	__error
		bl	__lookup_architecture_type
		teq	r7, #0				@ invalid architecture?
		moveq	r0, #'a'
		beq	__error
		bl	__create_page_tables
		adr	lr, __ret
		add	pc, r10, #12			@ flush caches (returns ctrl reg)

__switch_data:	.long	__mmap_switched
		.long	SYMBOL_NAME(__bss_start)
		.long	SYMBOL_NAME(_end)
		.long	SYMBOL_NAME(processor_id)
		.long	SYMBOL_NAME(__machine_arch_type)
		.long	SYMBOL_NAME(cr_alignment)
		.long	SYMBOL_NAME(init_task_union)+8192

__ret:		ldr	lr, __switch_data
		mcr	p15, 0, r0, c1, c0
		mov	r0, r0
		mov	r0, r0
		mov	r0, r0
		mov	pc, lr

		/*
		 * This code follows on after the page
		 * table switch and jump above.
		 *
		 * r0  = processor control register
		 * r1  = machine ID
		 * r9  = processor ID
		 */
		.align	5
__mmap_switched:
		adr	r3, __switch_data + 4
		ldmia	r3, {r4, r5, r6, r7, r8, sp}	@ Setup stack

		mov	fp, #0				@ Clear BSS
1:		cmp	r4, r5
		strcc	fp, [r4],#4
		bcc	1b

		str	r9, [r6]			@ Save processor ID
		str	r1, [r7]			@ Save machine type
#ifdef CONFIG_ALIGNMENT_TRAP
		orr	r0, r0, #2			@ ...........A.
#endif
		bic	r2, r0, #2			@ Clear 'A' bit
		stmia	r8, {r0, r2}			@ Save control register values
		b	SYMBOL_NAME(start_kernel)



/*
 * Setup the initial page tables.  We only setup the barest
 * amount which are required to get the kernel running, which
 * generally means mapping in the kernel code.
 *
 * We only map in 4MB of RAM, which should be sufficient in
 * all cases.
 *
 * r5 = physical address of start of RAM
 * r6 = physical IO address
 * r7 = byte offset into page tables for IO
 * r8 = page table flags
 */
__create_page_tables:
		add	r4, r5, #SWAPPER_PGDIR_OFFSET
		mov	r0, r4
		mov	r3, #0
		add	r2, r0, #0x4000			@ Clear page table
1:		str	r3, [r0], #4
		str	r3, [r0], #4
		str	r3, [r0], #4
		str	r3, [r0], #4
		teq	r0, r2
		bne	1b
		/*
		 * Create identity mapping for first MB of kernel.
		 * map in four sections (4MB) for kernel.
		 * these are marked cacheable and bufferable.
		 *
		 * The identity mapping will be removed by  paging_init()
		 */
		mov	r3, #0x0c
		orr	r3, r3, r8
		add	r3, r3, r5
		add	r0, r4, r5, lsr #18
		str	r3, [r0]
		add	r0, r4, #(TEXTADDR - 0x8000) >> 18
		str	r3, [r0], #4
		add	r3, r3, #1 << 20
		str	r3, [r0], #4
		add	r3, r3, #1 << 20
		str	r3, [r0], #4
		add	r3, r3, #1 << 20
		str	r3, [r0], #4
#ifdef CONFIG_DEBUG_LL
		/*
		 * Map in IO space for serial debugging.
		 * This allows debug messages to be output
		 * via a serial before paging_init.
		 */
		add	r0, r4, r7
		rsb	r3, r7, #0x4000 @ PTRS_PER_PGD*sizeof(long)
		cmp	r3, #0x0800
		addge	r2, r0, #0x0800
		addlt	r2, r0, r3
		orr	r3, r6, r8
1:		str	r3, [r0], #4
		add	r3, r3, #1 << 20
		teq	r0, r2
		bne	1b
#ifdef CONFIG_ARCH_NETWINDER
		teq	r1, #5
		bne	1f
		add	r0, r4, #0x3fc0
		mov	r3, #0x7c000000
		orr	r3, r3, r8
		str	r3, [r0], #4
		add	r3, r3, #1 << 20
		str	r3, [r0], #4
1:
#endif
#endif
#ifdef CONFIG_ARCH_RPC
		/*
		 * Map in screen at 0x02000000 & SCREEN2_BASE
		 * Similar reasons here - for debug.  This is
		 * only for Acorn RiscPC architectures.
		 */
		teq	r5, #0
		addne	r0, r4, #0x80			@ 02000000
		movne	r3, #0x02000000
		orrne	r3, r3, r8
		strne	r3, [r0]
		addne	r0, r4, #0x3600			@ d8000000
		strne	r3, [r0]
#endif
		mov	pc, lr



/*
 * Exception handling.  Something went wrong and we can't
 * proceed.  We ought to tell the user, but since we
 * don't have any guarantee that we're even running on
 * the right architecture, we do virtually nothing.
 * r0 = ascii error character
 *
 * Generally, only serious errors cause this.
 */
__error:
#ifdef CONFIG_ARCH_RPC
/*
 * Turn the screen red on a error - RiscPC only.
 */
		mov	r0, #0x02000000
		mov	r3, #0x11
		orr	r3, r3, r3, lsl #8
		orr	r3, r3, r3, lsl #16
		str	r3, [r0], #4
		str	r3, [r0], #4
		str	r3, [r0], #4
		str	r3, [r0], #4
#endif
1:		mov	r0, r0
		b	1b



/*
 * Read processor ID register (CP#15, CR0), and determine
 * processor type.
 *
 * Returns:
 *	r5, r6, r7 corrupted
 *	r8  = page table flags
 *	r9  = processor ID
 *	r10 = pointer to processor structure
 */
__lookup_processor_type:
		adr	r5, 2f
		ldmia	r5, {r7, r9, r10}
		sub	r5, r5, r9
		add	r7, r7, r5
		add	r10, r10, r5
		mrc	p15, 0, r9, c0, c0		@ get processor id
1:		ldmia	r10, {r5, r6, r8}		@ value, mask, mmuflags
		eor	r5, r5, r9
		tst	r5, r6
		moveq	pc, lr
		add	r10, r10, #36			@ sizeof(proc_info_list)
		cmp	r10, r7
		blt	1b
		mov	r10, #0
		mov	pc, lr

2:		.long	__proc_info_end
		.long	2b
		.long	__proc_info_begin

/*
 * Lookup machine architecture
 * r1 = machine architecture number
 * Returns:
 *  r4 = unused word
 *  r5 = physical start address of RAM
 *  r6 = physical address of IO
 *  r7 = byte offset into page tables for IO
 */
__lookup_architecture_type:
		cmp	r1, #(__arch_types_end - __arch_types_start) / 16
		bge	1f
		adr	r4, __arch_types_start
		add	r4, r4, r1, lsl #4
		ldmia	r4, {r4, r5, r6, r7}
		mov	r7, r7, lsr #18
		mov	pc, lr
1:		mov	r7, #0
		mov	pc, lr

/*
 * Machine parameters.  Each machine requires 4 words, which are:
 *
 * word0: unused
 * word1: physical start address of RAM
 * word2: physical start address of IO
 * word3: virtual start address of IO
 *
 * The IO mappings entered here are used to set up mappings
 * required for debugging information to be shown to the user.
 * paging_init() does the real page table initialisation.
 */
		@ 0x00 - DEC EBSA110
__arch_types_start:
		.long	0
		.long	0
		.long	0xe0000000
		.long	0xe0000000

		@ 0x01 - Acorn RiscPC
		.long	0
		.long	0x10000000
		.long	0x03000000
		.long	0xe0000000

		@ 0x02 - Unused
		.long	0
		.long	0
		.long	0xe0000000
		.long	0xe0000000

		@ 0x03 - NexusPCI
		.long	0
		.long	0x40000000
		.long	0x10000000
		.long	0xe0000000

		@ 0x04 - DEC EBSA285
		.long	0
		.long	0
		.long	0x42000000
		.long	0xfe000000

		@ 0x05 - Rebel.com NetWinder
		.long	0
		.long	0
		.long	0x42000000
		.long	0xfe000000

		@ 0x06 - CATS
		.long	0
		.long	0
		.long	0x42000000
		.long	0xfe000000

		@ 0x07 - tbox
		.long	0
		.long	0x80000000
		.long	0x00400000			@ Uart
		.long	0xe0000000

		@ 0x08 - DEC EBSA285 as co-processor
		.long	0
		.long	0
		.long	0x42000000			@ Physical I/O base address
		.long	0x7cf00000			@ Virtual I/O base address

		@ 0x09 - CL-PS7110
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0a - Acorn Archimedes
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0b - Acorn A5000
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0c - Etoile
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0d - LaCie_NAS
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0e - CL-PS7500
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x0f - Shark
		.long	0
		.long	0
		.long	0
		.long	0

		@ 0x10 - SA1100
		.long	0
		.long   0xc0000000
		.long   0x80000000 @ IO mapping will change when the kernel get$
		.long   0x80000000

		/*
		 * Don't add anything here unless you have an
		 * architecture number allocated - see
		 * Documentation/arm/README
		 */
__arch_types_end:

#ifdef CONFIG_DEBUG_LL
/*
 * Some debugging routines (useful if you've got MM problems and
 * printk isn't working).  For DEBUGGING ONLY!!!  Do not leave
 * references to these in a production kernel!
 */
#if defined(CONFIG_ARCH_RPC)
		.macro	addruart,rx
		mov	\rx, #0xe0000000
		orr	\rx, \rx, #0x00010000
		orr	\rx, \rx, #0x00000fe0
		.endm

		.macro	senduart,rd,rx
		strb	\rd, [\rx]
		.endm

		.macro	busyuart,rd,rx
1002:		ldrb	\rd, [\rx, #0x14]
		and	\rd, \rd, #0x60
		teq	\rd, #0x60
		bne	1002b
		.endm

		.macro	waituart,rd,rx
1001:		ldrb	\rd, [\rx, #0x18]
		tst	\rd, #0x10
		beq	1001b
		.endm

#elif defined(CONFIG_ARCH_EBSA110)
		.macro	addruart,rx
		mov	\rx, #0xf0000000
		orr	\rx, \rx, #0x00000be0
		.endm

		.macro	senduart,rd,rx
		strb	\rd, [\rx]
		.endm

		.macro	busyuart,rd,rx
1002:		ldrb	\rd, [\rx, #0x14]
		and	\rd, \rd, #0x60
		teq	\rd, #0x60
		bne	1002b
		.endm

		.macro	waituart,rd,rx
1001:		ldrb	\rd, [\rx, #0x18]
		tst	\rd, #0x10
		beq	1001b
		.endm

#elif defined(CONFIG_HOST_FOOTBRIDGE) || defined(CONFIG_ADDIN_FOOTBRIDGE)
#ifndef CONFIG_DEBUG_DC21285_PORT
	/* For NetWinder debugging */
		.macro	addruart,rx
		mov	\rx, #0xff000000
		orr	\rx, \rx, #0x000003f8
		.endm

		.macro	senduart,rd,rx
		strb	\rd, [\rx]
		.endm

		.macro	busyuart,rd,rx
1002:		ldrb	\rd, [\rx, #0x5]
		and	\rd, \rd, #0x60
		teq	\rd, #0x60
		bne	1002b
		.endm

		.macro	waituart,rd,rx
1001:		ldrb	\rd, [\rx, #0x6]
		tst	\rd, #0x10
		beq	1001b
		.endm
#else
	/* For EBSA285 debugging */
		.equ	dc21285_high, ARMCSR_BASE & 0xff000000
		.equ	dc21285_low,  ARMCSR_BASE & 0x00ffffff

		.macro	addruart,rx
		mov	\rx, #dc21285_high
		.if	dc21285_low
		orr	\rx, \rx, #dc21285_low
		.endif
		.endm

		.macro	senduart,rd,rx
		str	\rd, [\rx, #0x160]	@ UARTDR
		.endm

		.macro	busyuart,rd,rx
1001:		ldr	\rd, [\rx, #0x178]	@ UARTFLG
		tst	\rd, #1 << 3
		bne	1001b
		.endm

		.macro	waituart,rd,rx
		.endm
#endif
#elif defined(CONFIG_ARCH_NEXUSPCI)
		.macro	addruart,rx
		ldr	\rx, =0xfff00000
		.endm

		.macro	senduart,rd,rx
		str	\rd, [\rx, #0xc]
		.endm

		.macro	busyuart,rd,rx
1001:		ldr	\rd, [\rx, #0x4]
		tst	\rd, #1 << 0
		bne	1001b
		.endm

		.macro	waituart,rd,rx
		.endm
	
#elif defined(CONFIG_ARCH_SA1100)
		.macro	addruart,rx
		mov	\rx, #0x80000000
		add	\rx, \rx, #0x00050000	@ Ser3
		@add	\rx, \rx, #0x00010000	@ Ser1
		.endm

		.macro	senduart,rd,rx
		str	\rd, [\rx, #0x14]	@ UTDR
		.endm

		.macro	waituart,rd,rx
1001:		ldr	\rd, [\rx, #0x20]	@ UTSR1
		tst	\rd, #1 << 2		@ UTSR1_TNF
		beq	1001b
		.endm

		.macro	busyuart,rd,rx
1001:		ldr	\rd, [\rx, #0x20]	@ UTSR1
		tst	\rd, #1 << 0		@ UTSR1_TBY
		bne	1001b
		.endm

#else
#error Unknown architecture
#endif

/*
 * Useful debugging routines
 */
ENTRY(printhex8)
		mov	r1, #8
		b	printhex

ENTRY(printhex4)
		mov	r1, #4
		b	printhex

ENTRY(printhex2)
		mov	r1, #2
printhex:	ldr	r2, =hexbuf
		add	r3, r2, r1
		mov	r1, #0
		strb	r1, [r3]
1:		and	r1, r0, #15
		mov	r0, r0, lsr #4
		cmp	r1, #10
		addlt	r1, r1, #'0'
		addge	r1, r1, #'a' - 10
		strb	r1, [r3, #-1]!
		teq	r3, r2
		bne	1b
		mov	r0, r2
		b	printascii

		.ltorg

ENTRY(printascii)
		addruart r3
		b	2f
1:		waituart r2, r3
		senduart r1, r3
		busyuart r2, r3
		teq	r1, #'\n'
		moveq	r1, #'\r'
		beq	1b
2:		teq	r0, #0
		ldrneb	r1, [r0], #1
		teqne	r1, #0
		bne	1b
		mov	pc, lr

ENTRY(printch)
		addruart r3
		mov	r1, r0
		mov	r0, #0
		b	1b

		.bss
hexbuf:		.space 16

#endif
