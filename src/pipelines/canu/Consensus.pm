
###############################################################################
 #
 #  This file is part of canu, a software program that assembles whole-genome
 #  sequencing reads into contigs.
 #
 #  This software is based on:
 #    'Celera Assembler' (http://wgs-assembler.sourceforge.net)
 #    the 'kmer package' (http://kmer.sourceforge.net)
 #  both originally distributed by Applera Corporation under the GNU General
 #  Public License, version 2.
 #
 #  Canu branched from Celera Assembler at its revision 4587.
 #  Canu branched from the kmer project at its revision 1994.
 #
 #  This file is derived from:
 #
 #    src/pipelines/ca3g/Consensus.pm
 #
 #  Modifications by:
 #
 #    Brian P. Walenz from 2015-MAR-06 to 2015-AUG-25
 #      are Copyright 2015 Battelle National Biodefense Institute, and
 #      are subject to the BSD 3-Clause License
 #
 #    Brian P. Walenz beginning on 2015-NOV-03
 #      are a 'United States Government Work', and
 #      are released in the public domain
 #
 #    Sergey Koren beginning on 2015-DEC-16
 #      are a 'United States Government Work', and
 #      are released in the public domain
 #
 #  File 'README.licenses' in the root directory of this distribution contains
 #  full conditions and disclaimers for each license.
 ##

package canu::Consensus;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(consensusConfigure consensusCheck consensusLoad consensusAnalyze);

use strict;

use File::Path 2.08 qw(make_path remove_tree);

use canu::Defaults;
use canu::Execution;
use canu::Gatekeeper;
use canu::Unitig;
use canu::HTML;


sub utgcns ($$$) {
    my $asm     = shift @_;
    my $ctgjobs = shift @_;
    my $utgjobs = shift @_;
    my $jobs    = $ctgjobs + $utgjobs;

    my $path    = "unitigging/5-consensus";

    open(F, "> $path/consensus.sh") or caExit("can't open '$path/consensus.sh' for writing: $!", undef);

    print F "#!" . getGlobal("shell") . "\n";
    print F "\n";
    print F getJobIDShellCode();
    print F "\n";
    print F "if [ \$jobid -gt $jobs ]; then\n";
    print F "  echo Error: Only $jobs partitions, you asked for \$jobid.\n";
    print F "  exit 1\n";
    print F "fi\n";
    print F "\n";
    print F "if [ \$jobid -le $ctgjobs ] ; then\n";
    print F "  tag=\"ctg\"\n";
    print F "else\n";
    print F "  tag=\"utg\"\n";
    print F "  jobid=`expr \$jobid - $ctgjobs`\n";
    print F "fi\n";
    print F "\n";
    print F "jobid=`printf %04d \$jobid`\n";
    print F "\n";
    print F "if [ ! -d ./\${tag}cns ] ; then\n";
    print F "  mkdir -p ./\${tag}cns\n";
    print F "fi\n";
    print F "\n";
    print F "if [ -e ./\${tag}cns/\$jobid.cns ] ; then\n";
    print F "  exit 0\n";
    print F "fi\n";
    print F "\n";
    print F getBinDirectoryShellCode();
    print F "\n";
    print F "\$bin/utgcns \\\n";
    print F "  -G ../$asm.\${tag}Store/partitionedReads.gkpStore \\\n";      #  Optional; utgcns will default to this
    print F "  -T ../$asm.\${tag}Store 1 \$jobid \\\n";
    print F "  -O ./\${tag}cns/\$jobid.cns.WORKING \\\n";
    print F "  -maxcoverage " . getGlobal('cnsMaxCoverage') . " \\\n";
    print F "  -e " . getGlobal("cnsErrorRate") . " \\\n";
    print F "  -quick \\\n"      if (getGlobal("cnsConsensus") eq "quick");
    print F "  -pbdagcon \\\n"   if (getGlobal("cnsConsensus") eq "pbdagcon");
    print F "  -edlib    \\\n"   if (getGlobal("canuIteration") > 0);
    print F "  -utgcns \\\n"     if (getGlobal("cnsConsensus") eq "utgcns");
    print F "  -threads " . getGlobal("cnsThreads") . " \\\n";
    print F "&& \\\n";
    print F "mv ./\${tag}cns/\$jobid.cns.WORKING ./\${tag}cns/\$jobid.cns \\\n";
    print F "\n";
    print F "exit 0\n";

    if (getGlobal("canuIteration") == 0) {
        print STDERR "-- Using fast alignment for consensus.\n";
    } else {
        print STDERR "-- Using slow alignment for consensus.\n";
    }


    close(F);
}



