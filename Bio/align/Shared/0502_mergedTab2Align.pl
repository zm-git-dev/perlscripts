#!/usr/bin/perl -w
use strict;
use FindBin qw($Bin);
use lib "$Bin";
use loadconf;
use fasta;

use Data::Dumper;

&usage("NOT ENOUGHT ARGUMENTS"                          ) if ( @ARGV < 2            );
my $inTabFile = $ARGV[0];
my $inFasFile = $ARGV[1];
my $outFolder = $ARGV[2];
&usage("NO INPUT TAB FILE"                              ) if ( ! defined $inTabFile );
&usage("NO INPUT FASTA FILE"                            ) if ( ! defined $inFasFile );
&usage("INPUT TAB FILE DOESNT EXISTS:   \"$inTabFile\"" ) if ( ! -f      $inTabFile );
&usage("INPUT FASTA FILE DOESNT EXISTS: \"$inFasFile\"" ) if ( ! -f      $inFasFile );

my $ofB          = "$inTabFile.blast.aln";
my $ofF          = "$inTabFile.fasta.aln";
my $ofFasta      = "$inTabFile.fasta";
my $screenWidth  = 100;
my %DARGS;
my $argMaxLeng = 0;

my %ARGS;
my %checkCols;
&loadArgs();

my $outFileB       = $ARGS{outFileBlast     }{value};
my $outFileF       = $ARGS{outFileFasta     }{value};
my $outFileFasta   = $ARGS{outFileFastaFasta}{value};
my $maxHeaderWidth = $ARGS{maxHeaderWidth   }{value};
my $seqWidth       = $ARGS{seqWidth         }{value};
my $padSequence    = $ARGS{padSequence      }{value};
my $multAlign      = $ARGS{multAlign        }{value};
my $confFile       = $ARGS{confFile         }{value};
   $padSequence    = 1 if $multAlign;


print "
INPUT TAB FILE     : $inTabFile
INPUT FASTA FILE   : $inFasFile
OUTPUT FOLDER      : $outFolder

OUTPUT TAB ALN     : $ofB
INPUT TAB FASTA ALN: $ofF
OUTPUT FASTA       : $ofFasta
";

my $gTab   = &readTab($inTabFile);
my $gFasta = fasta->new($inFasFile);
#$gFasta->printChromStat();

if (( defined $confFile ) && ( $confFile ne "" ))
{
	if ( ! -f $confFile ) { &usage("COULD NOT FIND XML CONFIG FILE $confFile") };
	my $dbNames = &getDbNames($confFile);
	&export($gTab, $gFasta, $dbNames);
} else {
	&export($gTab, $gFasta);
}


sub getDbNames
{
	my $cnfFile = $_[0];
	print "ACQUIRING DB NAMES FROM $cnfFile\n";

	my %hash;
	my %pref = &loadconf::loadConf($cnfFile);
	&loadconf::checkNeeds('mergetab2align.folders.fastaFolder', 'mergetab2align.folders.inFastaFolder');
	#, 'mergetab2align.inFiles'

	my $fastaFolder   = $outFolder . "/" . $pref{'mergetab2align.folders.fastaFolder'  } || 'fasta';
	my $inFastaFolder = $outFolder . "/" . $pref{'mergetab2align.folders.inFastaFolder'} || 'query_fasta';
	#my $inFilesStr    = $pref{'mergetab2align.inFiles'}               || die "NO INPUT FILES DEFINED";

	die  "FOLDER ", $fastaFolder   ," DOESNT EXISTS" if ( ! -d $fastaFolder  );
	die  "FOLDER ", $inFastaFolder ," DOESNT EXISTS" if ( ! -d $inFastaFolder );

	my @db;
	my @alias;
	foreach my $key (sort keys %pref)
	{
		if ($key =~ /^mergetab2align\.(\S+)\.\1(\d+)\.(\S+)/)
		{
			my $prefix = $1;
			my $count  = $2;
			my $type   = $3;

			if ($prefix eq 'db')
			{
				#print "DB :: PREFIX $prefix COUNT $count TYPE $type => $pref{$key}\n";
				$db[$2]{$3} = $pref{$key};
			}
			elsif ($prefix eq 'alias')
			{
				#print "ALIAS :: PREFIX $prefix COUNT $count TYPE $type => $pref{$key}\n";
				$alias[$2]{$3} = $pref{$key};
			}
		}
	}

	die "NO INPUT DATABASE INSERTED" if ( ! @db );

	my $maxDbName = 0;
	for ( my $d = 0; $d < @db; $d++ )
	{
		my $nfo       = $db[$d];
		my $inFasta   = $nfo->{fileName} || die "FILE NAME NOT INFORMED FOR DB";
		my $inDbName  = $nfo->{dbName}   || die "DB NAME   NOT INFORMED FOR DB";
		my $inDbTitle = $nfo->{title}    || die "DB TITLE  NOT INFORMED FOR DB";
		my $inDbTaxId = $nfo->{taxId}    || die "TAX ID    NOT INFORMED FOR DB";

		die "INPUT DB FILE $fastaFolder/$inFasta DOESTN EXISTS" if ( ! -f "$fastaFolder/$inFasta" );
		$hash{db}{$inDbTitle}{file}  = "$fastaFolder/$inFasta";
		my $name = $inFasta;
		if ( index ( $name, "/" ) ne -1 ) { $name = substr( $name, rindex ( $name, "/" ) + 1); };
		$hash{db}{$inDbTitle}{name}  = $name;
		$hash{db}{$inDbTitle}{fasta} = fasta->new("$fastaFolder/$inFasta");
		$maxDbName = length($inDbTitle) > $maxDbName ? length($inDbTitle) : $maxDbName;
		printf "\tQRY DB NAME %-50s FASTA \"%s\"\n", "\"$inDbTitle\"", "$fastaFolder/$inFasta";
	}

	#map { printf "\tQRY DB NAME \"%-".($maxDbName+2)."s\" FASTA \"%s\"\n", "\"$_\"", $hash{db}{$_}{file}; } sort keys %{$hash{db}};

	my @inFiles;
	#for my $file (split(",",$inFilesStr))
	#{
		die "INPUT FASTA FILE $inFasFile DOESNT EXISTS" if ( ! -f "$inFasFile" );
		#fanthastic_blast.tab.out.tab_blast_merged_blast_all_gene.xml.tab
		if ( $inTabFile =~ /$inFasFile/ )
		{
			if ( ! -f "$inFasFile" )
			{
				die "ESPECULATED SOURCE FASTA FILE '$inFasFile' NOT FOUND\n";
			}

			$hash{ref}{file}  = "$inFasFile";
			$hash{ref}{name}  = "$inFasFile";
			$hash{ref}{fasta} = fasta->new("$inFasFile");
			printf "\tREF DB NAME %-50s FASTA \"%s\"\n", "reference","$inFasFile";
		}
	#}

	print "DB NAMES ACQUIRED FROM $cnfFile :: ", scalar keys %{$hash{db}}, " DBS RETRIEVED\n\n\n";
	return \%hash;
}

