/*
 * linux/arch/arm/mm/proc-sa110.S: MMU functions for SA110
 *
 * (C) 1997-1999 Russell King
 *
 * These are the low level assembler for performing cache and TLB
 * functions on the StrongARM-110.
 *
 * Additions for SA1100 support (C) 1999 Nicolas Pitre <nico@cam.org>
 *
 */
#include <linux/config.h>
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <asm/procinfo.h>
#include <asm/hardware.h>
#include "../lib/constants.h"

/* This is the maximum size of an area which will be flushed.  If the area
 * is larger than this, then we flush the whole cache
 */
#define MAX_AREA_SIZE	32768
#define FLUSH_OFFSET	32768

/* This is the size of the main data cache. */
#ifdef CONFIG_CPU_SA1100
# define MAIN_DCACHE_SIZE 8192
#else
# define MAIN_DCACHE_SIZE 16384
#endif

		.data
Lclean_switch:	.long	0
		.text

/*
 * Function: sa110_flush_cache_all (void)
 * Purpose : Flush all cache lines
 */
		.align	5
_sa110_flush_cache_all:					@ preserves r0
		mov	r2, #1
_sa110_flush_cache_all_r2:
		ldr	r3, =Lclean_switch
		ldr	ip, =FLUSH_BASE
		ldr	r1, [r3]
		ands	r1, r1, #1
		eor	r1, r1, #1
		str	r1, [r3]
		addne	ip, ip, #FLUSH_OFFSET

		@ main dcache
		add	r1, ip, #MAIN_DCACHE_SIZE
1:		ldr	r3, [ip], #32
		teq	r1, ip
		bne	1b

#ifdef CONFIG_CPU_SA1100
		@ mini dcache
		add	ip, ip, #(FLUSH_BASE_MINICACHE - FLUSH_BASE)
		add	r1, ip, #512    @ 512 bytes minicache
1:		ldr	r3, [ip], #32
		teq	r1, ip
		bne	1b
#endif

		mov	ip, #0
		tst	r2, #1
		mcrne	p15, 0, ip, c7, c5, 0		@ flush I cache
		mcr	p15, 0, ip, c7, c10, 4		@ drain WB
		mov	pc, lr

/*
 * Function: sa110_flush_cache_area (unsigned long address, int end, int flags)
 * Params  : address	Area start address
 *	   : end	Area end address
 *	   : flags	b0 = I cache as well
 * Purpose : clean & flush all cache lines associated with this area of memory
 */
		.align	5
_sa110_flush_cache_area:
		sub	r3, r1, r0
		cmp	r3, #MAX_AREA_SIZE
		bgt	_sa110_flush_cache_all_r2
1:		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		mcr	p15, 0, r0, c7, c6, 1		@ flush D entry
		add	r0, r0, #32
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		mcr	p15, 0, r0, c7, c6, 1		@ flush D entry
		add	r0, r0, #32
		cmp	r0, r1
		blt	1b
		tst	r2, #1
		movne	r0, #0
		mcrne	p15, 0, r0, c7, c5, 0		@ flush I cache
		mov	pc, lr

/*
 * Function: sa110_cache_wback_area(unsigned long address, unsigned long end)
 * Params  : address	Area start address
 *	   : end	Area end address
 * Purpose : ensure all dirty cachelines in the specified area have been
 *	     written out to memory (for DMA)
 */
		.align	5
_sa110_cache_wback_area:
		sub	r3, r1, r0
		cmp	r3, #MAX_AREA_SIZE
		mov	r2, #0
		bgt	_sa110_flush_cache_all_r2
		bic	r0, r0, #31
1:		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		cmp	r0, r1
		blt	1b
		mcr	p15, 0, r2, c7, c10, 4		@ drain WB
		mov	pc, lr

/*
 * Function: sa110_cache_purge_area(unsigned long address, unsigned long end)
 * Params  : address	Area start address
 *	   : end	Area end address
 * Purpose : throw away all D-cached data in specified region without
 *	     an obligation to write it back.
 * Note    : Must clean the D-cached entries around the boundaries if the
 *	     start and/or end address are not cache aligned.
 */
		.align	5
_sa110_cache_purge_area:
		tst	r0, #31
		bic	r0, r0, #31
		mcrne	p15, 0, r0, c7, c10, 1		@ clean D entry
		tst	r1, #31
		mcrne	p15, 0, r1, c7, c10, 1		@ clean D entry
1:		mcr	p15, 0, r0, c7, c6, 1		@ flush D entry
		add	r0, r0, #32
		cmp	r0, r1
		blt	1b
		mov	pc, lr

/*
 * Function: sa110_flush_cache_entry (unsigned long address)
 * Params  : address	Address of cache line to flush
 * Purpose : clean & flush an entry
 */
		.align	5