sub cleanupPartitions ($$) {
    my $asm    = shift @_;
    my $tag    = shift @_;

    return  if (! -e "unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions/map");

    my $gkpTime = -M "unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions/map";
    my $tigTime = -M "unitigging/$asm.ctgStore/seqDB.v001.tig";

    return  if ($gkpTime <= $tigTime);

    print STDERR "-- Partitioned gkpStore is older than tigs, rebuild partitioning (gkpStore $gkpTime days old; ctgStore $tigTime days old).\n";

    if (runCommandSilently("unitigging", "rm -rf ./$asm.${tag}Store/partitionedReads.gkpStore", 1)) {
        caExit("failed to remove old partitions (unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions), can't continue until these are removed", undef);
    }
}



sub partitionReads ($$) {
    my $asm    = shift @_;
    my $tag    = shift @_;
    my $bin    = getBinDirectory();
    my $cmd;

    return  if (-e "unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions/map");

    $cmd  = "$bin/gatekeeperPartition \\\n";
    $cmd .= "  -G ./$asm.gkpStore \\\n";
    $cmd .= "  -T ./$asm.${tag}Store 1 \\\n";
    $cmd .= "  -b " . getGlobal("cnsPartitionMin") . " \\\n"   if (defined(getGlobal("cnsPartitionMin")));
    $cmd .= "  -p " . getGlobal("cnsPartitions")   . " \\\n"   if (defined(getGlobal("cnsPartitions")));
    $cmd .= "> ./$asm.${tag}Store/partitionedReads.err 2>&1";

    if (runCommand("unitigging", $cmd)) {
        caExit("failed to partition the reads", "unitigging/$asm.${tag}Store/partitionedReads.err");
    }
}



sub computeNumberOfConsensusJobs ($$) {
    my $asm    = shift @_;
    my $tag    = shift @_;
    my $jobs   = 0;
    my $bin    = getBinDirectory();

    open(F, "ls unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions/blobs.* |") or caExit("failed to find partitioned files in 'unitigging/$asm.${tag}Store/partitionedReads.gkpStore/partitions/blobs.*': $!", undef);
    while (<F>) {
        if (m/blobs.(\d+)$/) {
            $jobs = int($1);
        }
    }
    close(F);

    return($jobs);
}



sub consensusConfigure ($) {
    my $asm    = shift @_;
    my $bin    = getBinDirectory();
    my $cmd;
    my $path   = "unitigging/5-consensus";

    goto allDone   if (skipStage($asm, "consensusConfigure") == 1);
    goto allDone   if ((-e "unitigging/$asm.ctgStore/seqDB.v002.tig") &&
                       (-e "unitigging/$asm.utgStore/seqDB.v002.tig"));

    make_path("$path")  if (! -d "$path");

    #  If the gkpStore partitions are older than the ctgStore unitig output, assume the unitigs have
    #  changed and remove the gkpStore partition.  -M is (annoyingly) 'file age', so we need to
    #  rebuild if gkp is older (larger) than tig.

    cleanupPartitions($asm, "ctg");
    cleanupPartitions($asm, "utg");

    #  Partition gkpStore if needed.  Yeah, we could create both at the same time, with significant
    #  effort in coding it up.

    partitionReads($asm, "ctg");
    partitionReads($asm, "utg");

    #  Set up the consensus compute.  It's in a useless if chain because there used to be
    #  different executables; now they're all rolled into utgcns itself.

    my $ctgjobs = computeNumberOfConsensusJobs($asm, "ctg");
    my $utgjobs = computeNumberOfConsensusJobs($asm, "utg");

    #  This configure is an odd-ball.  Unlike all the other places that write scripts,
    #  we'll rewrite this one every time, so that we can change the alignment algorithm
    #  on the second attempt.

    my $firstTime = (! -e "$path/consensus.sh");

    if ((getGlobal("cnsConsensus") eq "quick") ||
        (getGlobal("cnsConsensus") eq "pbdagcon") ||
        (getGlobal("cnsConsensus") eq "utgcns")) {
        utgcns($asm, $ctgjobs, $utgjobs);

    } else {
        caFailure("unknown consensus style '" . getGlobal("cnsConsensus") . "'", undef);
    }

    print STDERR "-- Configured $ctgjobs contig and $utgjobs unitig consensus jobs.\n";

  finishStage:
    emitStage($asm, "consensusConfigure")   if ($firstTime);
    buildHTML($asm, "utg");

  allDone:
    stopAfter("consensusConfigure");
}





