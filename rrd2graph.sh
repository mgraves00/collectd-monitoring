#!/bin/sh

# Basic script to generate an rrdcgi compatable script.  This is just enough
# to make an ugly graph from one or more RRD files.  Hand tuning is required.

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


## a list of colors for multi-value graphs
col[0]="00FF19"
col[1]="C6BE27"
col[2]="8F46AA"
col[3]="5B507A"
col[4]="5B618A"
col[5]="9EADC8"
col[6]="C3E79D"
col[7]="D6D84F"
col[8]="333333"
col[9]="48E5C2"
col[10]="F3D3BD"
col[11]="5E5E5E"
col[12]="46B1C9"
col[13]="84C0C6"
col[14]="9FB7B9"
col[15]="BCC1BA"

usage() {
cat << EOF
${0##*/} [-c <chroot dir>] [-b <begin time>] [-e <end time>] <file1.rrd [file2.rrd] ...>
EOF
}

XFILE=`mktemp`
incx() {
	local _x
	_x=`cat $XFILE`
	if [ -z "$_x" ]; then
		_x=0
	else
		_x=$((_x + 1))
	fi
	echo $_x > $XFILE
	echo $_x
}
cleanx() {
	[[ -f $XFILE ]] && rm -f $XFILE
}

GNAME="gname.png"
GTITLE=""
BEGIN="-1d"
END="now"
CHROOT=""

args=`getopt b:c:e:hn:t: $*`
if [ $? -ne 0 ]; then
	usage
	exit 2
fi
set -- $args
while [ $# -ne 0 ]; do
	case "$1" in
		-b)
			BEGIN=$2; shift; shift;;
		-c)
			CHROOT=$2; shift; shift;;
		-e)
			END=$2; shift; shift;;
		-h)
			usage; exit 0;;
		-n)
			GNAME=$2; shift; shift;;
		-t)
			GTITLE=$2; shift; shift;;
		--)
			shift; break;;
	esac
done

if [ $# -eq 0 ]; then
	echo "Nothing to do"
	usage
	exit 1
fi

# now output the header
cat << EOF
#!/usr/local/bin/rrdcgi
<RRD::GOODFOR 60>
<html>
<title></title>
<body>
<RRD::GRAPH $GNAME.png
  --title "$GTITLE"
  --start $BEGIN --end $END
EOF

# loop thru all files building graph
while [ $# -ne 0 ]; do
	file=$1
	rrdinfo $file | grep ^ds | sed -r -n 's/^ds\[(.*)\]\.type = "?([^"]+)"?$/\1 \2/p' | \
	while read val type; do
		rrd=${file##*/}
		name=${rrd%%.*}
		if [ ! -z "$CHROOT" ]; then
			file=${file##${CHROOT}}
		fi
		x=$(incx)
		printf "  DEF:ds%d=%s:%s:%s\n" $x $file $val "AVERAGE"
		printf "  VDEF:ds%dmax=ds%d,MAXIMUM\n" $x $x
		printf "  VDEF:ds%davg=ds%d,AVERAGE\n" $x $x
		printf "  VDEF:ds%dmin=ds%d,MINIMUM\n" $x $x
		printf "  LINE1:ds%d#${col[$x]}:\"%s %s\"\n" $x $name $val
		printf "  GPRINT:ds%davg:\"Avg\\\: %%6.2lf\"\n" $x
		printf "  GPRINT:ds%dmin:\"Min\\\: %%6.2lf\"\n" $x
		printf "  GPRINT:ds%dmax:\"Max\\\: %%6.2lf\\\\l\"\n" $x
	done
	shift
done

# output the footer
cat << EOF
>
</body>
</html>
EOF

# cleanup
cleanx

