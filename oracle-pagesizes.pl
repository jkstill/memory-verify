#!/usr/bin/env perl

=head1 Author

 Jared Still - Pythian - 2020-02-13
 still@pythian.com
 jkstill@gmail.com

=cut 

use warnings;
use strict;
use IO::File;
use English;
use Data::Dumper;

my $debug=0;
my $newRecMarker='^([[:xdigit:]]{8,16})-([[:xdigit:]]{8,16})';

# add here to attributes to capture
my %attributes = (
	#PAGESIZE_NAME => 'KernelPageSize',
	# MMUPageSize is a better choice, as per 'man proc'
	PAGESIZE_NAME => 'MMUPageSize',
	SIZE_NAME => 'Size',
	FLAGS_NAME => 'VmFlags',
	HT_FLAG => 'ht',
	ANON_PAGES => 'AnonHugePages',
	SWAP => 'Swap',
	RSS => 'Rss',
);

# add here to sum Values
my @sumFields=qw( SIZE_NAME ANON_PAGES SWAP RSS );

my %memSizes = (

	kB => 2**10,
	mB => 2**20,
	gB => 2**30,

);

my $sharedFlag='sh';
my $key;

=head1 %pageSizeMaps

 store summary info about memory maps

 my %pageSizeSums=();

 {PID}->{heap|shared}{pagesize}
 {
     count = integer,
     totalsize = integer,
     AnonHugePages = integer,
     Swap = integer,
 }


=cut

my %pageSizeSums=();
my %procs=();

# using readdir works, but there is much duplication due to shared memory
# many processes will appear, which is not really necessary
# instead just look for Oracle PMON

#opendir(my $dh, '/proc') || die "could not open /proc\n";
#while (readdir $dh) {
	#next unless /^[[:digit:]]+$/;
	#my $pid = $_;

print "\n";

foreach my $psLine ( qx(ps -eo pid,comm  | grep [p]mon) ) {

	chomp $psLine;

	$psLine =~ s/^\s+//g;
	my ($pid,$cmd) = split(/\s+/,$psLine);

	$procs{$pid} = $cmd;

	print "$pid: $cmd\n" if $debug;
	print '#' x 20 ." Working on $pid " . '#' x 20 . "\n";

	my $mapFile="/proc/$pid/smaps";

	# even with read access indicated, this will fail as non root
	# due to Linux 'capabilities' - see setcap
	if ( ! -r $mapFile) {
		warn "file $mapFile either does not exist or you lack permissions - see 'man setcap'\n";
		next;
	}

	my $fh = IO::File->new;

	# constants such as O_RDONLY can be found in Fcntl
	# vi -R <(perldoc -l Fcntl)

	$fh->open($mapFile,'<',O_RDONLY) or die "Could not open $mapFile\n";

	my %smaps=();
	while (my $line = <$fh>) {
		chomp $line;

		# progress every 100 lines
		#print '.' unless $INPUT_LINE_NUMBER%100;

		if ( $line =~ /^$newRecMarker/ ) {
			$key = "$1-$2";
			$smaps{$key}->{PID}=$pid;
			$smaps{$key}->{CMD}=$cmd;
			print "key: $key\n" if $debug;
			print "####################### Record: ############################\n" if $debug;
			print "$line\n" if $debug; 
			next;
		}

		print "$line\n" if $debug;
		# while this works, the next one does not leave the colon
		#my ($col) = $line =~ /^([[:graph:]]+)/;
		my ($col,@data) = split(/:/,$line);
		print "col: $col\n" if $debug;
	
		$smaps{$key}->{$col} = join(' ',@data);
	}

	print "\n";

	print 'SMAPS Dump: ' . Dumper(\%smaps) if $debug;

	print "PID: $smaps{$key}->{PID}\n";
	print "CMD: $smaps{$key}->{CMD}\n";

	#my $htUsageFound=0;

	foreach my $key (keys %smaps) {

		print "SMAPS Key: $key\n" if $debug;

		
		# look for 'sh' shared flag in VMFlags
		my $memType='heap';
		if ( grep(/$sharedFlag/, split(/\s+/,$smaps{$key}->{$attributes{FLAGS_NAME}})) ) {
			$memType='shared';
		}
		print "MemType: $memType\n" if $debug;
		print "   flags: $smaps{$key}->{$attributes{FLAGS_NAME}}\n" if $debug;

		my ($currPageMeasure,$currenPageSize) = (split(/\s+/,$smaps{$key}->{$attributes{PAGESIZE_NAME}}))[1,2];
		my $currentPageSizeKey = "$currPageMeasure $currenPageSize";

		my %sumValues = ();

		# get current values from memory segment
		foreach my $field ( @sumFields ) {
			# format is \s+value\s+kB	
			# in the future might it be mB, or gB?
			my $segmentInfo = $smaps{$key}->{$attributes{$field}};
			my ($dummy, $segmentMeasure, $segmentSize) = split(/\s+/,$smaps{$key}->{$attributes{$field}});

			my $memSize = $segmentMeasure * $memSizes{$segmentSize};

			#$sumValues{$attributes{$field}} = (split(/\s+/,$smaps{$key}->{$attributes{$field}}))[1];
			$sumValues{$attributes{$field}} = $memSize;
		}

		print '%sumValues: ' . Dumper(\%sumValues) if $debug;

		# now add them up
		foreach my $field ( @sumFields ) {

			print "working on $field\n" if $debug;
			$pageSizeSums{$pid}->{$memType}{ $currentPageSizeKey }{$attributes{$field}} += $sumValues{$attributes{$field}};
			print "sumValue: $sumValues{$attributes{$field}}\n" if $debug;

			#$attributes{SIZE_NAME} => $pageSizeSums{ $smaps{$key}->{$attributes{SIZE_NAME}} } += $smaps{$key}->{$attributes{SIZE_NAME}}

		}

		print "   pagesize_name: $attributes{PAGESIZE_NAME}\n" if $debug;
		print "   value: $smaps{$key}->{$attributes{PAGESIZE_NAME}}\n" if $debug;
		print "   pagesize: $currentPageSizeKey\n" if $debug;

	}

	print 'pageSizeSums: ' . Dumper(\%pageSizeSums) if $debug;

	print "\n";
}

print "\n#################### Memory Info per PMON Process ####################\n\n";

foreach my $pid  ( keys %procs ) {

	print "PID: $pid   CMD: $procs{$pid}\n\n";

	my %pageInfo = %{$pageSizeSums{$pid}};

	#print Dumper(\%pageInfo);
	
	foreach my $memType ( keys %pageInfo ) {

		print "   MemType: $memType\n";

		foreach my $pageSize ( keys %{$pageInfo{$memType}} ) {

			print "      pagesize: $pageSize\n";

			foreach my $field ( @sumFields ) {
				print "        $attributes{$field}: " . commify($pageInfo{$memType}->{$pageSize}{$attributes{$field}}) . "\n";
			}

		}
		print "\n";
	}

	print "\n";

}

	
sub commify {
	local $_  = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}


