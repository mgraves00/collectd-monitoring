#!/bin/sh

# plugin to read Unbound stats and report to collectd

# Copyright 2020 Michael Graves
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

PROG="unbound"
PROGCTL=/usr/sbin/${PROG}-control
CMD="stats"
HOSTNAME=${COLLECTD_HOSTNAME:-$(hostname)}
INTERVAL=${COLLECTD_INTERVAL:-60}
TMPFILE=$(mktemp)
LOG="/tmp/collectd-${PROG}.log"
DEBUG=0
PERTHREAD=0
EXTENDED=0

trap "cleanup 1 HUP" HUP
trap "cleanup 1 INT" INT
trap "cleanup 1 QUIT" QUIT
trap "cleanup 0 TERM" TERM
trap "cleanup 1 PIPE" PIPE
trap "cleanup 1 STOP" STOP

cleanup() {
	RC=${1:-0}
	logit "cleanup called $2"
	rm -f $TMPFILE
	exit $RC
}
logit() {
	[[ $DEBUG -ne 0 ]] && echo "$*" >> $LOG
}

args=$(getopt -DET $*)
# ignore any error
set -- $args
while [ $# -ne 0 ]; do
	case "$1" in
		-D) DEBUG=1; shift
			logit "COLLECTD_HOSTNAME=$COLLECTD_HOSTNAME"
			logit "COLLECTD_INTERVAL=$COLLECTD_INTERVAL"
			logit "TEMPFILE=$TMPFILE"
		    CMD="stats_noreset"
		;;
		-E) EXTENDED=1; shift ;;
		-T) PERTHREAD=1; shift ;;
		--) shift; break;;
	esac
done


while sleep "${INTERVAL}"
do
	${PROGCTL} ${CMD} > $TMPFILE
	if [ $? -ne 0 ]; then
		# problem with getting stats
		logit "ERROR with ${PROGCTL}"
		cleanup 1 "ERROR"
	fi
	D=$(date +"%s")
	# process totals
	cat $TMPFILE | sed -u -n -r "s~^total\.(num)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-num_\2 interval=${INTERVAL} $D:\3~p"
	cat $TMPFILE | sed -u -n -r "s~^total\.(requestlist)\.([^\.]+)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-reqlist_\2 interval=${INTERVAL} $D:\3~p"
	cat $TMPFILE | sed -u -n -r "s~^total\.(recursion)\.time\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-rectime_\2 interval=${INTERVAL} $D:\3~p"

	if [ ${EXTENDED} -ne 0 ]; then
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.type\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-type-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.authzone\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-authzone-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.edns\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-edns-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.class\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-class-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.opcode\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-opcode-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.aggressive\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-aggressive-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.(tcp|tcpout|tls|ipv6|ratelimit|subnet|subnet_cache)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.tls\.resume=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-tlsresume interval=${INTERVAL} $D:\1~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.query\.flags\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query-flags-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.answer\.rcode\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-answer-rcode-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^num\.answer\.(bogus|secure)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-answer-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^(rrset|msg|infra|key)\.cache\.count=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/count-cache-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^unwanted\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-unwanted-\1 interval=${INTERVAL} $D:\2~p"
		cat $TMPFILE | sed -u -n -r "s~^mem\.(mod|cache)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-mem-\1-\2 interval=${INTERVAL} $D:\3~p"
	fi
	if [ ${PERTHREAD} -ne 0 ]; then
		cat $TMPFILE | sed -u -n -r "s~^thread([0-9]+)\.(num)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-thread\1_num_\3 interval=${INTERVAL} $D:\4~p"
		cat $TMPFILE | sed -u -n -r "s~^thread([0-9]+)\.(requestlist)\.([^\.]+)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-thread\1_reqlist_\3 interval=${INTERVAL} $D:\4~p"
		cat $TMPFILE | sed -u -n -r "s~^thread([0-9]+)\.(recursion)\.time\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-thread\1_rectime_\3 interval=${INTERVAL} $D:\4~p"
	fi
done
# clean up
cleanup 0 "END"