_sa110_flush_cache_entry:
		mov	r1, #0
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		mcr	p15, 0, r1, c7, c10, 4		@ drain WB
		mcr	p15, 0, r1, c7, c5, 0		@ flush I cache
		mov	pc, lr

/*
 * Function: sa110_clean_cache_area(unsigned long start, unsigned long size)
 * Params  : address	Address of cache line to clean
 * Purpose : Ensure that physical memory reflects cache at this location
 *	     for page table purposes.
 */
_sa110_clean_cache_area:
1:		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry	 (drain is done by TLB fns)
		add	r0, r0, #32
		subs	r1, r1, #32
		bhi	1b
		mov	pc, lr

/*
 * Function: sa110_flush_ram_page (unsigned long page)
 * Params  : address	Area start address
 *	   : size	size of area
 *	   : flags	b0 = I cache as well
 * Purpose : clean & flush all cache lines associated with this area of memory
 */
		.align	5
_sa110_flush_ram_page:
		mov	r1, #4096
1:		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		add	r0, r0, #32
		subs	r1, r1, #128
		bne	1b
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4		@ drain WB
		mov	pc, lr

/*
 * Function: sa110_flush_tlb_all (void)
 * Purpose : flush all TLB entries in all caches
 */
		.align	5
_sa110_flush_tlb_all:
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4		@ drain WB
		mcr	p15, 0, r0, c8, c7, 0		@ flush I & D tlbs
		mov	pc, lr

/*
 * Function: sa110_flush_tlb_area (unsigned long address, unsigned long end, int flags)
 * Params  : address	Area start address
 *	   : end	Area end address
 *	   : flags	b0 = I-TLB as well
 * Purpose : flush a TLB entry
 */
		.align	5
_sa110_flush_tlb_area:
		mov	r3, #0
		mcr	p15, 0, r3, c7, c10, 4		@ drain WB
1:		cmp	r0, r1
		mcrlt	p15, 0, r0, c8, c6, 1		@ flush D TLB entry
		addlt	r0, r0, #4096
		cmp	r0, r1
		mcrlt	p15, 0, r0, c8, c6, 1		@ flush D TLB entry
		addlt	r0, r0, #4096
		blt	1b
		teq	r2, #0
		mcrne	p15, 0, r3, c8, c5, 0		@ flush I TLB
		mov	pc, lr

		.align	5
_sa110_flush_icache_area:
1:		mcr	p15, 0, r0, c7, c10, 1		@ Clean D entry
		add	r0, r0, #32
		subs	r1, r1, #32
		bhi	1b
		mov	r0, #0
		mcr	p15, 0, r0, c7, c10, 4		@ drain WB
		mcr	p15, 0, r0, c7, c5, 0		@ flush I cache
		mov	pc, lr
/*
 * Function: sa110_switch_to (struct task_struct *prev, struct task_struct *next)
 * Params  : prev	Old task structure
 *	   : next	New task structure for process to run
 * Returns : prev
 * Purpose : Perform a task switch, saving the old processes state, and restoring
 *	     the new.
 * Notes   : We don't fiddle with the FP registers here - we postpone this until
 *	     the new task actually uses FP.  This way, we don't swap FP for tasks
 *	     that do not require it.
 */
		.align	5