#  Checks that all consensus jobs are complete, loads them into the store.
#
sub consensusCheck ($) {
    my $asm     = shift @_;
    my $attempt = getGlobal("canuIteration");
    my $path    = "unitigging/5-consensus";

    goto allDone  if (skipStage($asm, "consensusCheck", $attempt) == 1);
    goto allDone  if ((-e "$path/ctgcns.files") && (-e "$path/utgcns.files"));
    goto allDone  if (-e "unitigging/$asm.ctgStore/seqDB.v002.tig");

    #  Figure out if all the tasks finished correctly.

    my $ctgjobs = computeNumberOfConsensusJobs($asm, "ctg");
    my $utgjobs = computeNumberOfConsensusJobs($asm, "utg");
    my $jobs = $ctgjobs + $utgjobs;

    my $currentJobID = "0001";
    my $tag          = "ctgcns";

    my @ctgSuccessJobs;
    my @utgSuccessJobs;
    my @failedJobs;
    my $failureMessage = "";

    for (my $job=1; $job <= $jobs; $job++) {
        if      (-e "$path/$tag/$currentJobID.cns") {
            push @ctgSuccessJobs, "5-consensus/$tag/$currentJobID.cns\n"      if ($tag eq "ctgcns");
            push @utgSuccessJobs, "5-consensus/$tag/$currentJobID.cns\n"      if ($tag eq "utgcns");

        } elsif (-e "$path/$tag/$currentJobID.cns.gz") {
            push @ctgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.gz\n"   if ($tag eq "ctgcns");
            push @utgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.gz\n"   if ($tag eq "utgcns");

        } elsif (-e "$path/$tag/$currentJobID.cns.bz2") {
            push @ctgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.bz2\n"  if ($tag eq "ctgcns");
            push @utgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.bz2\n"  if ($tag eq "utgcns");

        } elsif (-e "$path/$tag/$currentJobID.cns.xz") {
            push @ctgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.xz\n"   if ($tag eq "ctgcns");
            push @utgSuccessJobs, "5-consensus/$tag/$currentJobID.cns.xz\n"   if ($tag eq "utgcns");

        } else {
            $failureMessage .= "--   job $tag/$currentJobID.cns FAILED.\n";
            push @failedJobs, $job;
        }

        $currentJobID++;

        $currentJobID = "0001"    if ($job == $ctgjobs);  #  Reset for first utg job.
        $tag          = "utgcns"  if ($job == $ctgjobs);
    }

    #  Failed jobs, retry.

    if (scalar(@failedJobs) > 0) {

        #  If not the first attempt, report the jobs that failed, and that we're recomputing.

        if ($attempt > 1) {
            print STDERR "--\n";
            print STDERR "-- ", scalar(@failedJobs), " consensus jobs failed:\n";
            print STDERR $failureMessage;
            print STDERR "--\n";
        }

        #  If too many attempts, give up.

        if ($attempt > getGlobal("canuIterationMax")) {
            caExit("failed to generate consensus.  Made " . ($attempt-1) . " attempts, jobs still failed", undef);
        }

        #  Otherwise, run some jobs.

        emitStage($asm, "consensusCheck", $attempt);
        buildHTML($asm, "utg");

        submitOrRunParallelJob($asm, "cns", $path, "consensus", @failedJobs);
        return;
    }

  finishStage:
    print STDERR "-- All ", scalar(@ctgSuccessJobs) + scalar(@utgSuccessJobs), " consensus jobs finished successfully.\n";

    open(L, "> $path/ctgcns.files") or caExit("can't open '$path/ctgcns.files' for writing: $!", undef);
    print L @ctgSuccessJobs;
    close(L);

    open(L, "> $path/utgcns.files") or caExit("can't open '$path/utgcns.files' for writing: $!", undef);
    print L @utgSuccessJobs;
    close(L);

    emitStage($asm, "consensusCheck");
    buildHTML($asm, "utg");

  allDone:
}



sub purgeFiles ($$$$$) {
    my $tag     = shift @_;
    my $Ncns    = shift @_;
    my $Nfastq  = shift @_;
    my $Nlayout = shift @_;
    my $Nlog    = shift @_;

    my $path = "unitigging/5-consensus";

    open(F, "< $path/$tag.files") or caExit("can't open '$path/$tag.files' for reading: $!\n", undef);
    while (<F>) {
        chomp;
        if (m/^(.*)\/0*(\d+).cns$/) {
            my $ID6 = substr("00000" . $2, -6);
            my $ID4 = substr("000"   . $2, -4);
            my $ID0 = $2;

            if (-e "$1/$ID4.cns") {
                $Ncns++;
                unlink "$1/$ID4.cns";
            }
            if (-e "$1/$ID4.fastq") {
                $Nfastq++;
                unlink "$1/$ID4.fastq";
            }
            if (-e "$1/$ID4.layout") {
                $Nlayout++;
                unlink "$1/$ID4.layout";
            }
            if (-e "$1/consensus.$ID6.out") {
                $Nlog++;
                unlink "$1/consensus.$ID6.out";
            }
            if (-e "$1/consensus.$ID0.out") {
                $Nlog++;
                unlink "$1/consensus.$ID0.out";
            }

        } else {
            caExit("unknown consensus job name '$_'\n", undef);
        }
    }
    close(F);

    return($Ncns, $Nfastq, $Nlayout, $Nlog);
}



