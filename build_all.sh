#!/bin/bash

readonly GIT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"
readonly GIT_BRANCH="$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)"
readonly GIT_REV="$(git rev-parse --short HEAD 2>/dev/null)"
readonly DATE="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

MODE="build"
JAVA_PATH=""
J9_JAVA_PATH=""

print_usage()
{
    printf "Usage: ./build_all.sh [OPTION...]
    Available options:
    -j, --java
        Set the path to your default JDK, which will be used to build JSocketBench and DisniBench.
    -i, --ibm-java
        Set the path to your J9 JDK, which will be used to build JVerbsBench.
    -m, --mode
        Set the operating mode to either 'build', 'doc' or 'clean' (default: build)
    -h, --help
        Show this help message\\n"
}

parse_args()
{
    while [ "${1}" != "" ]; do
        local arg=$1
        local val=$2
        
        case $1 in
            -j|--java)
            JAVA_PATH=$val
            ;;
            -i|--ibm-java)
            J9_JAVA_PATH=$val
            ;;
            -m|--mode)
            MODE=$val
            ;;
            -h|--help)
            print_usage
            exit 0
            ;;
            *)
            LOG_ERROR "Unknown option '%s'" "${arg}"
            print_usage
            exit 1
            ;;
        esac
        shift 2
    done
}

check_config()
{
    local java_version j9_java_valid j9_java_version

    LOG_INFO "Checking configuration..."
    
    java_version=$("${JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    j9_java_valid=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | grep "IBM J9 VM");
    j9_java_version=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')

    if [ -z "${java_version}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to contain a valid JDK!" "${JAVA_PATH}"
    fi

    if [ -z "${j9_java_version}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to contain a valid JDK!" "${J9_JAVA_PATH}"
    fi

    if [ -z "${j9_java_valid}" ]; then
        LOG_ERROR_AND_EXIT "'%s' does not seem to contain a valid IBM JDK!" "${J9_JAVA_PATH}"
    fi

    if [ "${java_version}" -lt 18 ]; then
        LOG_ERROR_AND_EXIT "'%s' implements a version of java older than 1.8 (determined version %u)!" "${JAVA_PATH}" "${java_version}"
    else
        LOG_INFO "Default JVM: '%s' - Determined version: %u --> [VALID]" "${JAVA_PATH}" "${java_version}"
    fi

    if [ "${j9_java_version}" -lt 18 ]; then
        LOG_ERROR_AND_EXIT "'%s' implements a version of java older than 1.8 (determined version %u)!" "${J9_JAVA_PATH}" "${j9_java_version}"
    else
        LOG_INFO "IBM J9 JVM: '%s' - Determined version: %u --> [VALID]" "${J9_JAVA_PATH}" "${j9_java_version}"
    fi

    LOG_INFO "Configuration seems to be valid!"
}

generate_doc()
{
    local prog=$1

    LOG_INFO "Generating documentation for '%s'..." "${prog}"

    mkdir -p "doc/${prog}/"
    
    printf "\\n\\n\\n\\n\\nExecuting 'doxygen src/%s/doxygen.conf':\\n\\n" "${prog}" >> build.log

    doxygen "src/${prog}/doxygen.conf" >> build.log 2>&1

    if [ $? -eq 0 ]; then
        LOG_INFO "Finished successfully!"
    else
        LOG_ERROR_AND_EXIT "Finished with an error! See 'build.log' for detailed output messages!"
    fi

    ln -s "${prog}/html/index.html" "doc/${prog}.html"
}

build()
{
    local prog=$1
    local cmd=$2

    LOG_INFO "Building '%s'...\\e[0m" "${prog}"
    
    printf "\\n\\n\\n\\n\\nExecuting '%s':\\n\\n" "${cmd}" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        LOG_INFO "Build was successful!"
    else
        LOG_ERROR_AND_EXIT "Build failed! See 'build.log' for detailed output messages!"
    fi

    cd "../.." || exit;
}

clean()
{
    local prog=$1
    local cmd=$2

    LOG_INFO "Cleaning '%s'..." "${prog}"
    
    printf "\\n\\n\\n\\n\\nExecuting '%s':\\n\\n" "${cmd}" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        LOG_INFO "Cleaned successfully!"
    else
        LOG_ERROR_AND_EXIT "Cleaning failed! See 'build.log' for detailed output messages!"
    fi

    cd "../.." || exit;
}

generate_all_docs()
{
    rm -rf doc/

    generate_doc "CVerbsBench"
    generate_doc "JSocketBench"
    generate_doc "JVerbsBench"
    generate_doc "DisniBench"
}

build_all()
{
    build "CVerbsBench" "./build.sh"

    if [ -z "${JAVA_PATH}" ]; then
        build "JSocketBench" "./gradlew build"
        build "DisniBench" "./gradlew shadowJar"
    else
        build "JSocketBench" "./gradlew build -Dorg.gradle.java.home=${JAVA_PATH}"
        build "DisniBench" "./gradlew shadowJar -Dorg.gradle.java.home=${JAVA_PATH}"
    fi

    if [ -z "${J9_JAVA_PATH}" ]; then
        build "JVerbsBench" "./gradlew build"
    else
        build "JVerbsBench" "./gradlew build -Dorg.gradle.java.home=${J9_JAVA_PATH}"
    fi
}

clean_all()
{
    clean "CVerbsBench" "rm -rf build/"
    clean "JSocketBench" "./gradlew clean"
    clean "JVerbsBench" "./gradlew clean"
    clean "DisniBench" "./gradlew clean"
}

##################################################################
# Main entry point
##################################################################

source "log.sh"

LOG_INFO "Running automatic build script!"
LOG_INFO "version: %s(%s) - git %s, date: %s!" "${GIT_VERSION}" "${GIT_BRANCH}" "${GIT_REV}" "${DATE}"

printf "\\n"

parse_args "$@"
check_config

printf "\\n"

printf "Log from %s" "${DATE}" > build.log

case $MODE in
    build)
        build_all
        ;;
    doc)
        generate_all_docs
        ;;
    clean)
        clean_all
        ;;
    *)
        LOG_ERROR "Unknown mode '%s'\\n" "${MODE}"
        print_usage
        exit 1
esac

printf "\\n"

LOG_INFO "See 'build.log' for detailed output messages!"

exit 0
