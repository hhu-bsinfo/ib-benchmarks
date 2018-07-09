/**
 * Contains some static functions, which can be used to create color-coded logging messages.
 *
 * All messages have the following format: [NAME][TYPE]MESSAGE\n
 *
 * @author Fabian Ruhland, HHU
 * @date May 2018
 */
class Log {

    /**
     * The verbosity level.
     *
     * 0 = Only fatal errors and unformatted results
     * 1 = Only fatal errors and formatted results
     * 2 = Only errors, fatal errors and formatted results
     * 3 = Only warnings, errors, fatal errors and formatted results
     * 4 = Everything
     */
    static int VERBOSITY = 4;

    /**
     * Print an information message in blue.
     *
     * @param name Usually the callers name, e.g. "CONNECTION", etc.
     * @param string A format string containing the message
     * @param fmt The format parameters
     */
    static void INFO(String name, String string, Object... fmt) {
        if(VERBOSITY >= 4) {
            System.out.printf("\033[32m[%s]\033[34m[INFO] ", name);
            System.out.printf(string, fmt);
            System.out.println("\033[0m");
        }
    }

    /**
     * Print an information message in yellow.
     *
     * @param name Usually the callers name, e.g. "CONNECTION", etc.
     * @param string A format string containing the message
     * @param fmt The format parameters
     */
    static void WARN(String name, String string, Object... fmt) {
        if(VERBOSITY >= 3) {
            System.out.printf("\033[32m[%s]\033[33m[WARN] ", name);
            System.out.printf(string, fmt);
            System.out.println("\033[0m");
        }
    }

    /**
     * Print an information message in red.
     *
     * @param name Usually the callers name, e.g. "CONNECTION", etc.
     * @param string A format string containing the message
     * @param fmt The format parameters
     */
    static void ERROR(String name, String string, Object... fmt) {
        if(VERBOSITY >= 2) {
            System.out.printf("\033[32m[%s]\033[31m[ERROR] ", name);
            System.out.printf(string, fmt);
            System.out.println("\033[0m");
        }
    }

    /**
     * Print an information message in red and exit the program.
     *
     * @param name Usually the callers name, e.g. "CONNECTION", etc.
     * @param string A format string containing the message
     * @param fmt The format parameters
     */
    static void ERROR_AND_EXIT(String name, String string, Object... fmt) {
        System.out.printf("\033[32m[%s]\033[31m[FATAL ERROR] ", name);
        System.out.printf(string, fmt);
        System.out.println("\033[0m");

        System.exit(1);
    }
}
