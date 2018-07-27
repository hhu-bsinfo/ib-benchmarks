#!/bin/bash

readonly GIT_REV="$(git rev-parse --short HEAD)"
readonly BUILD_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

MODE="build"
JAVA_PATH=""

print_usage()
{
    printf "Usage: ./build_all.sh [OPTION...]
    Available options:
    -m, --mode
        Set the operating mode to either 'build', 'doc' or 'clean' (default: build)
    -j, --java
        Set the path to your default JVM
    -h, --help
        Show this help message\n"
}

parse_opts()
{
    while [ "${1}" != "" ]; do
        local arg=$1
        local val=$2
        
        case $1 in
            -m|--mode)
            MODE=$val
            ;;
            -j|--java)
            JAVA_PATH=$val
            ;;
            -h|--help)
            print_usage
            exit 0
            ;;
            *)
            printf "Unknown option '${arg}'\n"
            print_usage
            exit 1
            ;;
        esac
        shift 2
    done
}

generate_doc()
{
    local prog=$1

    printf "\n\e[92mGenerating documentation for ${prog}...\e[0m\n"

    mkdir -p doc/${prog}/
    
    printf "\n\n\n\n\nExecuting 'doxygen src/${prog}/doxygen.conf':\n\n" >> build.log 2>&1

    doxygen src/${prog}/doxygen.conf >> build.log

    if [ $? -eq 0 ]; then
        printf "\e[92mFinished successfully!\e[0m\n"
    else
        printf "\e[91mFinished unsuccessfully!\e[0m\n"
        printf "\n\e[94mSee 'build.log' for detailed output messages!\e[0m\n"
        exit 1
    fi

    ln -s ${prog}/html/index.html doc/${prog}.html
}

build()
{
    local prog=$1
    local cmd=$2

    printf "\n\e[92mBuilding ${prog}...\e[0m\n"
    
    printf "\n\n\n\n\nExecuting '${cmd}':\n\n" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        printf "\e[92mBuild successful!\e[0m\n"
    else
        printf "\e[91mBuild unsuccessful!\e[0m\n"
        printf "\n\e[94mSee 'build.log' for detailed output messages!\e[0m\n"
        exit 1
    fi

    cd ../..
}

clean()
{
    local prog=$1
    local cmd=$2
    
    printf "\n\e[92mCleaning ${prog}...\e[0m\n"
    
    printf "\n\n\n\n\nExecuting '${cmd}':\n\n" >> build.log
    
    cd "src/${prog}" && $cmd >> ../../build.log 2>&1

    if [ $? -eq 0 ]; then
        printf "\e[92mCleaned successful!\e[0m\n"
    else
        printf "\e[91mCleaned unsuccessful!\e[0m\n"
        printf "\n\e[94mSee 'build.log' for detailed output messages!\e[0m\n"
        exit 1
    fi

    cd ../..
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
	build "JVerbsBench" "./gradlew build"
    else
        build "JSocketBench" "./gradlew build -Dorg.gradle.java.home=${JAVA_PATH}"
	build "JVerbsBench" "./gradlew build -Dorg.gradle.java.home=${JAVA_PATH}"
    fi
}

clean_all()
{
    clean "CVerbsBench" "rm -rf build/"
    clean "JSocketBench" "./gradlew clean"
    clean "JVerbsBench" "./gradlew clean"
}

printf "\e[94mRunning automatic build script!\e[0m\n"
printf "\e[94mBuild date: ${BUILD_DATE}, git ${GIT_REV}!\e[0m\n"

parse_opts $@

printf "Log from ${BUILD_DATE}" > build.log

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
        printf "Unknown mode '${MODE}'\n"
        print_usage
        exit 1
esac

printf "\n\e[94mSee 'build.log' for detailed output messages!\e[0m\n"

exit 0
