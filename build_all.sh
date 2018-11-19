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
        Set the path to your default JDK, which will be used to build JSocketBench.
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
            printf "Unknown option '%s'\\n" "${arg}"
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

    printf "\\e[92mChecking configuration...\\e[0m\\n\\n"
    
    java_version=$("${JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    j9_java_valid=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | grep "IBM J9 VM");
    j9_java_version=$("${J9_JAVA_PATH}/bin/java" -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')

    if [ -z "${java_version}" ]; then
        printf "\\e[91m'%s' does not seem to contain a valid JDK!\\e[0m\\n" "${JAVA_PATH}"
        exit 1 
    fi

    if [ -z "${j9_java_version}" ]; then
        printf "\\e[91m'%s' does not seem to contain a valid JDK!\\e[0m\\n" "${J9_JAVA_PATH}"
        exit 1
    fi

    if [ -z "${j9_java_valid}" ]; then
        printf "\\e[91m'%s' does not seem to contain a valid IBM JDK!\\e[0m\\n" "${J9_JAVA_PATH}"
        exit 1
    fi

    if [ "${java_version}" -lt 18 ]; then
        printf "\\e[91m'%s' implements a version of java older than 1.8 (determined version %u)!\\e[0m\\n" "${JAVA_PATH}" "${java_version}"
        exit 1
    else
        printf "\\e[92mDefault JVM: '%s' - Determined version: %u --> [VALID]\\n" "${JAVA_PATH}" "${java_version}"
    fi

    if [ "${j9_java_version}" -lt 18 ]; then
        printf "\\e[91m'%s' implements a version of java older than 1.8 (determined version %u)!\\e[0m\\n" "${J9_JAVA_PATH}" "${j9_java_version}"
        exit 1
    else
        printf "\\e[92mIBM J9 JVM: '%s' - Determined version: %u --> [VALID]\\n" "${J9_JAVA_PATH}" "${j9_java_version}"
    fi

    printf "\\n\\e[92mConfiguration seems to be valid!\\e[0m\\n\\n"
}

generate_doc()
{
    local prog=$1

    printf "\\n\\e[92mGenerating documentation for '%s'...\\e[0m\\n" "${prog}"

    mkdir -p "doc/${prog}/"
    
    printf "\\n\\n\\n\\n\\nExecuting 'doxygen src/%s/doxygen.conf':\\n\\n" "${prog}" >> build.log

    doxygen "src/${prog}/doxygen.conf" >> build.log 2>&1

    if [ $? -eq 0 ]; then
        printf "\\e[92mFinished successfully!\\e[0m\\n"
    else
        printf "\\e[91mFinished with an error!\\e[0m\\n"
        printf "\\n\\e[94mSee 'build.log' for detailed output messages!\\e[0m\\n"
        exit 1
    fi

    ln -s "${prog}/html/index.html" "doc/${prog}.html"
}

build()
{
    local prog=$1
    local cmd=$2

    printf "\\n\\e[92mBuilding '%s'...\\e[0m\\n" "${prog}"
    
    printf "\\n\\n\\n\\n\\nExecuting '%s':\\n\\n" "${cmd}" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        printf "\\e[92mBuild successful!\\e[0m\\n"
    else
        printf "\\e[91mBuild failed!\\e[0m\\n"
        printf "\\n\\e[94mSee 'build.log' for detailed output messages!\\e[0m\\n"
        exit 1
    fi

    cd "../.." || exit;
}

clean()
{
    local prog=$1
    local cmd=$2
    
    printf "\\n\\e[92mCleaning '%s'...\\e[0m\\n" "${prog}"
    
    printf "\\n\\n\\n\\n\\nExecuting '%s':\\n\\n" "${cmd}" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        printf "\\e[92mCleaned successful!\\e[0m\\n"
    else
        printf "\\e[91mCleaning failed!\\e[0m\\n"
        printf "\\n\\e[94mSee 'build.log' for detailed output messages!\\e[0m\\n"
        exit 1
    fi

    cd "../.." || exit;
}

generate_all_docs()
{
    rm -rf doc/

    generate_doc "CVerbsBench"
    generate_doc "JSocketBench"
    generate_doc "JVerbsBench"
}

build_all()
{
    build "CVerbsBench" "./build.sh"

    if [ -z "${JAVA_PATH}" ]; then
        build "JSocketBench" "./gradlew build"
    else
        build "JSocketBench" "./gradlew build -Dorg.gradle.java.home=${JAVA_PATH}"
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
}

printf "\\e[94mRunning automatic build script!\\e[0m\\n"
printf "\\e[94mversion: %s(%s) - git %s, date: %s!\\e[0m\\n\\n" "${GIT_VERSION}" "${GIT_BRANCH}" "${GIT_REV}" "${DATE}"

parse_args "$@"
check_config

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
        printf "Unknown mode '%s'\\n" "${MODE}"
        print_usage
        exit 1
esac

printf "\\n\\e[94mSee 'build.log' for detailed output messages!\\e[0m\\n"

exit 0
