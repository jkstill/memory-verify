#!/usr/bin/bash

# test regex for pulling memlock from /etc/security/limits.conf

# duplicate entries may appear in the file
# the following are duplicates for 'oracle soft memlock'
# the second one of 1078768 will be the one used by the system
#
# oracle soft memlock 5078768
# oracle soft memlock 1078768

# Test Variables
TOTALMEM=33554432
(( TOTALMEM_BYTES = TOTALMEM * 1024 ))
LIMITS_FILE=limits-test.conf
#######################################

# from the limits.conf man page
#  All items support the values -1, unlimited or infinity indicating no limit, except for priority and nice.

SOFT_MEMLOCK=$( grep -E '^oracle.*soft.*memlock.*(unlimited|infinity|-1)|^oracle.*soft.*memlock.*[0-9]++' $LIMITS_FILE | tail -1 | awk '{ print $4 }')
if [[ -z $SOFT_MEMLOCK ]]; then
	SOFT_MEMLOCK=$( grep -E '^\*.*soft.*memlock.*(unlimited|infinity|-1)|^\*.*soft.*memlock.*[0-9]+' $LIMITS_FILE | tail -1 | awk '{ print $4 }')
fi
[[ $(echo $SOFT_MEMLOCK | grep -E 'unlimited|infinity|-1') ]] && SOFT_MEMLOCK=$TOTALMEM

HARD_MEMLOCK=$( grep -E '^oracle.*hard.*memlock.*(unlimited|infinity|-1)|^oracle.*hard.*memlock.*[0-9]+' $LIMITS_FILE  | tail -1 | awk '{ print $4 }')
if [[ -z $HARD_MEMLOCK ]]; then
	HARD_MEMLOCK=$( grep -E '^\*.*hard.*memlock.*(unlimited|infinity|-1)|^\*.*hard.*memlock.*[0-9]+' $LIMITS_FILE  | tail -1 | awk '{ print $4 }')
fi
[[ $(echo $HARD_MEMLOCK | grep -E '(unlimited|infinity|-1)|infinity|-1') ]] && HARD_MEMLOCK=$TOTALMEM

[[ -z $SOFT_MEMLOCK ]] && SOFT_MEMLOCK=0
[[ -z $HARD_MEMLOCK ]] && HARD_MEMLOCK=0

(( SOFT_MEMLOCK_BYTES = SOFT_MEMLOCK * 1024 ))
(( HARD_MEMLOCK_BYTES = HARD_MEMLOCK * 1024 ))


cat <<MEMINFO

OS:
        totalmem: $TOTALMEM
        in bytes: $TOTALMEM_BYTES

    soft_memlock: $SOFT_MEMLOCK
        in bytes: $SOFT_MEMLOCK_BYTES
    hard_memlock: $HARD_MEMLOCK
        in bytes: $HARD_MEMLOCK_BYTES

MEMINFO


