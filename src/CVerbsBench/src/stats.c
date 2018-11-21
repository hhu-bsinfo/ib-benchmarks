#include <math.h>
#include <stdint.h>
#include <stdlib.h>

static int cmpfunc(const void *a, const void *b);

uint64_t stats_times_get_total(uint64_t *array, uint64_t size)
{
    uint64_t tmp = 0;

    for (uint64_t i = 0; i < size; i++) {
        tmp += array[i];
    }

    return tmp;
}

void stats_times_sort_asc(uint64_t *array, uint64_t size)
{
    qsort(array, size, sizeof(uint64_t), cmpfunc);
}

long double stats_time_get_avg_us(uint64_t *array, uint64_t size)
{
    long double tmp = 0;

    for (uint64_t i = 0; i < size; i++) {
        tmp += (long double) array[i] / 1000.0;
    }

    return tmp / size;
}

long double stats_time_get_min_us(uint64_t *array, uint64_t size)
{
    return (long double) array[0] / 1000.0;
}

long double stats_time_get_max_us(uint64_t *array, uint64_t size)
{
    return (long double) array[size - 1] / 1000.0;
}

long double stats_times_get_percentiles_us(uint64_t *array, uint64_t size, float perc)
{
    if (perc < 0.0 || perc > 1.0) {
        return -1;
    }

    return (long double) array[(uint64_t) ceil(perc * size) - 1] / 1000.0;
}

static int cmpfunc(const void *a, const void *b)
{
    return (*(int64_t*) a - *(int64_t*) b); 
}