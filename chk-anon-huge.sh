#!/bin/bash

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
		grep '[always]' $anonFileToChk >/dev/null && {
			#echo anonymous HugePages are enabled
			anonHugePagesEnabled=1
		}
	fi

	# return code - will be either 0 or 1
	echo $(( anonHugePagesConfigured * anonHugePagesEnabled ))

}

r=$(chkAnonHuge)

echo "r: $r"


