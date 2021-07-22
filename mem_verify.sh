#!/bin/bash

# memverify
# check of oracle and linux memory parameters
# warnings appear for obvious errors

# assumes just 1 SGA - ignoring ASM for now

###################################
## SGA and GRANULE Size
##
## Choose the smallest Granule Size
## only complain if that one does not
## equally divide
## not perfect, but enough for now
###################################

unset SQLPATH
unset ORAENV_ASK

SGA=0

# this is 32G - should be sufficient for most databases
# just needs to be larger than the largest likely granule size
GRANULESIZE=34359738368

# cannot depend on oratab
# just connect to those instances that are currently running
# this assumes that there are instance specific entries in oratab in addition to the db entry
# some logic could be added to deal with that if necessary
#for SID in $(grep -P '^[A-Z]+\d{1}:' /etc/oratab | cut -f1 -d:)
for SID in $(ps -e -o cmd |  grep [p]mon | cut -d_ -f3 | grep -v '+ASM')
do

	. /usr/local/bin/oraenv <<< $SID

	TMPSGA=$(sqlplus -S /nolog <<-EOF
   	connect / as sysdba
   	set term on feed off head off  echo off verify off
   	ttitle off
   	btitle off
   	select value from v\$parameter where name = 'sga_max_size';
	EOF
	)

	# sqlplus adding a trailing LF
	TMPSGA=$( echo $TMPSGA | tr -d "[\012]" )
	(( SGA += TMPSGA ))


	TMP_GRANULESIZE=$(sqlplus -S /nolog <<-EOF
   	connect / as sysdba
   	set term on feed off head off  echo off verify off
   	ttitle off
   	btitle off
   	select granule_size from V_\$SGA_DYNAMIC_COMPONENTS where component = 'DEFAULT buffer cache';
	EOF
	)

	TMP_GRANULESIZE=$( echo $TMP_GRANULESIZE | tr -d "[\012]" )
	if [[ "$TMP_GRANULESIZE" -lt "$GRANULESIZE" ]]; then
		GRANULESIZE="$TMP_GRANULESIZE"
	fi
	

done


# sqlplus adding a trailing LF
GRANULESIZE=$( echo $GRANULESIZE | tr -d "[\012]" )

####################################
## total mem
####################################
# MemTotal is in K bytes
TOTALMEM=$(grep MemTotal /proc/meminfo | awk '{ print $2 }')
(( TOTALMEM = TOTALMEM * 1024 ))

####################################
## hugepages
####################################

HUGEPAGES=$( grep HugePages_Total /proc/meminfo | awk '{ print $2 }')
# hugepage size in in K
HUGEPAGE_SIZE=$(grep Hugepagesize /proc/meminfo | awk '{ print $2 }')
(( HUGEPAGE_BYTES = HUGEPAGES * HUGEPAGE_SIZE * 1024 ))

# shmall is in pages
# shmmax is in bytes

####################################
## shared mem
####################################

PAGESIZE=$(getconf PAGE_SIZE)
SHMMAX=$(cat /proc/sys/kernel/shmmax)
SHMALL=$(cat /proc/sys/kernel/shmall)
(( SHMALL_BYTES=SHMALL * PAGESIZE ))

####################################
## memlock
####################################

# value is in k
SOFT_MEMLOCK=$(grep 'oracle.*soft.*memlock' /etc/security/limits.conf | grep -v '^#' |  awk '{ print $4 }')
HARD_MEMLOCK=$(grep 'oracle.*hard.*memlock' /etc/security/limits.conf | grep -v '^#' |  awk '{ print $4 }')
(( SOFT_MEMLOCK = SOFT_MEMLOCK * 1024 ))
(( HARD_MEMLOCK = HARD_MEMLOCK * 1024 ))


cat <<MEMINFO

OS:
        totalmem: $TOTALMEM

       hugepages: $HUGEPAGES
  hugepage_bytes: $HUGEPAGE_BYTES

    soft_memlock: $SOFT_MEMLOCK
    hard_memlock: $HARD_MEMLOCK

          shmmax: $SHMMAX
          shmall: $SHMALL_BYTES

The following should be true:

shmmax <= available memory
shmall <= available memory
SGA    <= hugepages
SGA <= memlock < available memory

Oracle:

  smallest granulesize: $GRANULESIZE
                   SGA: $SGA

MEMINFO

# is shmmax GT mem ?
[ "$SHMMAX" -gt "$TOTALMEM" ] && echo "Warning: shmmax of $SHMMAX  > totalmem of $TOTALMEM"

# is shmall GT mem ?
[ "$SHMALL_BYTES" -gt "$TOTALMEM" ] && echo "Warning: shmall of $SHMALL ( $SHMALL_BYTES bytes )  > totalmem of $TOTALMEM"

# is SGA GT hugepages?
[ "$SGA" -gt "$HUGEPAGE_BYTES" ] && echo "Warning: SGA of $SGA is > Hugepages of $HUGEPAGES ( $HUGEPAGE_BYTES bytes )"

# is sga <= memlock and memlock < memory ?
[ "$SGA" -le "$SOFT_MEMLOCK" -a "$SOFT_MEMLOCK" -lt "$TOTALMEM" ] || echo "Warning: SGA:SOFT_MEMLOCK:TOTALMEM imbalance"
[ "$SGA" -le "$HARD_MEMLOCK" -a "$HARD_MEMLOCK" -lt "$TOTALMEM" ] || echo "Warning: SGA:HARD_MEMLOCK:TOTALMEM imbalance"

# is SGA multiple of granule?
# returned value should be 0 if SGA is evenly dvisible by granule
DIFF=$( perl -e '{ my($sga,$granule)=($ARGV[0],$ARGV[1]); my $x= int($sga/$granule); my $y = $sga/$granule; print $y-$x }' $SGA $GRANULESIZE )
[ "$DIFF" -eq 0 ] || echo "Warning: SGA of $SGA is not evenly divisible by the granulesize of $GRANULESIZE"

### end
echo
echo 'All OK if no warnings shown'
echo