sub export
{
	#TODO:	NOT WORKING PROPERLY YET.
	#		NEEDS TO MERGE HSPS
	my ($tab, $fasta, $db) = @_;
	my %fastas;

	my ( $maxLengK1, $maxLengK2, $maxLengChrom, $maxLengK ) = &getMaxLengs($tab);
	my $format1       = "%-".$maxLengK."s %03d %-".$maxLengChrom."s";
	my $format1H      = "%-".$maxLengK."s %-3s %-".$maxLengChrom."s";
	my $format2       = "%7d %7d %7d %7d %7d";
	my $format2H      = "%-7s %-7s %-7s %-7s %-7s";
	my @sequenceTitle = split(//, "SEQUENCE");

	print "EXPORTING ", scalar keys %{$tab->{dir}}, " KEYS\n";

	open OFB, ">$outFileB" or die "COULD NOT OPEN OUTPUT FILE $outFileB\n";
	open OFF, ">$outFileF" or die "COULD NOT OPEN OUTPUT FILE $outFileF\n";

	foreach my $format ('dir')
	{
		#print "  "x1 , "RUNNING FORMAT '$format'\n";
		my $tabData = $tab->{$format};

		foreach my $key1 (sort keys %$tabData)
		{
			# KEY 1 = QUERY SEQUENCE NAME
			my $k1t = &getTruncated($key1, $screenWidth);
			my $sub = $tabData->{$key1};

			my $k1tF = $k1t;
			   $k1tF =~ s/\///g;
			   $k1tF =~ s/\|//g;

			my  $oFa  = "$outFileFasta.$k1tF.fasta";
			open OFa,  ">$oFa"     or die "COULD NOT OPEN OUTPUT FILE $oFa: $!\n"     if defined $db;
			open OFaL, ">$oFa.log" or die "COULD NOT OPEN OUTPUT FILE $oFa.log: $!\n" if defined $db;


			my $min = $sub->{margin}{0}{min};
			my $max = $sub->{margin}{0}{max};
			my $len = $sub->{margin}{0}{leng};
			print OFaL "  "x2 , "$format :: EXPORTING KEY '$k1t'\n";

			my @B_headers;
			my @B_numbers;
			my @B_seqs;
			my @F_headers;
			my @F_numbers;
			my @F_seqs;
			my $frag = $fasta->getFragment($key1, 1, $len);

			print OFaL "  "x3 , "$format :: $key1\n";
			print OFaL "  "x4 , "FASTA FILE $oFa\n";


			$B_headers[0] = sprintf($format1H, "ORGANISM", "HIT", "CHROMOSSOME");
			$B_numbers[0] = sprintf($format2H, "LENGTH", "MIN", "MAX", "START", "END");
			$B_seqs[0]    = \@sequenceTitle;

			$B_headers[1] = sprintf($format1, &getTruncated($key1, $maxHeaderWidth), 0, "REF");
			$B_numbers[1] = sprintf($format2, $len, $min, $max, 1, $len);
			$B_seqs[1]    = $frag;


			my $B_baseWidth = length($B_headers[1]) + length($B_numbers[1]);

			printf OFaL "    $format :: $k1t :: LENGTH %7d MIN %7d MAX %7d START %7d END %7d", $len, $min, $max, 1, $len;
			print OFaL "  "x2 , "$format :: $k1t :: REQUESTING SEQ '", &getTruncated($key1, $screenWidth) , "' [1-$len]\n";
			print OFaL "  "x3 , "$format :: $k1t :: LENGTH ", (scalar @$frag), "\n";

			foreach my $key2 (sort keys %$sub)
			{
				next if ($key2 eq 'margin');
				my $k2t = &getTruncated($key2, $screenWidth);
				print OFaL "  "x3 , "$format :: $k1t :: EXPORTING QUERY '$k2t'\n";

				my $hits    = $sub->{$key2};

				print OFaL "  "x4 , "$format :: $k1t :: $k2t :: HITS : ", ( scalar keys %$hits ) ,"\n";

				foreach my $hit ( sort { $a <=> $b } keys %$hits )
				{
					my $nfo  = $hits->{$hit};
					my $data = $nfo->{data};

					my $Qstart  = $data->{$ARGS{QstartCol }{value}};
					my $Qend    = $data->{$ARGS{QendCol   }{value}};
					my $Qlen    = $data->{$ARGS{QlengthCol}{value}};
					my $Hstart  = $data->{$ARGS{HstartCol }{value}};
					my $Hend    = $data->{$ARGS{HendCol   }{value}};
					my $Hlen    = $data->{$ARGS{HlengthCol}{value}};
					my $HStrand = $data->{$ARGS{HStrandCol}{value}};
					my $HitId   = $data->{$ARGS{HitId     }{value}};
					my $HName   = $data->{$ARGS{HNameCol  }{value}};

					push(@B_headers, sprintf($format1, &getTruncated($key2, $maxHeaderWidth), $hit, $HName));
					push(@B_numbers, sprintf($format2, $Hlen, $Hstart, $Hend, $Qstart, $Qend));
					printf OFaL "    $format :: $k1t :: HIT LENGTH %7d HIT START %7d HIT END %7d QUERY START %7d QUERY END %7d", $Hlen, $Hstart, $Hend, $Qstart, $Qend;

					my $aln    = $nfo->{aln};
					my $aln1   = $aln->{aln1};
					my $aln2   = $aln->{aln2};
					my $aln3   = $aln->{aln3};
					my $hSeq   = $aln3;

					if ( $padSequence )
					{
						print OFaL "    $format :: $k1t :: QRY LEN $len HIT LENG ", length($hSeq), " START $Qstart DIFF ", ($len - length($hSeq)), "\n";
						$hSeq   = "-"x($Qstart-1) . $hSeq . "-"x($len - length($hSeq) );
					}

					my @hSeq = split("", $hSeq);
					push(@B_seqs,    \@hSeq);

					if ( ! defined $db )
					{
						print OFaL "  "x4 , "REV :: $k1t :: $k2t :: NOTHING TO DO IN REVERSE\n";
					} else {
						print OFaL "  "x4 , "REV :: $k1t :: $k2t :: STARTING REVERSE\n";

						die "NO DATABASE FOUND FOR \"$key2\"" if ( ! exists ${$db->{db}}{$key2} );
						my $dbk2       = $db->{db}{$key2};
						my $fastaName  = $dbk2->{name};
						my $fastaFile  = $dbk2->{file};
						my $fastaFasta = $dbk2->{fasta};
						print OFaL "  "x5 , "REV :: $k1t :: $k2t :: FASTA NAME $fastaName\n";
						die "TAB REVERSE DOESNT EXISTS"                if ( ! exists ${$tab}{rev}                         );
						die "TAB REVERSE KEY2 \"$key2\" DOESNT EXISTS" if ( ! exists ${$tab->{rev}}{$key2}                );
						die "TAB REVERSE KEY1 \"$key1\" DOESNT EXISTS" if ( ! exists ${$tab->{rev}{$key2}}{$key1}         );
						#die "TAB REVERSE HIT \"$hit\" DOESNT EXISTS"   if ( ! exists ${$tab->{rev}{$key2}{$key1}}{$hit}   );
						die "TAB REVERSE MARGIN DOESNT EXISTS"         if ( ! exists ${$tab->{rev}{$key2}{$key1}}{margin} );

						my $lm    = $tab->{rev}{$key2}{$key1}{margin};

						foreach my $rHit ( sort {$a <=> $b} keys %$lm )
						{
							my $lRev    = $lm->{$hit};
							my $Fmin    = $lRev->{min};
							my $Fmax    = $lRev->{max};
							my $Flen    = $lRev->{leng};
							#my $hitName = $lRev->{name};
							my $hitName = $lRev->{chrom};
							die "TAB REVERSE MIN DOESNT EXISTS"   if ( ! defined $Fmin    );
							die "TAB REVERSE MAX DOESNT EXISTS"   if ( ! defined $Fmax    );
							die "TAB REVERSE LENG DOESNT EXISTS"  if ( ! defined $Flen    );
							die "TAB REVERSE CHROM DOESNT EXISTS" if ( ! defined $hitName );
							my $Flen2   = $max   - $min;
							my $Fgap    = $Flen2 - $Flen;

							print OFaL "  "x6 , "REV :: $k1t :: $k2t :: $fastaName :: MIN $Fmin MAX $Fmax LENG $Flen REAL LENG $Flen2 GAP $Fgap :: REQUESTING SEQ '", &getTruncated($hitName, $screenWidth) , "'\n";
							my $Ffrag   = $fastaFasta->getFragment($hitName, $Fmin, $Fmax);
							if ( ! defined $Ffrag ) { die "ERROR READING FASTA :: PARAMETERS OUT OF RANGE : $k1t :: $k2t :: $fastaName :: MIN $Fmin MAX $Fmax LENG $Flen REAL LENG $Flen2 GAP $Fgap\n"; };

							print OFaL "  "x7 , "REV :: $k1t :: $k2t :: $fastaName :: MIN $Fmin MAX $Fmax LENG $Flen REAL LENG $Flen2 GAP $Fgap :: LENGTH ", (scalar @$Ffrag), "\n";

							if ( $HStrand eq "-1" )
							{
								#print "FRAG BEFORE: ",&getTruncated(join('', @$Ffrag), $screenWidth),"\n";
								&revCompArray($Ffrag);
								#print "FRAG AFTER:  ",&getTruncated(join('', @$Ffrag), $screenWidth),"\n";
							}

							if ( ! scalar @F_headers )
							{
								$F_headers[0] = sprintf($format1H, "ORGANISM", "HIT", "CHROMOSSOME");
								$F_numbers[0] = sprintf($format2H, "LENGTH", "MIN", "MAX", "START", "END");
								$F_seqs[0]    = \@sequenceTitle;

								$F_headers[1] = sprintf($format1, &getTruncated($key1, $maxHeaderWidth), 0, "REF");
								$F_numbers[1] = sprintf($format2, $len, $min, $max, 1, $len);
								$F_seqs[1]    = $frag;
							}

							push(@F_headers, sprintf($format1, &getTruncated($key2, $maxHeaderWidth), $hit, $hitName));
							push(@F_numbers, sprintf($format2, $Flen, $Fmin, $Fmax, $Fmin, $Fmax));
							push(@F_seqs,    $Ffrag);
						}
					} # end if else ! defined $db
				} # end foreach my $hit
			} # end foreach my $key2











			if ( $multAlign )
			{
				print OFaL "  "x3 , "$format :: $k1t :: EXPORTING BLAST MULTIPLE ALIGNMENT\n";
				# still not working properly
				for (my $s = 0; $s < $len; $s += $seqWidth)
				{
					my $begin  = $s + 1;
					my $lPiecesSize = $seqWidth;
					for (my $h = 0; $h < @B_headers; $h++)
					{
						while ( ( $s + $lPiecesSize ) > $len ) { $lPiecesSize-- };
						next if $lPiecesSize == 0;
						my $finish = ($s + $lPiecesSize);
						my $phrase = $B_headers[$h] . " " . $B_numbers[$h] . " ";
						my $frag   = @{$B_seqs[$h]}[$s..($s+$lPiecesSize)];
						printf OFB "%-s | %7d %-s %7d\n", $phrase, $begin, $frag, $finish;
					}
					print OFB "\n";
				}
				print OFB "\n", "="x( $B_baseWidth + $seqWidth + 10) , "\n\n";
			} else {
				print OFaL "  "x3 , "$format :: $k1t :: EXPORTING BLAST SEQUENCES\n";
				for (my $h = 0; $h < @B_headers; $h++)
				{
					printf OFB "%-s %-s | %-s\n", $B_headers[$h], $B_numbers[$h], join("", @{$B_seqs[$h]});
				}
				print OFB "\n", "="x( $B_baseWidth + $seqWidth + 10) , "\n\n";
			} # end if else ! multalign

			if ( ! defined $db )
			{
				print OFaL "  "x3 , "$format :: $k1t :: NOTHING TO EXPORT IN REVERSE\n";
			} else {
				print OFaL "  "x3 , "$format :: $k1t :: EXPORTING FASTA FRAGMENTS SEQUENCE\n";
				for (my $h = 1; $h < @F_headers; $h++)
				{
					printf OFF "%-s %-s | %-s\n", $F_headers[$h], $F_numbers[$h], join("", @{$F_seqs[$h]});
					my $head = ">" . $F_headers[$h] . $F_numbers[$h];
					my $seq  = join("", @{$F_seqs[$h]});
					$head =~ s/\s+/\_/g;
					$head =~ s/\|/\_/g;
					$head =~ s/_+/\_/g;
					$seq  =~ s/(.{60})/$1\n/g;
					print OFa $head, "\n", $seq, "\n";
					printf OFaL   "%-s %-s | %-s\n", $F_headers[$h], $F_numbers[$h], join("", @{$F_seqs[$h]});
					print  OFaL $head, "\n", $seq, "\n";

				}
				print OFF "\n", "="x( $B_baseWidth + $seqWidth + 10) , "\n\n";
			}

			close OFa  if defined $db;
			close OFaL if defined $db;

		} # end foreach my $key
	} # end foreach my format
	close OFB;
	close OFF;
	print "EXPORTING COMPLETED\n";
}





sub readTab
{
	my $file          = shift;
	my $stLine        = $ARGS{'1stline'}{value} || 1;
	my $dump          = 0;
	my $hitNameColumn = $ARGS{HNameCol}{value} || die;

	print "READING TAB FILE $file\n";
	open FILE, "<$file" or die "COULD NOT OPEN INPUT FILE $file: $!";

	my $lineCount = 0;
	my @colNumbers;
	my %colNames;

	my $groupByCol1Filter      = $ARGS{groupByCol1Filter}{value};
	my %outHash;
	my %seenK1;
	my %seenK2;

	while (my $line = <FILE>)
	{
		chomp $line;
		$lineCount++;
		if    ( $lineCount <  $stLine )
		{
			print "\tSKIPPING :: $line\n"; next;
		}
		elsif ( $lineCount == $stLine )
		{
			print "\tACQUIRING HEADERS :: $line\n";
			$line =~ s/\#//;
			$line =~ s/\"//g;
			@colNumbers = split(/\t/, $line);

			for (my $c = 0; $c < @colNumbers; $c++)
			{
				my $colName = $colNumbers[$c];
				$colNames{$colName} = $c;
				printf "\t\tCOL %02d NAME %-".$argMaxLeng."s", $c, $colName;
				if ( exists $checkCols{$colName} ) { print " *[",$checkCols{$colName}{desc},"]"}
				print "\n";
			}

			my $cnf = "COULD NOT FIND COLUMN ";
			my $ihl = "] IN HEADER LINE :: $line";

			foreach my $cCol ( sort keys %checkCols )
			{
				if ( ! exists $colNames{$cCol} )
				{
					&usage($cnf . $cCol . " [" . $checkCols{$cCol}{name} . $ihl)
				} else {
					$checkCols{$cCol}{number} = $colNames{$cCol};
				}
			}

			print "\tACQUIRING DATA\n";
		}
		elsif ( scalar @colNumbers )
		{
			$line =~ s/\"//g;
			if (( defined $groupByCol1Filter ) && ( $groupByCol1Filter ne '' ) && ( $line !~ /$groupByCol1Filter/ )) { print "NEXTING\n" if 0; next;};

			my @cols   = split(/\t/, $line);
			my $grpBy1 = $cols[$checkCols{$ARGS{groupByCol1}{value}}{number}];
			my $grpBy2 = $cols[$checkCols{$ARGS{groupByCol2}{value}}{number}];
			my $aln    = $cols[$checkCols{$ARGS{alignCol   }{value}}{number}];
			my $Qstart = $cols[$checkCols{$ARGS{QstartCol  }{value}}{number}];
			my $Qend   = $cols[$checkCols{$ARGS{QendCol    }{value}}{number}];
			my $Qlen   = $cols[$checkCols{$ARGS{QlengthCol }{value}}{number}];
			my $Hstart = $cols[$checkCols{$ARGS{HstartCol  }{value}}{number}];
			my $Hend   = $cols[$checkCols{$ARGS{HendCol    }{value}}{number}];
			my $Hlen   = $cols[$checkCols{$ARGS{HlengthCol }{value}}{number}];
			my $HitId  = $cols[$checkCols{$ARGS{HitId      }{value}}{number}];
			my $HName  = $cols[$checkCols{$ARGS{HNameCol   }{value}}{number}];

			foreach my $cCol ( sort keys %checkCols )
			{
				#print "\t\tCHECKING VALUE '$cCol'\n";
				die "NO COLUMN NAME DEFINED" if ! defined $cCol;
				my $num = $checkCols{$cCol}{number};
				die "NO COLUMN NUMBER DEFINED TO '$cCol'" if ! defined $num;

				my $colVal = $cols[$num];
				if (( ! defined $colVal ) || ( $colVal eq '' ))
				{
					&usage("COLUMN '$cCol' HAS NO VALUE: '$colVal'\n")
				}
			}

			if ( ! exists $seenK1{$grpBy1} ) { print "\t\tACQUIRING ", &getTruncated($grpBy1, $screenWidth) , "\n"};
			if ( ! exists $seenK2{$grpBy2} ) { print "\t\t\tACQUIRING $grpBy2\n"};
			$seenK1{$grpBy1}++;
			$seenK2{$grpBy2}++;
			$outHash{dir}{$grpBy1}{$grpBy2}{$HitId} = {} if (( ! exists $outHash{dir} ) || ( ! exists ${$outHash{dir}}{$grpBy1} ) || ( ! exists ${$outHash{dir}{$grpBy1}}{$grpBy2} ) || ( ! exists ${$outHash{dir}{$grpBy1}{$grpBy2}}{$HitId} ));
			$outHash{rev}{$grpBy2}{$grpBy1}{$HitId} = {} if (( ! exists $outHash{rev} ) || ( ! exists ${$outHash{rev}}{$grpBy2} ) || ( ! exists ${$outHash{rev}{$grpBy2}}{$grpBy1} ) );

			my $localDirGrpBy1 = $outHash{dir}{$grpBy1};
			my $localDirGrpBy2 = $outHash{dir}{$grpBy1}{$grpBy2};
			my $localDirGrpBy3 = $outHash{dir}{$grpBy1}{$grpBy2}{$HitId};

			my $localRevGrpBy2 = $outHash{rev}{$grpBy2};
			my $localRevGrpBy1 = $outHash{rev}{$grpBy2}{$grpBy1};
			#my $localRevGrpBy0 = $outHash{rev}{$grpBy2}{$grpBy1}{$HitId};


			# k1 = query sequence name
			# k2 = database hit name
			my %alns;
			if ( $aln =~ /\<st\>(.+?)\<\/st\>\<nd\>(.+?)\<\/nd\>\<rd\>(.+?)\<\/rd\>/)
			{
				$alns{aln1} = $1;
				$alns{aln2} = $2;
				$alns{aln3} = $3;
			} else {
				warn 'weeeird... no alignment dude: ' . $aln . "\n";
			}

			if ( ! $dump )
			{
				$localDirGrpBy3->{aln} = \%alns;
			}

			my $Qmin = $Qend > $Qstart ? $Qstart : $Qend;
			my $Qmax = $Qend < $Qstart ? $Qstart : $Qend;

			my $Hmin = $Hend > $Hstart ? $Hstart : $Hend;
			my $Hmax = $Hend < $Hstart ? $Hstart : $Hend;

			if ( ! exists ${$localDirGrpBy1}{margin}  )
			{
				$localDirGrpBy1->{margin}{0} = {};
				my $lm = $localDirGrpBy1->{margin}{0};
				$lm->{min}   = $Qmin ;
				$lm->{max}   = $Qmax ;
				$lm->{leng}  = $Qlen ;
				$lm->{name}  = $grpBy1;
				$lm->{chrom} = $grpBy1;
			} else {
				if ( ! exists ${$localDirGrpBy1->{margin}}{0} )
				{
					$localDirGrpBy1->{margin}{0} = {};
					my $lm = $localDirGrpBy1->{margin}{0};
					$lm->{min}   = $Qmin ;
					$lm->{max}   = $Qmax ;
					$lm->{leng}  = $Qlen ;
					$lm->{name}  = $grpBy1;
					$lm->{chrom} = $grpBy1;
				} else {
					my $lm = $localDirGrpBy1->{margin}{0};
					$lm->{min}   = $lm->{min} < $Qmin ? $lm->{min} : $Qmin;
					$lm->{max}   = $lm->{max} > $Qmax ? $lm->{max} : $Qmax;
					$lm->{name}  = $grpBy1;
					$lm->{chrom} = $grpBy1;
					if ( $lm->{leng} != $Qlen )
					{
						die "WEEEIRD. QUERY LENGTH CHANGES. '$Qlen' vs '" . $lm->{leng} . "'\n";
					}
				}
			}

			if ( ! exists ${$localRevGrpBy1}{margin}  )
			{
				$localRevGrpBy1->{margin}{$HitId} = {};
				my $lm = $localRevGrpBy1->{margin}{$HitId};
				$lm->{min}   = $Hmin ;
				$lm->{max}   = $Hmax ;
				$lm->{leng}  = $Hlen ;
				$lm->{name}  = $grpBy2;
				$lm->{chrom} = $HName;
			} else {
				if ( ! exists ${$localRevGrpBy1->{margin}}{$HitId}  )
				{
					$localRevGrpBy1->{margin}{$HitId} = {};
					my $lm = $localRevGrpBy1->{margin}{$HitId};
					$lm->{min}   = $Hmin ;
					$lm->{max}   = $Hmax ;
					$lm->{leng}  = $Hlen ;
					$lm->{name}  = $grpBy2;
					$lm->{chrom} = $HName;
				} else {
					my $lm = $localRevGrpBy1->{margin}{$HitId};
					$lm->{min}   = $lm->{min} < $Hmin ? $lm->{min} : $Hmin;
					$lm->{max}   = $lm->{max} > $Hmax ? $lm->{max} : $Hmax;
					$lm->{name}  = $grpBy2;
					$lm->{chrom} = $HName;
					$lm->{leng} += $Hlen;
				}
			}


			#if ( ! exists ${$localDirGrpBy1}{min}  ) { $localDirGrpBy1->{min}  = $Qmin ; } else { $localDirGrpBy1->{min}   = $localDirGrpBy1->{min} < $Qmin ? $localDirGrpBy1->{min} : $Qmin; };
			#if ( ! exists ${$localDirGrpBy1}{max}  ) { $localDirGrpBy1->{max}  = $Qmax ; } else { $localDirGrpBy1->{max}   = $localDirGrpBy1->{max} > $Qmax ? $localDirGrpBy1->{max} : $Qmax; };
			#if ( ! exists ${$localDirGrpBy1}{leng} ) { $localDirGrpBy1->{leng} = $Qlen ; } else { if ( $localDirGrpBy1->{leng} != $Qlen ) { warn "WEEEIRD. QUERY LENGTH CHANGES. '$Qlen' vs '".$localDirGrpBy1->{leng}."'\n"}};
			#
			#if ( ! exists ${$localRevGrpBy1}{min}  ) { $localRevGrpBy1->{min}  = $Hmin ; } else { $localRevGrpBy1->{min}   = $localRevGrpBy1->{min} < $Hmin ? $localRevGrpBy1->{min} : $Hmin; };
			#if ( ! exists ${$localRevGrpBy1}{max}  ) { $localRevGrpBy1->{max}  = $Hmax ; } else { $localRevGrpBy1->{max}   = $localRevGrpBy1->{max} > $Hmax ? $localRevGrpBy1->{max} : $Hmax; };
			#if ( ! exists ${$localRevGrpBy1}{leng} ) { $localRevGrpBy1->{leng} = $Hlen ; } else { $localRevGrpBy1->{leng} += $Hlen };


			my %lData;
			for ( my $c = 0; $c < @cols; $c++ )
			{
				my $colName = $colNumbers[$c];
				next if ( ! exists $checkCols{$colName} || ! exists ${$checkCols{$colName}}{data} );
				my $colVal  = $cols[$c];
				#print "ADDING $grpBy1 : $grpBy2 data $colName\n";
				$lData{$colName} = $colVal;

				#if ( $colName eq $hitNameColumn )
				#{
				#	if ( ! exists ${$localRevGrpBy1}{HNameCol} )
				#	{
				#		$localRevGrpBy1->{HNameCol} = $colVal;
				#	} else {
				#		if ( $localRevGrpBy1->{HNameCol} ne $colVal )
				#		{
				#			die "WEIRRRD. CHROMOSSOME CHANGED IN HIT: \"", $localRevGrpBy1->{HNameCol} ,"\" VS \"", $colVal, "\"\n";
				#		}
				#	}
				#}
			}

			if ( ! $dump )
			{
				$localDirGrpBy3->{data} = \%lData;
				#$localRevGrpBy1->{data} = \%lData;
			}
		} else {
			&usage("ERROR READING TAB FILE");
		}
	}

	if ( $dump )
	{
		$Data::Dumper::Indent    = 1;
		$Data::Dumper::Purity    = 1;
		$Data::Dumper::Quotekeys = 1;
		print Dumper \%outHash;
		exit;
	}



	close FILE;
	print "TAB FILE $file READ :: ",scalar keys %seenK1," REFERENCES EXPORTED AGAINST ",scalar keys %seenK2," DBS [",((scalar keys %seenK1) * (scalar keys %seenK2))," PERMUTATIONS]\n\n\n";

	return \%outHash;
}



sub getTruncated
{
	my $str = $_[0];
	my $len = $_[1];

	return $str if ( length $str < $len );
	return $str if ( $len == 0          );
	my $sides  = int(($len - 5) / 2);
	return substr($str, 0, $sides) . "..." . substr($str, length($str)-$sides);
}


sub getMaxLengs
{
	my $hash      = $_[0];
	my $k1Leng    = 0;
	my $k2Leng    = 0;
	my $chromLeng = 0;
	foreach my $key1 (sort keys %{$hash->{dir}})
	{
		#print "  "x1, "K1 ", $key1, "\n";
		$k1Leng = length($key1) if ( length($key1) > $k1Leng );
		my $sub  = $hash->{dir}{$key1};
		foreach my $key2 (sort keys %$sub)
		{
			next if ($key2 eq 'margin');
			#print "  "x2, "K2 ", $key2, "\n";
			$k2Leng  = length($key2) if ( length($key2) > $k2Leng);
			my $hits = $sub->{$key2};

			foreach my $hit ( sort { $a <=> $b } keys %$hits )
			{
				my $nfo  = $hits->{$hit};
				my $data = $nfo->{data};
				my $HName   = $data->{$ARGS{HNameCol  }{value}};
				#print "  "x3, "H  ", $hit, " => ", $HName, "\n";
				$chromLeng  = length($HName) if ( length($HName) > $chromLeng);
			}
		}
	}

	my $maxLeng = $k1Leng > $k2Leng ? $k1Leng : $k2Leng;
	my $mLeng   = $maxLeng;
	if ( $maxHeaderWidth && ( $mLeng > $maxHeaderWidth )) { $mLeng = $maxHeaderWidth };
	return ( $k1Leng, $k2Leng, $chromLeng, $mLeng);
}


sub usage
{
	my $error = shift;

	print "#"x20, "\n", $error, "\n", "#"x20, "\n";
	print "COMMAND: ", $0, " @ARGV\n";
	print "USAGE  : ", $0, " <INPUT TAB FILE> <INPUT FASTA FILE> <OUTPUT BASE FOLDER>\n";
	map { print "\t", $_, ":<", $DARGS{$_}{desc}, "[ DEFAULT: ",$DARGS{$_}{value},"]>\n"; } sort keys %DARGS;
	exit 1;
}



sub loadArgs
{
	%DARGS = (
				#contant name		=>	[FIELD DESCRIPTION									, VALUE,	, COMPULSORY FIELD IN TABLE[BOL], DATA FIELD IN TABLE[BOL] ]
				'maxHeaderWidth'    => {'desc' => 'MAX HEADER WIDTH [IN CHARS - INT] (0 FOR NO MAX)', 'value' => 0            , 'comp' => 0 , 'data' => 0 },
				'seqWidth'          => {'desc' => 'SEQUENCE WIDTH [IN CHARS - INT] (0 FOR NO MAX)'  , 'value' => 100          , 'comp' => 0 , 'data' => 0 },
				'padSequence'       => {'desc' => 'PAD SEQUENCES WITH - [BOL]'                      , 'value' => 0            , 'comp' => 0 , 'data' => 0 },
				'multAlign'         => {'desc' => 'DO MULTI ALIGNMENT [BOL]'                        , 'value' => 0            , 'comp' => 0 , 'data' => 0 },
				'outFileBlast'      => {'desc' => 'OUTPUT FILE NAME [STR]'                          , 'value' => $ofB         , 'comp' => 0 , 'data' => 0 },
				'outFileFasta'      => {'desc' => 'OUTPUT FILE NAME [STR]'                          , 'value' => $ofF         , 'comp' => 0 , 'data' => 0 },
				'outFileFastaFasta' => {'desc' => 'OUTPUT FILE NAME [STR]'                          , 'value' => $ofFasta     , 'comp' => 0 , 'data' => 0 },
				'confFile'          => {'desc' => 'CONFIG FILE [STR] {more than one allowed}'       , 'value' => ""           , 'comp' => 0 , 'data' => 0 },

				'1stline'           => {'desc' => 'FIRST LINE NUMBER'                               , 'value' => 3            , 'comp' => 0 , 'data' => 0 },
				'groupByCol1Filter' => {'desc' => 'FILTER OF FIRST GROUP BY COLUMN'                 , 'value' => ''           , 'comp' => 0 , 'data' => 0 },
				#'groupByCol1Filter' => {'desc' => 'FILTER OF FIRST GROUP BY COLUMN'                 , 'value' => 'FLANK'     , 'comp' => 0 , 'data' => 0 },
				#'groupByCol1Filter' => {'desc' => 'FILTER OF FIRST GROUP BY COLUMN'                 , 'value' => 'FLANK\b|\]_\d+\b'    , 'comp' => 0 , 'data' => 0 },
				#'groupByCol1Filter' => {'desc' => 'FILTER OF FIRST GROUP BY COLUMN'                 , 'value' => '^\S+\d+\s'  , 'comp' => 0 , 'data' => 0 },
				'groupByCol1'       => {'desc' => 'FIRST COLUMN TO GROUP BY'                        , 'value' => 'queryId'    , 'comp' => 1 , 'data' => 0 },
				# query sequence name
				'groupByCol2'       => {'desc' => 'SECOND COLUMN TO GROUP BY'                       , 'value' => 'hitsId'     , 'comp' => 1 , 'data' => 0 },
				# organism
				'alignCol'          => {'desc' => 'ALIGNMENT COLUMN'                                , 'value' => 'aln'        , 'comp' => 1 , 'data' => 0 },

				'QstartCol'         => {'desc' => 'QUERY START POSITION COLUMN'                     , 'value' => 'Qstart'     , 'comp' => 1 , 'data' => 1 },
				'QendCol'           => {'desc' => 'QUERY END POSITION COLUMN'                       , 'value' => 'Qend'       , 'comp' => 1 , 'data' => 1 },
				'QlengthCol'        => {'desc' => 'QUERY FIRST GROUP BY LENGTH COLUMN'              , 'value' => 'querylength', 'comp' => 1 , 'data' => 1 },
				'HstartCol'         => {'desc' => 'HIT START POSITION COLUMN'                       , 'value' => 'Hstart'     , 'comp' => 1 , 'data' => 1 },
				'HendCol'           => {'desc' => 'HIT END POSITION COLUMN'                         , 'value' => 'Hend'       , 'comp' => 1 , 'data' => 1 },
				'HlengthCol'        => {'desc' => 'HIT SECOND GROUP BY LENGTH COLUMN'               , 'value' => 'Hlength'    , 'comp' => 1 , 'data' => 1 },
				'HStrandCol'        => {'desc' => 'HIT SECOND GROUP BY STRAND COLUMN'               , 'value' => 'Hstrand'    , 'comp' => 1 , 'data' => 1 },
				'HNameCol'          => {'desc' => 'HIT SECOND GROUP BY NAME COLUMN'                 , 'value' => 'hitName'    , 'comp' => 1 , 'data' => 1 },
				# chromossome
				'HitId'             => {'desc' => 'HIT ID'                                          , 'value' => 'hitId'      , 'comp' => 1 , 'data' => 1 }
				# hit number
			);



	%ARGS = %DARGS;

	for (my $a = 2; $a < @ARGV; $a++)
	{
		my $arg = $ARGV[$a];
		if ( index($arg, ":") != -1 )
		{
			my $name  = substr($arg, 0, index($arg, ":"));
			my $value = substr($arg, index($arg, ":")+1);
			#print "NAME $name VALUE $value\n";
			if (( exists $ARGS{$name} ) && ( exists ${$ARGS{$name}}{value} ) && ( $value ne $DARGS{$name}{value}) )
			{
				if ( $ARGS{$name}{value} ne "" )
				{
					$ARGS{$name}{value} .= ";$value";
				} else
				{
					$ARGS{$name}{value} = $value;
				}
			}
		}
	}

	print "ARGUMENTS [",scalar keys %ARGS,"]:\n";
	map { print "\t$_:", $ARGS{$_}{value}, "\n"; } sort keys %ARGS;

	foreach my $col (sort keys %ARGS)
	{
		my $colDesc = $ARGS{$col}{desc};
		my $colName = $ARGS{$col}{value};
		my $colNeed = $ARGS{$col}{comp};
		my $colData = $ARGS{$col}{data};

		next if ! $colNeed;
		$checkCols{$colName}{name}   = $col;
		$checkCols{$colName}{data}   = $colData;
		$checkCols{$colName}{desc}   = $colDesc;
		$checkCols{$colName}{number} = '';
		printf "\tCHECKING NAME %-11s AS %s\n", $col, $colName;
		$argMaxLeng = length $colName if ((length $colName) > $argMaxLeng);
	}
}

sub revComp
{
    my $sequence  = $_[0];
    $$sequence    = uc($$sequence);
    $$sequence    = reverse($$sequence);
    $$sequence    =~ tr/ACGT/TGCA/;
    return $sequence;
}

sub revCompArray
{
    my $sequence    = $_[0];
	my $sequenceStr = join('', @{$sequence});
	#print "SEQUENCE BEFORE : ",&getTruncated($sequenceStr, $screenWidth),"\n";
	revComp(\$sequenceStr);
	#print "SEQUENCE RC     : ",&getTruncated($sequenceStr, $screenWidth),"\n";
	@{$sequence} = split(//, $sequenceStr);

    #return $$sequence;
}

sub revCompArray2
{
	my %H = ( 'A' => 'T', 'C' => 'G', 'G' => 'C','T' => 'A', 'N' => 'N' );
    my $sequence  = $_[0];
	#print "SEQUENCE BEFORE : ",&getTruncated(join('', @$sequence), $screenWidth),"\n";
    @$sequence    = reverse @$sequence;
	#print "SEQUENCE REVERSE: ",&getTruncated(join('', @$sequence), $screenWidth),"\n";
	map { uc($_) } @$sequence;
	#print "SEQUENCE UC     : ",&getTruncated(join('', @$sequence), $screenWidth),"\n";
	map { $H{$_} } @$sequence;
	#print "SEQUENCE RC     : ",&getTruncated(join('', @$sequence), $screenWidth),"\n\n\n";

    #return $$sequence;
}

sub exportBLAST
{
	#TODO:	NOT WORKING PROPERLY YET.
	#		NEEDS TO MERGE HSPS
	my ($tab, $fasta) = @_;

	my $maxLengK = &getMaxLeng($tab);
	print "EXPORTING ", scalar keys %$tab, " KEYS\n";
	open OF, ">$outFileB" or die "COULD NOT OPEN OUTPUT FILE $outFileB\n";
	foreach my $key1 (sort keys %$tab)
	{
		print "\tEXPORTING KEY '$key1'\n";
		my $sub  = $tab->{$key1};
		my $min  = $sub->{min};
		my $max  = $sub->{max};
		my $len  = $sub->{leng};
		#print "REQUESTING SEQ '".&getTruncated($key1, $maxHeaderWidth) . "'\n";
		my $frag = $fasta->getFragment($key1, 1, $len);
		my $qSeq  = join('', @$frag);
		#print "\t\tLENGTH ", length($qSeq), "\n";

		my @headers;
		my @numbers;
		my @seqs;
		$headers[0]   = sprintf("%-".$maxLengK."s", &getTruncated($key1, $maxHeaderWidth));
		$numbers[0]   = sprintf("%7d %7d %7d %7d %7d", $len, $min, $max, 1, $len);
		$seqs[0]      = $qSeq;
		my $baseWidth = length($headers[0]) + length($numbers[0]);

		foreach my $key2 (sort keys %$sub)
		{
			next if (($key2 eq 'min') || ($key2 eq 'max') || ($key2 eq 'leng'));
			print "\t\tEXPORTING QUERY '$key2'\n";
			my $nfo    = $sub->{$key2};

			my $aln    = $nfo->{aln};
			my $data   = $nfo->{data};

			my $start  = $data->{$ARGS{HstartCol }{value}};
			my $end    = $data->{$ARGS{HendCol   }{value}};
			my $Qstart = $data->{$ARGS{QstartCol }{value}};
			my $Qend   = $data->{$ARGS{QendCol   }{value}};
			my $hLen   = $data->{$ARGS{HlengthCol}{value}};

			my $aln1   = $aln->{aln1};
			my $aln2   = $aln->{aln2};
			my $aln3   = $aln->{aln3};
			my $hSeq   = $aln3;

			if ( $padSequence )
			{
				#print "QRY LEN $len HIT LENG ", length($hSeq), " START $Qstart DIFF ", ($len - length($hSeq)), "\n";
				$hSeq   = "-"x($Qstart-1) . $hSeq . "-"x($len - length($hSeq) );
			}


			push(@headers, sprintf("%-".$maxLengK."s", &getTruncated($key2, $maxHeaderWidth)));
			push(@numbers, sprintf("%7d %7d %7d %7d %7d", $hLen, $start, $end, $Qstart, $Qend));
			push(@seqs,    $hSeq);
		}

		if ( $multAlign )
		{
			for (my $s = 0; $s < $len; $s += $seqWidth)
			{
				my $begin  = $s + 1;
				my $lPiecesSize = $seqWidth;
				for (my $h = 0; $h < @headers; $h++)
				{
					while ( ( $s + $lPiecesSize ) > $len ) { $lPiecesSize-- };
					next if $lPiecesSize == 0;
					my $finish = ($s + $lPiecesSize);
					my $phrase = $headers[$h] . " " . $numbers[$h] . " ";
					my $frag   = substr($seqs[$h], $s, $lPiecesSize);
					printf OF "%-s | %7d %-s %7d\n", $phrase, $begin, $frag, $finish;
				}
				print OF "\n";
			}
			print OF "\n", "="x( $baseWidth + $seqWidth + 10) , "\n\n";
		} else {
			for (my $h = 0; $h < @headers; $h++)
			{
				printf OF "%-s %-s | %-s\n", $headers[$h], $numbers[$h], $seqs[$h];
			}
			print OF "\n", "="x( $baseWidth + $seqWidth + 10) , "\n\n";
		}
	}
	close OF;
	print "EXPORTING COMPLETED\n";
}



1;