_sa110_switch_to:
		stmfd	sp!, {r4 - r10, fp, lr}		@ Store most regs on stack
		mrs	ip, cpsr
		stmfd	sp!, {ip}			@ Save cpsr_SVC
		ldr	r2, [r0, #TSS_MEMMAP]		@ Get old page tables
		str	sp, [r0, #TSS_SAVE]		@ Save sp_SVC

		ldr	r5, [r0, #TSK_NEED_RESCHED]	@ Move reschedule flag
		cmp	r5, #0				@ over to new
		strne	r5, [r1, #TSK_NEED_RESCHED]	@ TSS if it's set
		movne	r5, #0				@ Clear old one to
							@ stop unnecessary
		strne	r5, [r0, #TSK_NEED_RESCHED]	@ calls to schedule()
	
		ldr	sp, [r1, #TSS_SAVE]		@ Get saved sp_SVC
		ldr	r5, [r1, #TSS_DOMAIN]
		ldr	r4, [r1, #TSS_MEMMAP]		@ Page table pointer
		mcr	p15, 0, r5, c3, c0		@ Set segment
/*
 * Flushing the cache is nightmarishly slow, so we take any excuse
 * to get out of it.  If the old page table is the same as the new,
 * this is a CLONE_VM relative of the old task and there is no need
 * to flush.  The overhead of the tests isn't even on the radar
 * compared to the cost of the flush itself.
 */
		teq	r4, r2
		beq	2f
		ldr	r3, =Lclean_switch
		ldr	r2, [r3]
		ands	r2, r2, #1
		eor	r2, r2, #1
		str	r2, [r3]
		ldr	r2, =FLUSH_BASE
		addne	r2, r2, #FLUSH_OFFSET

		@ main dcache
		add	r1, r2, #MAIN_DCACHE_SIZE
1:		ldr	r3, [r2], #32
		teq	r1, r2
		bne	1b

#ifdef CONFIG_CPU_SA1100
		@ mini dcache
		add	r2, r2, #(FLUSH_BASE_MINICACHE - FLUSH_BASE)
		add	r1, r2, #512	@ 512 bytes minicache
1:		ldr	r3, [r2], #32
		teq	r1, r2
		bne	1b
#endif

		mov	r1, #0
		mcr	p15, 0, r1, c7, c5, 0		@ flush I cache
		mcr	p15, 0, r1, c7, c10, 4		@ drain WB
		mcr	p15, 0, r4, c2, c0, 0		@ load page table pointer
		mcr	p15, 0, r1, c8, c7, 0		@ flush TLBs
2:		ldmfd	sp!, {ip}
		msr	spsr, ip			@ Save tasks CPSR into SPSR for this return
		ldmfd	sp!, {r4 - r10, fp, pc}^	@ Load all regs saved previously

/*
 * Function: sa110_data_abort ()
 * Params  : r0 = address of aborted instruction
 * Purpose : obtain information about current aborted instruction
 * Returns : r0 = address of abort
 *	   : r1 = FSR
 *	   : r2 != 0 if writing
 */
		.align	5
_sa110_data_abort:
		ldr	r2, [r0]			@ read instruction causing problem
		mrc	p15, 0, r0, c6, c0, 0		@ get FAR
		mov	r2, r2, lsr #19			@ b1 = L
		and	r3, r2, #0x69 << 2
		and	r2, r2, #2
		mrc	p15, 0, r1, c5, c0, 0		@ get FSR
		and	r1, r1, #255
		mov	pc, lr

/*
 * Function: sa110_set_pmd(pmd_t *pmdp, pmd_t pmd)
 * Params  : r0 = Address to set
 *	   : r1 = value to set
 * Purpose : Set a PMD and flush it out
 */
		.align	5
_sa110_set_pmd:	str	r1, [r0]
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		mcr	p15, 0, r0, c7, c10, 4		@ drain WB
		mov	pc, lr

/*
 * Function: sa110_set_pte(pte_t *ptep, pte_t pte)
 * Params  : r0 = Address to set
 *	   : r1 = value to set
 * Purpose : Set a PTE and flush it out
 */
		.align	5
_sa110_set_pte:	str	r1, [r0], #-1024		@ linux version

		eor	r1, r1, #LPTE_PRESENT | LPTE_YOUNG | LPTE_WRITE | LPTE_DIRTY

		bic	r2, r1, #0xff0
		bic	r2, r2, #3
		orr	r2, r2, #HPTE_TYPE_SMALL

		tst	r1, #LPTE_USER | LPTE_EXEC	@ User or Exec?
		orrne	r2, r2, #HPTE_AP_READ

		tst	r1, #LPTE_WRITE | LPTE_DIRTY	@ Write and Dirty?
		orreq	r2, r2, #HPTE_AP_WRITE

		tst	r1, #LPTE_PRESENT | LPTE_YOUNG	@ Present and Young?
		movne	r2, #0

		str	r2, [r0]			@ hardware version
		mov	r0, r0
		mcr	p15, 0, r0, c7, c10, 1		@ clean D entry
		mcr	p15, 0, r0, c7, c10, 4		@ drain WB
		mov	pc, lr

/*
 * Function: sa110_check_bugs (void)
 *	   : sa110_proc_init (void)
 *	   : sa110_proc_fin (void)
 * Notes   : This processor does not require these
 */
_sa110_check_bugs:
		mrs	ip, cpsr
		bic	ip, ip, #F_BIT
		msr	cpsr, ip
		mov	pc, lr

_sa110_proc_init:
		mov	r0, #0
		mcr	p15, 0, r0, c15, c1, 2		@ Enable clock switching
		mov	pc, lr

_sa110_proc_fin:
		mrs	r0, cpsr
		orr	r0, r0, #F_BIT | I_BIT
		msr	cpsr, r0
		mov	r0, #0
		mcr	p15, 0, r0, c15, c2, 2		@ Disable clock switching
		mrc	p15, 0, r0, c1, c0, 0
		bic	r0, r0, #0x1100			@ ...i...s........
		bic	r0, r0, #0x000e			@ ............wca.
		mcr	p15, 0, r0, c1, c0, 0		@ disable caches
		mov	pc, lr

		.align	5
ENTRY(cpu_sa110_do_idle)
		mov	r0, #0
		mcr	p15, 0, r0, c15, c2, 2		@ Disable clock switching
		ldr	r1, =FLUSH_BASE+FLUSH_OFFSET*2	@ load from uncacheable loc
		ldr	r1, [r1, #0]
		b	1f

		.align	5
1:		mcr	p15, 0, r0, c15, c8, 2		@ Wait for interrupt
		mcr	p15, 0, r0, c15, c1, 2		@ Enable clock switching
		mov	pc, lr

/*
 * Function: sa110_reset
 * Notes   : This sets up everything for a reset
 */
_sa110_reset:
		stmfd	sp!, {r1, lr}
		mov	r2, #1
		bl	_sa110_flush_cache_all
		bl	_sa110_flush_tlb_all
		mcr	p15, 0, ip, c7, c7, 0		@ flush I,D caches
		mrc	p15, 0, r0, c1, c0, 0		@ ctrl register
		bic	r0, r0, #0x000f			@ ............wcam
		bic	r0, r0, #0x1100			@ ...i...s........
		ldmfd	sp!, {r1, pc}
/*
 * Purpose : Function pointers used to access above functions - all calls
 *	     come through these
 */

cpu_manu_name:	.asciz	"Intel"
ENTRY(cpu_sa110_name)
#ifdef CONFIG_CPU_SA1100
		.asciz	"StrongARM-1100"
#else
		.asciz	"StrongARM-110"
#endif
		.align

		.section ".text.init", #alloc, #execinstr

__sa110_setup:	mov	r0, #0
		mcr	p15, 0, r0, c7, c7		@ flush I,D caches on v4
		mcr	p15, 0, r0, c7, c10, 4		@ drain write buffer on v4
		mcr	p15, 0, r0, c8, c7		@ flush I,D TLBs on v4
		mcr	p15, 0, r4, c2, c0		@ load page table pointer
		mov	r0, #0x1f			@ Domains 0, 1 = client
		mcr	p15, 0, r0, c3, c0		@ load domain access register
		mrc	p15, 0, r0, c1, c0		@ get control register v4
		bic	r0, r0, #0x0e00			@ ....??r.........
		bic	r0, r0, #0x0002			@ ..............a.
		orr	r0, r0, #0x003d			@ ..........DPWC.M
		orr	r0, r0, #0x1100			@ ...I...S........
		mov	pc, lr

		.type	sa110_processor_functions, #object
sa110_processor_functions:
		.word	cpu_sa110_name			@  0
		.word	_sa110_switch_to		@  4
		.word	_sa110_data_abort		@  8
		.word	_sa110_check_bugs		@ 12
		.word	_sa110_proc_init		@ 16
		.word	_sa110_proc_fin			@ 20

		.word	_sa110_flush_cache_all		@ 24
		.word	_sa110_flush_cache_area		@ 28
		.word	_sa110_flush_cache_entry	@ 32
		.word	_sa110_clean_cache_area		@ 36
		.word	_sa110_flush_ram_page		@ 40
		.word	_sa110_flush_tlb_all		@ 44
		.word	_sa110_flush_tlb_area		@ 48

		.word	_sa110_set_pmd			@ 52
		.word	_sa110_set_pte			@ 56
		.word	_sa110_reset			@ 60
		.word	_sa110_flush_icache_area	@ 64

		.word	_sa110_cache_wback_area		@ 68
		.word	_sa110_cache_purge_area		@ 72
		.word	0
		.word	cpu_sa110_do_idle
		.size	sa110_processor_functions, . - sa110_processor_functions

		.type	cpu_sa110_info, #object
cpu_sa110_info:
		.long	cpu_manu_name
		.long	cpu_sa110_name
		.size	cpu_sa110_info, . - cpu_sa110_info

		.type	cpu_arch_name, #object
cpu_arch_name:	.asciz	"armv4"
		.size	cpu_arch_name, . - cpu_arch_name

		.type	cpu_elf_name, #object
cpu_elf_name:	.asciz	"v4"
		.size	cpu_elf_name, . - cpu_elf_name
		.align

		.section ".proc.info", #alloc, #execinstr

		.type	__sa110_proc_info,#object
__sa110_proc_info:
		.long	0x4401a100
		.long	0xffffffe0
		.long	0x00000c02
		b	__sa110_setup
		.long	cpu_arch_name
		.long	cpu_elf_name
		.long	HWCAP_SWP | HWCAP_HALF | HWCAP_26BIT
		.long	cpu_sa110_info
		.long	sa110_processor_functions
		.size	__sa110_proc_info, . - __sa110_proc_info


