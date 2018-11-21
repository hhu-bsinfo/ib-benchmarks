/**
 * @file timer.h
 * @author Stefan Nothaas, HHU
 * @date 2018
 *
 * @brief Timer based on tscp
 */

#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

/**
 * This implementation is based on the following source:
 * https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/ia-32-ia-64-benchmark-code-execution-paper.pdf
 */

/**
 * Initialize the timer. Call this before using any of
 * of the functions to measure time.
 */
void timer_init();

/**
 * Calculate the delta time of a start and end time in cycles.
 *
 * @param start_cycles Measurement taken at start
 * @param end_cycles Measurement taken at end
 * @return Time in ns
 */
uint64_t timer_calc_delta_ns(uint64_t start_cycles, uint64_t end_cycles);

/**
 * Calculate the delta time of a start and end time in cycles.
 *
 * @param start_cycles Measurement taken at start
 * @param end_cycles Measurement taken at end
 * @return Time in ns
 */
uint64_t timer_calc_delta_us(uint64_t start_cycles, uint64_t end_cycles);

/**
 * Calculate the delta time of a start and end time in cycles.
 *
 * @param start_cycles Measurement taken at start
 * @param end_cycles Measurement taken at end
 * @return Time in ns
 */
uint64_t timer_calc_delta_ms(uint64_t start_cycles, uint64_t end_cycles);

/**
 * Calculate the delta time of a start and end time in cycles.
 *
 * @param start_cycles Measurement taken at start
 * @param end_cycles Measurement taken at end
 * @return Time in ns
 */
uint64_t timer_calc_delta_sec(uint64_t start_cycles, uint64_t end_cycles);

/**
 * Convert cycles to seconds
 * 
 * @param cycles The number of cycles to convert
 * @return Time in seconds
 */
uint64_t timer_cycles_to_sec(uint64_t cycles);

/**
 * Convert cycles to milliseconds
 * 
 * @param cycles The number of cycles to convert
 * @return Time in milliseconds
 */
uint64_t timer_cycles_to_ms(uint64_t cycles);

/**
 * Convert cycles to microseconds
 * 
 * @param cycles The number of cycles to convert
 * @return Time in microseconds
 */
uint64_t timer_cycles_to_us(uint64_t cycles);

/**
 * Convert cycles to nanoseconds
 * 
 * @param cycles The number of cycles to convert
 * @return Time in nanoseconds
 */
uint64_t timer_cycles_to_ns(uint64_t cycles);

/**
 * Start time measurement
 *
 * @return Current "time" in clock cycles
 */
static inline uint64_t timer_start()
{
    uint32_t lo;
    uint32_t hi;

    asm volatile ("rdtscp\n\t"
        "mov %%edx, %0\n\t"
        "mov %%eax, %1\n\t": "=r" (hi), "=r" (lo)::
        "%rax", "%rcx", "%rdx");

    return (uint64_t) hi << 32 | lo;
}

/**
 * End time measurement (weak version)
 *
 * This version has a lower overhead because it doesn't
 * serialize after the rdtscp instruction which avoids
 * out of order execution of all following instructions
 * together with the rdtscp instruction. This might result
 * in minor inaccuracies but yields better performance.
 *
 * @return Current "time" in clock cycles
 */
static inline uint64_t timer_end_weak()
{
    uint32_t lo;
    uint32_t hi;

    asm volatile("rdtscp\n\t"
        "mov %%edx, %0\n\t"
        "mov %%eax, %1\n\t": "=r" (hi), "=r" (lo)::
        "%rax", "%rcx", "%rdx");

    return (uint64_t) hi << 32 | lo;
}

/**
 * End time measurement (strong version)
 *
 * This version has a higher overhead than the weak one
 * but guarantees higher accuracy for the measured time.
 * It serializes execution after the rdtscp instruction
 * to avoid out of order execution of any following
 * instruction before the rdtscp call completed. However,
 * this comes at a cost of higher overhead.
 *
 * @return Current "time" in clock cycles
 */
static inline uint64_t timer_end_strong()
{
    uint32_t lo;
    uint32_t hi;

    asm volatile("rdtscp\n\t"
        "mov %%edx, %0\n\t"
        "mov %%eax, %1\n\t"
        "cpuid\n\t": "=r" (hi), "=r" (lo)::
        "%rax", "%rbx", "%rcx", "%rdx");

    return (uint64_t) hi << 32 | lo;
}

#endif