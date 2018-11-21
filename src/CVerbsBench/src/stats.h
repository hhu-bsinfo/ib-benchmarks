/**
 * @file stats.h
 * @author Stefan Nothaas, HHU
 * @date 2018
 *
 * @brief Contains various utility functions for evaluating recorded data.
 */

#ifndef STATS_H
#define STATS_H

#include <stdint.h>

/**
 * Get the total time of all measured values
 *
 * @param array Array with time values
 * @param size Size of array
 * @return Sum of values in array
 */
uint64_t stats_times_get_total(uint64_t *array, uint64_t size);

/**
 * Sort the measured time values in ascending order
 *
 * @param array Array of values to sort
 * @param size Size of array
 */
void stats_times_sort_asc(uint64_t *array, uint64_t size);

/**
 * Get the average time in us
 *
 * @param array Array of measured time values
 * @param size Size of array
 * @return Average time in us
 */
long double stats_time_get_avg_us(uint64_t *array, uint64_t size);

/**
 * Get the min time in us (array must be sorted)
 *
 * @param array Array of measured time values
 * @param size Size of array
 * @return Min time in us
 */
long double stats_time_get_min_us(uint64_t *array, uint64_t size);

/**
 * Get the max time in us (array must be sorted)
 *
 * @param array Array of measured time values
 * @param size Size of array
 * @return Max time in us
 */
long double stats_time_get_max_us(uint64_t *array, uint64_t size);

/**
 * Get the Xth percentiles value (array must be sorted)
 *
 * @param array Array of measured time values
 * @param size Size of array
 * @param perc Xth percentile to get (e.g. 0.95 for 95h percentile)
 * @return Value in us
 */
long double stats_times_get_percentiles_us(uint64_t *array, uint64_t size, float perc);

#endif