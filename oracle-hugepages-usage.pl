#!/usr/bin/env perl

use warnings;
use strict;
use IO::File;
use English;
use Data::Dumper;

my $debug=0;
my $newRecMarker='^([[:xdigit:]]{8,16})-([[:xdigit:]]{8,16})';
my $htPageSize='2048\s+kB'; 

my %attributes = (
	PAGESIZE_NAME => 'KernelPageSize',
	SIZE_NAME => 'Size',
	FLAGS_NAME => 'VmFlags',
	HT_FLAG => 'ht',
	ANON_PAGES => 'AnonHugePages',
);
my $htFlag='ht';

my $key;

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

	print "$pid: $cmd\n" if $debug;
	print '#' x 20 ." Working on $pid " . '#' x 20 . "\n";

	my $mapFile="/proc/$pid/smaps";

	if ( ! -r $mapFile) {
		warn "file $mapFile is either does not exist or you lack permissions\n";
		next;
	}

	my $fh = IO::File->new;

	# constants such as O_RDONLY can be found in Fcntl
	# vi -R $(perldoc -l Fcntl)

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

	print Dumper(\%smaps) if $debug;

	print "PID: $smaps{$key}->{PID}\n";
	print "CMD: $smaps{$key}->{CMD}\n";

	my $htUsageFound=0;

	foreach my $key (keys %smaps) {

		my $currPageSize = $smaps{$key}->{$attributes{PAGESIZE_NAME}};
		if ( $currPageSize =~ /$htPageSize/ ) {
			print '=' x 50 . "\n";
			print "PageSize: $currPageSize\n";

			# validate ht flag
			if ( ! grep(/$htFlag/, split(/\s+/,$smaps{$key}->{$attributes{FLAGS_NAME}})) ) {
				warn "HugeTables Flag not found!\n";
			} else {
				$htUsageFound=1;
			}


			print "Size: $smaps{$key}->{$attributes{SIZE_NAME}}\n";
			print "AnonPages (should be 0):  $smaps{$key}->{$attributes{ANON_PAGES}}\n";
		}
	}

	print "No HugeTables usage found\n" unless $htUsageFound;
	print "\n";
}

	

	#print '#' x 20 . " PID: $pid " . '#' x 20 . "\n";


