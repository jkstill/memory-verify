#!/bin/bash

# memverify
# check of oracle and linux memory parameters
# warnings appear for obvious errors

function getOraValue() {
	declare -r SQL=$*

#echo "SQL: $SQL" >&2

	# attemtps to redirector the STDERR here have failed for some reason
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


function chkAnonHuge () {

: <<'PYTHDOC'

check for anonymous huge pages
see Oracle Support Note:
  ALERT: Disable Transparent HugePages on SLES11, RHEL6, RHEL7, OL6, OL7 and UEK2 Kernels (Doc ID 1557478.1)

The note contains a recommendation to check /proc/meminfo as one method to detect Anonymous HugePages,
but that method is only reliable if some Anonymous HugePages have actually been allocated.

PYTHDOC

	declare -a anonConfigFiles=(
		[0]='/sys/kernel/mm/redhat_transparent_hugepage/enabled'
		[1]='/sys/kernel/mm/transparent_hugepage/enabled'
	)

	declare fileCount=${#anonConfigFiles[@]}

	declare i=0

	declare anonFileToChk=''

	while [[ $fileCount -gt $i ]]
	do
		#echo $i: ${anonConfigFiles[$i]}
		[[ -r ${anonConfigFiles[$i]} ]] && {
			anonFileToChk=${anonConfigFiles[$i]}
			break
		}
		(( i++ ))
	done

	#echo anonFileToChk: $anonFileToChk

: <<'ANONCHK'

check the contents of file anonFileToChk

'[always] never': Anonymous HugePages should be disabled.

'always [never]': Anonymous HugePages are configured in the kernel, but disabled.

If the file does not even exist, that Anonymous HugePages are not configured and can be ignored.

ANONCHK

	declare anonHugePagesConfigured=1
	[[ -z $anonFileToChk ]] && anonHugePagesConfigured=0

	#echo anonHugePagesConfigured: $anonHugePagesConfigured

	declare anonHugePagesEnabled=0

	if [[ $anonHugePagesConfigured -gt 0 ]]; then
		grep '\[always\]' $anonFileToChk >/dev/null && {
			#echo anonymous HugePages are enabled
			anonHugePagesEnabled=1
		}
	fi

	# return code - will be either 0 or 1
	echo $(( anonHugePagesConfigured * anonHugePagesEnabled ))

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

# the method of using oratab just too error prone
#for SID in $(grep -P '^[A-Za-z0-9]+\d*:' /etc/oratab | cut -f1 -d:)
# next line had a bug - sid needs to be uppercase, but was lower case
# well spotted by Fred Denis
for SID in $(ps -e -ocmd | grep [r]a_pmon | sed -e 's/ora_pmon_//'| grep -v -- 'sed -e')
do
	echo "Working on $SID"

	. oraenv <<< $SID >/dev/null

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

done



###################################
## GRANULE
###################################

GRANULESIZE=$(getGranuleSize)

# may get the query returned as a result if error

granuleChk=$(echo $GRANULESIZE | grep -i 'select' )

# avoid divide by 0 later in perl
if [[ -n $granuleChk ]]; then
	GRANULESIZE=1
fi


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
LIMITS_FILE='/etc/security/limits.conf'

# from the limits.conf man page
#  All items support the values -1, unlimited or infinity indicating no limit, except for priority and nice.

UNLIMITED_REGEX='unlimited|infinity|-1'

SOFT_MEMLOCK=$( grep -E "^oracle.*soft.*memlock.*($UNLIMITED_REGEX)|^oracle.*soft.*memlock.*[0-9]++" $LIMITS_FILE | tail -1 | awk '{ print $4 }')
if [[ -z $SOFT_MEMLOCK ]]; then
	SOFT_MEMLOCK=$( grep -E "^\*.*soft.*memlock.*($UNLIMITED_REGEX)|^\*.*soft.*memlock.*[0-9]+" $LIMITS_FILE | tail -1 | awk '{ print $4 }')
fi
[[ $(echo $SOFT_MEMLOCK | grep -E "$UNLIMITED_REGEX") ]] && SOFT_MEMLOCK=$TOTALMEM

HARD_MEMLOCK=$( grep -E "^oracle.*hard.*memlock.*($UNLIMITED_REGEX)|^oracle.*hard.*memlock.*[0-9]+" $LIMITS_FILE  | tail -1 | awk '{ print $4 }')
if [[ -z $HARD_MEMLOCK ]]; then
	HARD_MEMLOCK=$( grep -E "^\*.*hard.*memlock.*($UNLIMITED_REGEX)|^\*.*hard.*memlock.*[0-9]+" $LIMITS_FILE  | tail -1 | awk '{ print $4 }')
fi
[[ $(echo $HARD_MEMLOCK | grep -E "$UNLIMITED_REGEX") ]] && HARD_MEMLOCK=$TOTALMEM

[[ -z $SOFT_MEMLOCK ]] && SOFT_MEMLOCK=0
[[ -z $HARD_MEMLOCK ]] && HARD_MEMLOCK=0

(( SOFT_MEMLOCK_BYTES = SOFT_MEMLOCK * 1024 ))
(( HARD_MEMLOCK_BYTES = HARD_MEMLOCK * 1024 ))


cat <<MEMINFO

OS:
        totalmem: $TOTALMEM
        in bytes: $TOTALMEM_BYTES

       hugepages: $HUGEPAGES
        pagesize: $((HUGEPAGE_SIZE * 1024))
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
	echo "  Adjust 'oracle soft memlock $RECSIZE' in $LIMITS_FILE"
	echo
}

[ "$SGA" -le "$HARD_MEMLOCK_BYTES" -a "$HARD_MEMLOCK_BYTES" -le "$TOTALMEM_BYTES" ] || {
	echo "Warning: SGA:HARD_MEMLOCK:TOTALMEM imbalance"
	RECSIZE=$(( ($TOTALMEM_BYTES / 1024 ) - 1024 ))
	echo "  Should be: SGA <= hard memlock < Total Memory"
	echo "  Adjust 'oracle hard memlock $RECSIZE' in $LIMITS_FILE"
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
#echo "SGA: |$SGA|"
#echo "GRANULESIZE: |$GRANULESIZE|"

DIFF=$( perl -e '{ my($sga,$granule)=($ARGV[0],$ARGV[1]); my $x= int($sga/$granule); my $y = $sga/$granule; print $y-$x }' $SGA $GRANULESIZE )
[[ -z $DIFF ]] && DIFF=0
[[ "$DIFF" -eq 0 ]] || echo "Warning: SGA of $SGA is not evenly divisible by the granulesize of $GRANULESIZE"

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

# show configured instances
echo
echo "##################################"
echo "## Configured Instances ##########"
echo "##################################"
grep '^[A-Za-z]' /etc/oratab
echo

# show active instances
echo "##################################"
echo "## Active Instances ##############"
echo "##################################"
ps -e -ocmd | grep [o]ra_pmon

echo 

if [[ $(chkAnonHuge) -gt 0 ]]; then
cat <<-CHK4ANON

!!!!!!!!!!!!!!!
!! Important !!
!!!!!!!!!!!!!!!

The use of Anonymous HugePages has been detected on this server.
Anonymous HugePages are not compatible with Oracle and should be disabled.

Please see the following Oracle Support Note:

  ALERT: Disable Transparent HugePages on SLES11, RHEL6, RHEL7, OL6, OL7 and UEK2 Kernels (Doc ID 1557478.1)
  
CHK4ANON

fi


