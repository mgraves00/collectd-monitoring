#!/bin/sh

# plugin to read NSD stats and report to collectd

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

NSDCTL=/usr/sbin/nsd-control
HOSTNAME=${COLLECTD_HOSTNAME:-$(hostname)}
INTERVAL=${COLLECTD_INTERVAL:-60}
TMPFILE=$(mktemp)
PROG="nsd"
LOG="/tmp/collectd-nsd.log"
DEBUG=0

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

args=$(getopt -D $*)
# ignore any error
set -- $args
while [ $# -ne 0 ]; do
	case "$1" in
		-D) DEBUG=1; shift
			logit "COLLECTD_HOSTNAME=$COLLECTD_HOSTNAME"
			logit "COLLECTD_INTEFVAL=$COLLECTD_INTEFVAL"
			logit "TEMPFILE=$TMPFILE"
		;;
		--) shift; break;;
	esac
done


while sleep "${INTERVAL}"
do
	${NSDCTL} stats > $TMPFILE
	if [ $? -ne 0 ]; then
		# problem with getting stats
		logit "ERROR with NSDCTL"
		cleanup 1 "ERROR"
	fi
	D=$(date +"%s")
	# process query type
	cat $TMPFILE | sed -u -n -r "s~^num\.(type)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-qtype_\2 interval=${INTERVAL} $D:\3~p"
	# process query result
	cat $TMPFILE | sed -u -n -r "s~^num\.(rcode)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-qresult_\2 interval=${INTERVAL} $D:\3~p"
	# process error counters
	cat $TMPFILE | sed -u -n -r "s~^num\.(edns.*|answer.*|.xerr|raxfr|trunc.*|drop.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-qerror_\1 interval=${INTERVAL} $D:\2~p"
	# process query protocol
	cat $TMPFILE | sed -u -n -r "s~^num\.(udp6?|tcp6?|tls6?)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-qproto_\1 interval=${INTERVAL} $D:\2~p"
	# process master / slave zones
	cat $TMPFILE | sed -u -n -r "s~^zone\.(master|slave)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-zones_\1 interval=${INTERVAL} $D:\2~p"
	# process num queries total
	cat $TMPFILE | sed -u -n -r "s~^num\.(queries)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query_total interval=${INTERVAL} $D:\2~p"
	# process memory utilization
	cat $TMPFILE | sed -u -n -r "s~^size\.(.*)\.(.*)=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-server_\2_\1 interval=${INTERVAL} $D:\3~p"
	# number of server processes
	N=`cat $TMPFILE | grep -E "^server" | wc -l | tr -d " "`
	echo "PUTVAL ${HOSTNAME}/${PROG}/gauge-num_servers interval=${INTERVAL} $D:${N}" | cat -u
	# queries per server process
	cat $TMPFILE | sed -u -n -r "s~^server([0-9]+)\.queries=(.*)$~PUTVAL ${HOSTNAME}/${PROG}/gauge-query_server\1 interval=${INTERVAL} $D:\2~p"
done
# clean up
cleanup 0 "END"

