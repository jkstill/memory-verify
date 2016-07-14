#!/bin/bash

# memverify
# check of oracle and linux memory parameters
# warnings appear for obvious errors

function getOraValue() {
	declare -r SQL=$*

#echo "SQL: $SQL" >&2

	tmpResult=$(sqlplus -S /nolog <<-EOF
		connect / as sysdba
		set term on feed off head off  echo off verify off
		set timing off
		ttitle off
		btitle off
		$SQL;
	EOF
	)

	# sqlplus adding a trailing LF
	tmpResult=$( echo $tmpResult | tr -d "[\012]" )
	echo $tmpResult
}

function getOraParm() {
	declare -r parmName=$1
	declare SQL="select value from v\$parameter where name = '$parmName'"
	#echo "!!!!" >&2
	#echo "ParmName: $parmName" >&2
	#echo "!!!!" >&2

	parmValue=$(getOraValue $SQL)
	echo $parmValue
}

function getGranuleSize() {
	declare SQL="select granule_size from V_\$SGA_DYNAMIC_COMPONENTS where component = 'DEFAULT buffer cache'"
	declare granuleSize=$(getOraValue $SQL)
	echo $granuleSize
}

function getEstPGA() {
	declare SQL="select pga_target_for_estimate from v\$pga_target_advice where pga_target_factor = 1"
	declare pgaSize=$(getOraValue $SQL)
	echo $pgaSize
}

function getEstSGA() {
	declare SQL="select sum(value) from v\$sga";
	declare sgaSize=$(getOraValue $SQL)
	echo $sgaSize
}


###################################
## SGA
###################################

# if older version of Bash ( lt 4.x) there are no associative arrays
declare -a ORASIDS
declare -a ESTIMATE_MEM
IDX=0

unset SQLPATH
unset ORAENV_ASK

SGA=0

for SID in $(grep -P '^[A-Za-z0-9]+\d*:' /etc/oratab | cut -f1 -d:)
do

	# check to see if there is a corresponding active instance
	isActive=$(ps -e -ocmd | grep "^[o]ra_pmon_${SID}$")


	[[ -n $isActive ]] && {

		#echo "is Active: |$isActive|"
		#echo "Working on $SID"

		. oraenv <<< $SID >/dev/null

		echo
		TMPSGA=$(getOraParm 'sga_max_size')

		(( SGA += TMPSGA ))

		ORASIDS[$IDX]=$SID
		ESTIMATE_MEM[$IDX]=0

		MEMORY_TARGET=$(getOraParm 'memory_target')
		MEMORY_MAX_TARGET=$(getOraParm 'memory_max_target')

		[ "$MEMORY_TARGET" != '0' -o "$MEMORY_MAX_TARGET" != '0' ] && {
			ESTIMATE_MEM[$IDX]=1
		}

		(( IDX++ ))
	}

done



###################################
## GRANULE
###################################

# just hardcoding this for now
GRANULESIZE=$(getGranuleSize)

####################################
## total mem
####################################
# MemTotal is in K bytes
TOTALMEM=$(grep MemTotal /proc/meminfo | awk '{ print $2 }')
(( TOTALMEM_BYTES = TOTALMEM * 1024 ))

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
# if 'unlimited' then set to value of total memory
# grep -E 'oracle.*soft.*memlock.*unlimited|\*.*soft.*memlock.*unlimited' /etc/security/limits.conf
SOFT_MEMLOCK=$( grep -E '^oracle.*soft.*memlock.*unlimited|^\*.*soft.*memlock.*unlimited' /etc/security/limits.conf | awk '{ print $4 }')
[[ $SOFT_MEMLOCK == 'unlimited' ]] && SOFT_MEMLOCK=$TOTALMEM

HARD_MEMLOCK=$( grep -E '^oracle.*hard.*memlock.*unlimited|^\*.*hard.*memlock.*unlimited' /etc/security/limits.conf | awk '{ print $4 }')
[[ $HARD_MEMLOCK == 'unlimited' ]] && HARD_MEMLOCK=$TOTALMEM
(( SOFT_MEMLOCK_BYTES = SOFT_MEMLOCK * 1024 ))
(( HARD_MEMLOCK_BYTES = HARD_MEMLOCK * 1024 ))


cat <<MEMINFO

OS:
		  totalmem: $TOTALMEM
		  in bytes: $TOTALMEM_BYTES

		 hugepages: $HUGEPAGES
  hugepage_bytes: $HUGEPAGE_BYTES

	 soft_memlock: $SOFT_MEMLOCK
		  in bytes: $SOFT_MEMLOCK_BYTES
	 hard_memlock: $HARD_MEMLOCK
		  in bytes: $HARD_MEMLOCK_BYTES

			 shmmax: $SHMMAX
			 shmall: $SHMALL
	 shmall bytes: $SHMALL_BYTES

		  pagesize: $PAGESIZE

