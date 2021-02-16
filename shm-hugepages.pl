#!/usr/bin/env perl

use warnings;
use strict;
#use Data::Dumper;

=head1 shm-hugepages.pl

 This script attempts create shared memory segments using HugePages

   [oracle]$ perl shm.pl
   waiting for input

 In another session

   [root@boc-solver ~]# ipcs -m

   ------ Shared Memory Segments --------
   key        shmid      owner      perms      bytes      nattch     status
   0x00000000 4          oracle     700        4294967296 0

   [root@boc-solver ~]# grep Huge /proc/meminfo
   AnonHugePages:         0 kB
   HugePages_Total:    2048
   HugePages_Free:     2047
   HugePages_Rsvd:     2047
   HugePages_Surp:        0
   Hugepagesize:       2048 kB

 Now release the memory by pressing ENTER

   [oracle]$ perl shm.pl
   waiting for input
   [oracle]
   
 Check Memory again

   [root]# ipcs -m

   ------ Shared Memory Segments --------
   key        shmid      owner      perms      bytes      nattch     status

   [root]# grep Huge /proc/meminfo
   AnonHugePages:         0 kB
   HugePages_Total:    2048
   HugePages_Free:     2048
   HugePages_Rsvd:        0
   HugePages_Surp:        0
   Hugepagesize:       2048 kB

=cut

my $gigs=4;
my $shmSize = $gigs * 1024 * 2**20;

use IPC::SysV qw(IPC_PRIVATE S_IRUSR S_IWUSR S_IRWXU SHM_HUGETLB S_IXUSR);
use IPC::SharedMem;
#my $shm = IPC::SharedMem->new(IPC_PRIVATE , 2048 * 2**20, S_IRWXU | SHM_HUGETLB);

my $shm = IPC::SharedMem->new(IPC_PRIVATE , $shmSize, (S_IRUSR | S_IWUSR | S_IXUSR) | SHM_HUGETLB)
	or die "cannot allocate shared memory\n";

$shm->write(pack("S", 4711), 2, 2);
my $data = $shm->read(0, 2);
my $ds = $shm->stat;

#print Dumper($ds);

print "waiting for input\n";

my $input=<>;

$shm->remove;
