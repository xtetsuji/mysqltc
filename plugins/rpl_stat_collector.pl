#!/usr/bin/env perl
#
# This script will purge obsolete binlog files which had been read by all
# slaves. This script could be run as a contab task daily or any other ways.
#
# This script must be work with MySQL plugin: rpl_stat_plugin
#
# WARNING: all slaves should be connected to master at least once, to make sure
# that every slaves were recorded accordingly.

use strict;
use warnings;

##editing area#########################################################
# serverid->binlogfile mapping
my %rpl_stats;

# replication status file store
my $rpl_stats_file = '/tmp/rpl_stats_hash.log';

# rpl_stat_plugin output history log directory
my $rpl_stat_output_log_dir = '/tmp';
# outputs need to be processed
my @rpl_stat_outputs;
# output file regex
my $re_rpl_stat_outputs = '^rpl-stat\.log\.\d*$';
my $re_rpl_stat_line_format =
    '^server_id:(.*), binlog_file:(.*), offset:(.*)$';

# MySQL binlog index file
my $binlog_index_file = '/tmp/mysql-bin.index';
# binlog files array from binlog index file
my @binlog_files;
##editing area$$######################################################


# read previous replication statuses
sub init_rpl_stats {
    open(my $log, "<", $rpl_stats_file) or
        die "Can't open $rpl_stats_file: $!";
    while(my $line = <$log>) {
        $line =~ s/^\s+|\s+$//g;
        next if ((length $line) == 0);
        $line =~ /(.*) (.*)/;
        $rpl_stats{$1} = $2;
    }
    close $log or die "$log: $!";
}

# write out current replication statuses
sub persist_rpl_stats {
    open(my $log, ">", $rpl_stats_file) or
        die "Can't not open $rpl_stats_file: $!";
    foreach my $key (sort (keys (%rpl_stats))) {
        print $log $key." ".$rpl_stats{$key}."\n";
    }
    close $log or die "$log: $!";
}

# parse all rpl_stat_plugin history outputs which generated by logrotate
# by match file name subfix
sub parse_stats_log {
    opendir my $dir, $rpl_stat_output_log_dir or
        die "Can't open $rpl_stat_output_log_dir: $!";
    my @files = grep { /$re_rpl_stat_outputs/ } readdir($dir);
    closedir $dir;
    
    # sort outputs
    my %hfiles;
    foreach (@files) {
        /.*\.(\d*)/;
        $hfiles{$1} = $_;
    }
    foreach (reverse sort {$a <=> $b} (keys %hfiles)) {
        push @rpl_stat_outputs, $hfiles{$_};
    }

    # parse rpl_stat output contents
    foreach my $file_name (@rpl_stat_outputs) {
        my $real_file_name = $rpl_stat_output_log_dir.'/'.$file_name;
        open(my $file, "<", $real_file_name) or
            die "Can't open $file_name: $!";
        while (my $line = <$file>) {
            $line =~ s/^\s+|\s+$//g;
            next if ((length $line) == 0);
            $line =~ qr/$re_rpl_stat_line_format/;
            $rpl_stats{$1} = $2;
        }
        close($file) or die "$file: $!";
        unlink $real_file_name or warn "Can't unlink $real_file_name: $!";
    }
}

# pruge all logs which had been read by all slaves
sub purge_logs {
    # parse mysql binlog index file
    open(my $index_file, "<", $binlog_index_file) or
        die "Can't open $binlog_index_file: $!";
    while (my $line = <$index_file>) {
        $line =~ s/^\s+|\s+$//g;
        next if ((length $line) == 0);
        push @binlog_files, $line;
    }
    close($index_file) or die "$index_file: $!";

    # strip out logs which still were using
    my $binlog_file_count = @binlog_files;
    my @cur_binlog_files = values %rpl_stats;
    my $end = -1;
  LOOP: for (my $i = 0; $i < $binlog_file_count; $i++) {
        my $binlog_file = $binlog_files[$i];
        $binlog_file =~ s/^.*\///g;
        foreach my $cur_binlog_file (@cur_binlog_files) {
            if ($binlog_file eq $cur_binlog_file) {
                $end = $i;
                last LOOP;
            }    
        }
    }
    
    $end -= 1;
    if ($end >= 0) {
        @binlog_files = @binlog_files[0..$end];
    } else {
        # no files need to be purged
        return;
    }

    # remove obsolete binlogs
    foreach my $file (@binlog_files) {
        unlink $file or warn "Can't unlink $file: $!";
    }
}

sub main {
    init_rpl_stats();
    parse_stats_log();
    purge_logs();
    persist_rpl_stats();
}


main();
