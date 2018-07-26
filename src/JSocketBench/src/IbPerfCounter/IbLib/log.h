/**
 * @file log.h
 * @author Fabian Ruhland, HHU
 * @date May 2018
 *
 * @brief Contains some macros, which can be used to create color-coded logging messages.
 *
 * All messages have the following format: [NAME][TYPE]MESSAGE\n
 */


#ifndef LOG_H
#define LOG_H

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

extern uint8_t verbosity;

/**
 * Print an information message in blue.
 *
 * @param NAME Usually the callers name, e.g. "CONNECTION", "QUEUE PAIR", etc.
 * @param ... A format string containing the message, followed by its parameters.
 */
#define LOG_INFO(NAME, ...) if(verbosity >= 4) { \
                                printf("\e[32m[%s]\e[34m[INFO] ", NAME); \
                                printf(__VA_ARGS__); printf("\e[0m\n"); \
                            }

/**
 * Print a warning message in yellow.
 *
 * @param NAME Usually the callers name, e.g. "CONNECTION", "QUEUE PAIR", etc.
 * @param ... A format string containing the message, followed by its parameters.
 */
#define LOG_WARN(NAME, ...) if(verbosity >= 3) { \
                                printf("\e[32m[%s]\e[33m[WARN] ", NAME); \
                                printf(__VA_ARGS__); printf("\e[0m\n"); \
                            }

/**
 * Print an error message in red.
 *
 * @param NAME Usually the callers name, e.g. "CONNECTION", "QUEUE PAIR", etc.
 * @param ... A format string containing the message, followed by its parameters.
 */
#define LOG_ERROR(NAME, ...) if(verbosity >= 2) { \
                                printf("\e[32m[%s]\e[31m[ERROR] ", NAME); \
                                printf(__VA_ARGS__); \
                                printf("\e[0m\n"); \
                            }

/**
* Print an error message in red and exit the program.
*
* @param NAME Usually the callers name, e.g. "CONNECTION", "QUEUE PAIR", etc.
* @param ... A format string containing the message, followed by its parameters.
*/
#define LOG_ERROR_AND_EXIT(NAME, ...) printf("\e[32m[%s]\e[31m[FATAL ERROR] ", NAME); \
                                      printf(__VA_ARGS__); \
                                      printf("\e[0m\nExiting...\n"); \
                                      exit(1);

#endif