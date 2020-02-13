
# HugePages utilities for Oracle

## memory_verify.sh

Use the mem_verify.sh script to help verify and configure HugePages on Linux servers used for Oracle.

Example usage:

```text

[oracle@oravm01 hugepages]$ ./mem_verify.sh


OS:
        totalmem: 5201707008

       hugepages: 800
  hugepage_bytes: 1677721600

    soft_memlock: 41943030
        in bytes: 42949662720
    hard_memlock: 41943030
        in bytes: 42949662720

          shmmax: 68719476736
          shmall: 4294967296
    shmall bytes: 17592186044416

        pagesize: 4096

The following should be true:

shmmax <= available memory
shmall <= available memory
SGA    <= hugepages
SGA <= memlock < available memory

Oracle:

  granulesize: 16777216
          SGA: 1660944384

Warning: shmmax of 68719476736  > totalmem of 5201707008
   Set shmmax to 5201707008 or less

Warning: shmall of 4294967296 ( 17592186044416 bytes )  > totalmem of 5201707008
   Set shmall to 1269948 or less

Warning: SGA:SOFT_MEMLOCK:TOTALMEM imbalance
  Should be: SGA <= soft_memlock < Total Memory
  Adjust 'oracle soft memlock 5078768' in /etc/security/limits.conf

Warning: SGA:HARD_MEMLOCK:TOTALMEM imbalance
  Should be: SGA <= hard memlock < Total Memory
  Adjust 'oracle hard memlock 5078768' in /etc/security/limits.conf

Warning: Configured SGA is larger than Configured HugePages
  Set HugePages to 792 or more
  Adjust vm.nr_hugepages=792 in /etc/sysctl.conf


use 'sysctl -p' to reload configuration
changes to hugepages config will require server reboot


All OK if no warnings shown

memory_target and memory_max_target are not compatible with HugePages
Estimating SGA and PGA settings for any instances found using the memory target parameters

```

## oracle-hugepages-usage.pl

Show usage of HugePages by Oracle

Linux only, 2.6.14+ kernel 

This script works by parsing the /proc/PID/smaps file

See `man proc` for details.

No HugePages usage by Oracle:

```text

[root@ora192rac01 tmp]# ./oracle-hugepages-usage.pl

#################### Working on 5583 ####################

PID: 5583
CMD: asm_pmon_+asm1
No HugeTables usage found

#################### Working on 6021 ####################

PID: 6021
CMD: ora_pmon_cdb1
No HugeTables usage found

```

Some HugePages usage by Oracle

```text
[root@rac19c01 tmp]# ./oracle-hugepages-usage.pl

#################### Working on 28862 ####################

PID: 28862
CMD: asm_pmon_+asm1
No HugeTables usage found

#################### Working on 29872 ####################

PID: 29872
CMD: ora_pmon_cdb1
==================================================
PageSize:      2048 kB
Size:               10240 kB
AnonPages (should be 0):           0 kB
==================================================
PageSize:      2048 kB
Size:                8192 kB
AnonPages (should be 0):           0 kB
==================================================
PageSize:      2048 kB
Size:             3063808 kB
AnonPages (should be 0):           0 kB

```

If there are no Oracle PMON processes, there will be no output:

```text

$ ~/oracle/hugepages/memory-verify $ ./oracle-hugepages-usage.pl

```




