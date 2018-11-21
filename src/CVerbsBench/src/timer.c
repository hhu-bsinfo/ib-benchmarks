#include <stdbool.h>
#include <sys/time.h>

#include "IbLib/log.h"
#include "timer.h"

static bool timer_tscp_support();
static uint64_t timer_overhead(uint32_t samples);
static double timer_util_cycles_per_sec(uint64_t overhead_cycles);

static uint64_t timer_minimal_overhead_cycles;
static double timer_cycles_per_second;

void timer_init()
{
    if(!timer_tscp_support()) {
        LOG_ERROR_AND_EXIT("TIMER", "CPU does not support RDTSCP instruction required for measuring time!");
    }

    // Determine the overhead of the timer and cycles per second to calculate the results later
    timer_minimal_overhead_cycles = timer_overhead(1000000);
    timer_cycles_per_second = timer_util_cycles_per_sec(timer_minimal_overhead_cycles);
}

uint64_t timer_calc_delta_ns(uint64_t start_cycles, uint64_t end_cycles)
{
    uint64_t tmp = end_cycles - start_cycles;

    // Looks like 0 measurement considering the overhead 
    if (tmp < timer_minimal_overhead_cycles) {
        return 0;
    }

    return timer_cycles_to_ns(tmp - timer_minimal_overhead_cycles);
}

uint64_t timer_calc_delta_us(uint64_t start_cycles, uint64_t end_cycles)
{
    return timer_calc_delta_ns(start_cycles, end_cycles) / 1000;
}

uint64_t timer_calc_delta_ms(uint64_t start_cycles, uint64_t end_cycles)
{
    return timer_calc_delta_ns(start_cycles, end_cycles) / 1000 / 1000;
}

uint64_t timer_calc_delta_sec(uint64_t start_cycles, uint64_t end_cycles)
{
    return timer_calc_delta_ns(start_cycles, end_cycles) / 1000 / 1000 / 1000;
}

uint64_t timer_cycles_to_sec(uint64_t cycles)
{
    return (uint64_t) (cycles / timer_cycles_per_second);
}

uint64_t timer_cycles_to_ms(uint64_t cycles)
{
    return (uint64_t) (cycles / (timer_cycles_per_second / 1000.0));
}

uint64_t timer_cycles_to_us(uint64_t cycles)
{
    return (uint64_t) (cycles / (timer_cycles_per_second / 1000.0 / 1000.0));
}

uint64_t timer_cycles_to_ns(uint64_t cycles)
{
    return (uint64_t) (cycles / (timer_cycles_per_second / 1000.0 / 1000.0 / 1000.0));
}

/**
 * Check if the rdtscp instruction is supported by the current CPU
 */
static bool timer_tscp_support()
{
    uint32_t in = 1;
    uint32_t flags;

    asm volatile("cpuid" : "=d" (flags) : "a" (in));
    return (bool) (flags & (1 << 27));
}

/**
 * Measure the minimal overhead when using rdtscp for time measurements. This
 * value must be considered when measuring times using rdtscp
 *
 * @return Overead when using rdtscp to measure time in cycles
 */
static uint64_t timer_overhead(uint32_t samples)
{
    uint64_t start;
    uint64_t end;
    uint64_t min = 0;

    /* Warm up the instruction cache to avoid spurious measurements due to
       cache effects */

    timer_start();
    timer_end_strong();
    timer_start();
    timer_end_strong();

    /* Execute overhead measurements. The minimum is the guaranteed overhead. */

    for (uint32_t i = 0; i < samples; i++) {
        start = timer_start();
        end = timer_end_strong();

        if (end < start) {
            return (uint64_t) -1;
        }

        if (min == 0 || end - start < min) {
            min = end - start;
        }
    }

    return min;
}

/**
 * Source: https://github.com/PlatformLab/RAMCloud/blob/master/src/Cycles.cc
 * 
 * Calculate the number of cycles per second which is used to convert cycle
 * counts yielded by rdtsc or rdtscp to secs, ms, us or ns.
 * 
 * @param overhead_cycles The overhead (in cycles) to consider when measuring 
 *        time using rdtsc or rdtscp
 * @return Number of cycles per second
 */
static double timer_util_cycles_per_sec(uint64_t overhead_cycles)
{
    /* Compute the frequency of the fine-grained CPU timer: to do this,
       take parallel time readings using both rdtsc and gettimeofday.
       After 10ms have elapsed, take the ratio between these readings. */

    double cycles_per_sec;
    struct timeval start_time;
    struct timeval stop_time;
    uint64_t start_cycles;
    uint64_t stop_cycles;
    uint64_t micros;
    double old_cycles;

    /* There is one tricky aspect, which is that we could get interrupted
       between calling gettimeofday and reading the cycle counter, in which
       case we won't have corresponding readings.  To handle this (unlikely)
       case, compute the overall result repeatedly, and wait until we get
       two successive calculations that are within 0.1% of each other. */

    old_cycles = 0;

    while (1) {
        if (gettimeofday(&start_time, NULL) != 0) {
            return 0.0;
        }

        start_cycles = timer_start();

        while (1) {
            if (gettimeofday(&stop_time, NULL) != 0) {
                return 0.0;
            }
                    
            stop_cycles = timer_end_strong();
            micros = (uint64_t) ((stop_time.tv_usec - start_time.tv_usec) +
                (stop_time.tv_sec - start_time.tv_sec) * 1000000);

            if (micros > 10000) {
                cycles_per_sec = 
                    (double) (stop_cycles - start_cycles - overhead_cycles);
                cycles_per_sec = 1000000.0 * cycles_per_sec/
                        (double) (micros);
                break;
            }
        }

        double delta = cycles_per_sec / 1000.0;

        if ((old_cycles > (cycles_per_sec - delta)) &&
                (old_cycles < (cycles_per_sec + delta))) {
            return cycles_per_sec;
        }

        old_cycles = cycles_per_sec;
    }
}