The following should be true:

shmmax <= available memory
shmall <= available memory
SGA	 <= hugepages
SGA <= memlock < available memory

Oracle:

  granulesize: $GRANULESIZE
			 SGA: $SGA

MEMINFO

# is shmmax GT mem ?
[ "$SHMMAX" -gt "$TOTALMEM_BYTES" ] && {
	echo "Warning: shmmax of $SHMMAX  > totalmem of $TOTALMEM_BYTES"
	echo "	Set shmmax to $TOTALMEM_BYTES or less in /etc/sysctl.conf"
	echo
}

# is shmall GT mem ?
[ "$SHMALL_BYTES" -gt "$TOTALMEM_BYTES" ] && {
	echo "Warning: shmall of $SHMALL ( $SHMALL_BYTES bytes )  > totalmem of $TOTALMEM_BYTES"
	echo "	Set shmall to" $(( TOTALMEM_BYTES / PAGESIZE )) "or less in /etc/sysctl.conf"
	echo
}

# is SGA GT hugepages?
[ "$SGA" -gt "$HUGEPAGE_BYTES" ] && echo "Warning: SGA of $SGA is > Hugepages of $HUGEPAGES ( $HUGEPAGE_BYTES bytes )" ;echo

# is sga <= memlock and memlock < memory ?
[ "$SGA" -le "$SOFT_MEMLOCK_BYTES" -a "$SOFT_MEMLOCK_BYTES" -le "$TOTALMEM_BYTES" ] || {
	echo "Warning: SGA:SOFT_MEMLOCK:TOTALMEM imbalance"
	RECSIZE=$(( ($TOTALMEM_BYTES / 1024 ) - 1024 ))
	echo "  Should be: SGA <= soft_memlock < Total Memory"
	echo "  Adjust 'oracle soft memlock $RECSIZE' in /etc/security/limits.conf"
	echo
}

[ "$SGA" -le "$HARD_MEMLOCK_BYTES" -a "$HARD_MEMLOCK_BYTES" -le "$TOTALMEM_BYTES" ] || {
	echo "Warning: SGA:HARD_MEMLOCK:TOTALMEM imbalance"
	RECSIZE=$(( ($TOTALMEM_BYTES / 1024 ) - 1024 ))
	echo "  Should be: SGA <= hard memlock < Total Memory"
	echo "  Adjust 'oracle hard memlock $RECSIZE' in /etc/security/limits.conf"
	echo
}

[ "$SGA" -gt "$HUGEPAGE_BYTES" ] && {
	echo "Warning: Configured SGA is larger than Configured HugePages"
	RECSIZE=$(( SGA / HUGEPAGE_SIZE / 1024 ))
	echo "  Set HugePages to $RECSIZE or more"
	echo "  Adjust vm.nr_hugepages=$RECSIZE in /etc/sysctl.conf"
	echo
}

# is SGA multiple of granule?
# returned value should be 0 if SGA is evenly dvisible by granule
DIFF=$( perl -e '{ my($sga,$granule)=($ARGV[0],$ARGV[1]); my $x= int($sga/$granule); my $y = $sga/$granule; print $y-$x }' $SGA $GRANULESIZE )
[ "$DIFF" -eq 0 ] || echo "Warning: SGA of $SGA is not evenly divisible by the granulesize of $GRANULESIZE"

echo
echo "use 'sysctl -p' to reload configuration"
echo "changes to hugepages config will require server reboot"
echo

### end
echo
echo 'All OK if no warnings shown'


echo
echo "memory_target and memory_max_target are not compatible with HugePages"
echo "Estimating SGA and PGA settings for any instances found using the memory target parameters"
echo

for idx in ${!ESTIMATE_MEM[@]}
do
	if [[ ${ESTIMATE_MEM[$idx]} -eq 1 ]]; then
		echo "SID: ${ORASIDS[$idx]}"

		# estimate PGA
		echo "  pga_aggregate_target: " $(getEstPGA)

		# estimate SGA
		echo "  sga_target_size: " $(getEstSGA)

		# use if 11g+
		# select value from v$parameter where name = 'use_large_pages'
		useLargePages=$(getOraParm 'use_large_pages')
		if [ "$useLargePages" == 'FALSE' ]; then
			echo "  set 'use_large_pages=TRUE'"
		fi

	fi
done

