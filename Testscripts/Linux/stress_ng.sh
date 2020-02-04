#!/bin/bash

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

HOMEDIR=$(pwd)
LogMsg()
{
	echo "[$(date +"%x %r %Z")] ${1}"
	echo "[$(date +"%x %r %Z")] ${1}" >> "${HOMEDIR}/runlog.txt"
}

CONSTANTS_FILE="$HOMEDIR/constants.sh"
UTIL_FILE="$HOMEDIR/utils.sh"

. ${UTIL_FILE} || {
	errMsg="Error: missing ${UTIL_FILE} file"
	LogMsg "${errMsg}"
	SetTestStateAborted
	exit 10
}
UtilsInit

############################################################
# Main body
############################################################

HOMEDIR=$HOME
SetTestStateRunning
LogMsg "Start installing stress-ng."
install_stressng $stressng_version

if [ $? -ne 0 ]; then
	LogErr "Install stressng failed."
	SetTestStateAborted
	exit 1
fi

stress-ng --version
if [ $? -ne 0 ]; then
	LogErr "stress-ng not installed successfully".
	SetTestStateAborted
	exit 0
fi
LogMsg "stress-ng installed successfully."
LogMsg "Delete *.yaml file."
rm -rf *.yaml

declare -A tests_Dic
tests_Dic=(
[cpu]="--af-alg 0 --atomic 0 --bsearch 0 --context 0 --cpu 0 --crypt 0 --fp-error 0 --getrandom 0 --heapsort 0 --hsearch 0 \
--longjmp 0 --lsearch 0 --matrix 0 --mergesort 0 --nop 0 --numa 0 --opcode 0 --qsort 0 --rdrand 0 --str 0 --stream 0 --tsc 0 --tsearch 0 --vecmath 0 \
--wcs 0 --zlib 0"
[hot-cpu]="--ignite-cpu --aggressive --times --tz --cpu 0 --matrix 0"
[cpu-cache]="--bsearch 0 --cache 0 --heapsort 0 --hsearch 0 --icache 0 --lockbus 0 --lsearch 0 --malloc 0 --matrix 0 --membarrier 0 \
--memcpy 0 --mergesort 0 --qsort 0 --str 0 --stream 0 --tsearch 0 --vecmath 0 --wcs 0 --zlib 0"
[device]="--dev 0 --full 0 --null 0 --urandom 0 --zero 0 --zero-ops 1000000"
[filesystem]="--bind-mount 0 --chdir 0 --chmod 0 --chown 0 --copy-file 0 --dentry 0 --dir 0 --dirdeep 0 --dnotify 0 --dup 0 --eventfd 0 \
--fallocate 0 --fanotify 0 --fcntl 0 --fiemap 0 --filename 0 --flock 0 --fstat 0 --getdent 0 --handle 0 --inotify 0 --io 0 --iomix 0 --ioprio 0 --lease 0 \
--link 0 --locka 0 --lockf 0 --lockofd 0 --mknod 0 --open 0 --procfs 0 --rename 0 --symlink 0 --sync-file 0 --utime 0 --xattr 0"
[interrupt]="--aio 0 --aiol 0 --clock 0 --fault 0 --itimer 0 --kill 0 --schedpolicy 0 --sigfd 0 --sigfpe 0 --sigpending 0 --sigq 0 --sigsegv 0 \
--sigsuspend 0 --sleep 0 --timer 0 --timerfd 0"
[io]="--aio 0 --aiol 0 --hdd 0 --readahead 0 --seek 0 --sync-file 0"
[matrix-methods]="--tz --matrix 0 --matrix-method all --matrix 0 --matrix-method add --matrix 0 --matrix-method copy --matrix 0 --matrix-method div \
--matrix 0 --matrix-method frobenius --matrix 0 --matrix-method hadamard --matrix 0 --matrix-method mean --matrix 0 --matrix-method mult --matrix 0 --matrix-method prod --matrix 0 \
--matrix-method sub --matrix 0 --matrix-method trans"
[memory]="--atomic 0 --bsearch 0 --context 0 --full 0 --heapsort 0 --hsearch 0 --lockbus 0 --lsearch 0 --malloc 0 --matrix 0 --membarrier 0 --memcpy 0 \
--memfd 0 --memthrash 0 --mergesort 0 --mincore 0 --null 0 --numa 0 --oom-pipe 0 --pipe 0 --qsort 0 --remap 0 --resources 0 --rmap 0 --stack 0 --stackmmap 0 --str 0 \
--stream 0 --tlb-shootdown 0 --tlb-shootdown-ops 1000000 --tmpfs 0 --tsearch 0 --vm 0 --vm-rw 0 --wcs 0 --zero 0 --zlib 0"
[network]="--fifo 0 --dccp 0 --epoll 0 --icmp-flood 0 --sctp 0 --sock 0 --sockfd 0 --sockpair 0 --udp 0 --udp-flood 0"
[pipe]="--fifo 0 --pipe 0 --sendfile 0 --splice 0 --tee 0 --vm-splice 0"
[scheduler]="--affinity 0 --affinity-rand --clone 0 --daemon 0 --dnotify 0 --eventfd 0 --exec 0 --fanotify 0 --fault 0 --fifo 0 --fork 0 --futex 0 \
--inotify 0 --kill 0 --mmapfork 0 --mq 0 --msg 0 --netlink-proc 0 --nice 0 --poll 0 --pthread 0 --schedpolicy 0 --sem 0 --sem-sysv 0 --sleep 0 --spawn 0 --switch 0 \
--tee 0 --vfork 0 --vforkmany 0 --wait 0 --yield 0 --zombie 0"
[security]="--apparmor 0"
[vm]="--bigheap 0 --brk 0 --madvise 0 --malloc 0 --mlock 0 --mmap 0 --mmapfork 0 --mmapmany 0 --mremap 0 --msync 0 --shm 0 --shm-sysv 0 --stack 0 \
--stackmmap 0 --tmpfs 0 --userfaultfd 0 --vm 0 --vm-rw 0 --vm-splice 0"
)
common_cmd="--metrics-brief --perf --sequential 0 --timeout 60s"
for key in $(echo ${!tests_Dic[*]})
do
	LogMsg "Start $key testing."
	full_cmd="--yaml $key.yaml $common_cmd ${tests_Dic[$key]}"
	LogMsg "stress-ng $full_cmd"
	stress-ng $full_cmd
	if [ $? -ne 0 ]; then
		LogErr "stress-ng - $full_cmd run test failed"
		SetTestStateFailed
		exit 0
	fi
	LogMsg "Finish $key testing, results are redirect to file $key.yaml."
done

SetTestStateCompleted