sub consensusLoad ($) {
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;
    my $path    = "unitigging/5-consensus";

    goto allDone    if (skipStage($asm, "consensusLoad") == 1);
    goto allDone    if ((-e "unitigging/$asm.ctgStore/seqDB.v002.tig") && (-e "unitigging/$asm.utgStore/seqDB.v002.tig"));

    #  Expects to have a list of output files from the consensusCheck() function.

    caExit("can't find '$path/ctgcns.files' for loading tigs into store: $!", undef)  if (! -e "$path/ctgcns.files");
    caExit("can't find '$path/utgcns.files' for loading tigs into store: $!", undef)  if (! -e "$path/utgcns.files");

    #  Now just load them.

    $cmd  = "$bin/tgStoreLoad \\\n";
    $cmd .= "  -G ./$asm.gkpStore \\\n";
    $cmd .= "  -T ./$asm.ctgStore 2 \\\n";
    $cmd .= "  -L 5-consensus/ctgcns.files \\\n";
    $cmd .= "> 5-consensus/ctgcns.files.ctgStoreLoad.err 2>&1";

    if (runCommand("unitigging", $cmd)) {
        caExit("failed to load unitig consensus into ctgStore", "$path/ctgcns.files.ctgStoreLoad.err");
    }

    $cmd  = "$bin/tgStoreLoad \\\n";
    $cmd .= "  -G ./$asm.gkpStore \\\n";
    $cmd .= "  -T ./$asm.utgStore 2 \\\n";
    $cmd .= "  -L 5-consensus/utgcns.files \\\n";
    $cmd .= "> 5-consensus/utgcns.files.utgStoreLoad.err 2>&1";

    if (runCommand("unitigging", $cmd)) {
        caExit("failed to load unitig consensus into utgStore", "$path/utgcns.files.utgStoreLoad.err");
    }

    #  Remvoe consensus outputs

    if ((-e "$path/ctgcns.files") ||
        (-e "$path/utgcns.files")) {
        print STDERR "-- Purging consensus output after loading to ctgStore and/or utgStore.\n";

        my $Ncns    = 0;
        my $Nfastq  = 0;
        my $Nlayout = 0;
        my $Nlog    = 0;

        ($Ncns, $Nfastq, $Nlayout, $Nlog) = purgeFiles("ctgcns", $Ncns, $Nfastq, $Nlayout, $Nlog);
        ($Ncns, $Nfastq, $Nlayout, $Nlog) = purgeFiles("utgcns", $Ncns, $Nfastq, $Nlayout, $Nlog);

        print STDERR "-- Purged $Ncns .cns outputs.\n"        if ($Ncns > 0);
        print STDERR "-- Purged $Nfastq .fastq outputs.\n"    if ($Nfastq > 0);
        print STDERR "-- Purged $Nlayout .layout outputs.\n"  if ($Nlayout > 0);
        print STDERR "-- Purged $Nlog .err log outputs.\n"    if ($Nlog > 0);
    }

    reportUnitigSizes($asm, 2, "after consensus generation");

  finishStage:
    emitStage($asm, "consensusLoad");
    buildHTML($asm, "utg");
  allDone:
}




sub consensusAnalyze ($) {
    my $asm     = shift @_;
    my $bin     = getBinDirectory();
    my $cmd;

    goto allDone   if (skipStage($asm, "consensusAnalyze") == 1);
    goto allDone   if (-e "unitigging/$asm.ctgStore/status.coverageStat");

    $cmd  = "$bin/tgStoreCoverageStat \\\n";
    $cmd .= "  -G ./$asm.gkpStore \\\n";
    $cmd .= "  -T ./$asm.ctgStore 2 \\\n";
    $cmd .= "  -s " . getGlobal("genomeSize") . " \\\n";
    $cmd .= "  -o ./$asm.ctgStore.coverageStat \\\n";
    $cmd .= "> ./$asm.ctgStore.coverageStat.err 2>&1";

    if (runCommand("unitigging", $cmd)) {
        caExit("failed to compute coverage statistics", "unitigging/$asm.ctgStore.coverageStat.err");
    }

    unlink "unitigging/$asm.ctgStore.coverageStat.err";

  finishStage:
    emitStage($asm, "consensusAnalyze");
    buildHTML($asm, "utg");
    touch("unitigging/$asm.ctgStore/status.coverageStat");
  allDone:
    stopAfter("consensus");
}
