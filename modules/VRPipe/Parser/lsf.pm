use VRPipe::Base;

class VRPipe::Parser::lsf with VRPipe::ParserRole {
    our %months = qw(Jan 1
                     Feb 2
                     Mar 3
                     Apr 4
                     May 5
                     Jun 6
                     Jul 7
                     Aug 8
                     Sep 9
                     Oct 10
                     Nov 11
                     Dec 12);
    our $date_regex = qr/(\w+)\s+(\d+) (\d+):(\d+):(\d+)/;
    
=head2 parsed_record

 Title   : parsed_record
 Usage   : my $parsed_record= $obj->parsed_record()
 Function: Get the data structure that will hold the last parsed record
           requested by next_record()
 Returns : array ref, where the elements are:
           [0]  cmd
           [1]  status
           [2]  memory
           [3]  time
           [4]  cpu_time
           [5]  idle_factor
           [6]  queue
 Args    : n/a

=cut
    
=head2 next_record

 Title   : next_record
 Usage   : while ($obj->next_record()) { # look in parsed_record }
 Function: Parse the next report from the lsf file, starting with the last and
           working backwards.
 Returns : boolean (false at end of output; check the parsed_record for the
           actual information)
 Args    : n/a

=cut
    method next_record {
        # just return if no file set
        my $fh = $self->fh() || return;
        
        # we're only interested in the small LSF-generated report, which may be
        # prefaced by an unlimited amount of output from the program that LSF
        # ran, so we go line-by-line to find our little report. Typically we're
        # only interested in the last result, so we're also actually reading the
        # file backwards
        my ($found_report_start, $found_report_end, $next_is_cmd);
        my ($started, $finished, $cmd, $mem, $status,$queue);
        my $cpu = 0;
        while (<$fh>) {
            if (/^Sender: LSF System/) {
                $found_report_start = 1;
                last;
            }
            elsif (/^The output \(if any\) is above this job summary/) {
                $found_report_end = 1;
                next;
            }
            
            if ($found_report_end) {
                if (/^Started at \S+ (.+)$/) { $started = $1; }
                elsif (/^Job was executed.+in queue \<([^>]+)\>/) { $queue = $1; }
                elsif (/^Results reported at \S+ (.+)$/) { $finished = $1; }
                elsif (/^# LSBATCH: User input/) { $next_is_cmd = 0; }
                elsif ($next_is_cmd) {
                    $cmd .= $_;
                }
                elsif (!$cmd && $status && /^------------------------------------------------------------/) {
                    $next_is_cmd = 1;
                }
                elsif (/^Successfully completed/) { $status = 'OK'; }
                elsif (/^Cannot open your job file/) { $status = 'unknown'; }
                elsif (! $status && /^Exited with exit code/) { $status = 'exited'; }
                elsif (/^TERM_\S+ job killed by/) { $status = 'killed'; }
                elsif (/^TERM_([^:]+):/) { $status = $1; }
                elsif (/^\s+CPU time\s+:\s+(\S+)/) { $cpu = $1; }
                elsif (/^\s+Max Memory\s+:\s+(\S+)\s+(\S+)/) { 
                    $mem = $1;
                    if ($2 eq 'KB') { $mem /= 1024; }
                    elsif ($2 eq 'GB') { $mem *= 1024; }
                }
            }
        }
        
        # if we didn't see a whole LSF report, assume eof
        unless ($found_report_start && $found_report_end) {
            return;
        }
        unless ($status) {
            $self->warn("a status was not parsed out of a result in ".$self->file);
        }
        
        chomp($cmd) if $cmd;
        
        # calculate wall time and idle factor
        my ($smo, $sd, $sh, $sm, $ss) = $started =~ /$date_regex/;
        my ($emo, $ed, $eh, $em, $es) = $finished =~ /$date_regex/;
        my $dt = DateTime->new(year => 2010, month => $months{$smo}, day => $sd, hour => $sh, minute => $sm, second => $ss);
        my $st = $dt->epoch;
        $dt = DateTime->new(year => 2010, month => $months{$emo}, day => $ed, hour => $eh, minute => $em, second => $es);
        my $et = $dt->epoch;
        my $wall = $et - $st;
        my $idle = sprintf("%0.2f", ($cpu < 1 ? 1 : $cpu) / ($wall < 1 ? 1 : $wall));
        
        # fill in the parsed_record
        my $pr = $self->parsed_record;
        $pr->[0] = $cmd;
        $pr->[1] = $status;
        $pr->[2] = $mem;
        $pr->[3] = $wall;
        $pr->[4] = $cpu;
        $pr->[5] = $idle;
        $pr->[6] = $queue;
        
        return 1;
    }
    
=head2 status

 Title   : status
 Usage   : my $status = $obj->status();
 Function: Get the status of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : string (OK|exited|killed|MEMLIMIT|RUNLIMIT)
 Args    : n/a

=cut
    method status {
        return $self->_get_result(1);
    }
    
    method _get_result (Int $index where {$_ >= 0 && $_ <= 6}) {
        my $pr = $self->parsed_record;
        unless (@$pr == 7) {
            $self->next_record || return;
        }
        return $pr->[$index];
    }
    
=head2 time

 Title   : time
 Usage   : my $time = $obj->time();
 Function: Get the wall-time of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : int (s)
 Args    : n/a

=cut
    method time {
        return $self->_get_result(3);
    }
    
=head2 cpu_time

 Title   : cpu_time
 Usage   : my $time = $obj->cpu_time();
 Function: Get the cpu-time of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : real number (s)
 Args    : n/a

=cut
    method cpu_time {
        return $self->_get_result(4);
    }
    
=head2 idle_factor

 Title   : idle_factor
 Usage   : my $idle_factor = $obj->idle_factor();
 Function: Compare cpu time to wall time to see what proportion was spent
           waiting on disc.
 Returns : real number 0-1 inclusive (1 means no time spent waiting on disc, 0
           means the cpu did nothing and we spent all time waiting on disc)
 Args    : n/a

=cut
    method idle_factor {
        return $self->_get_result(5);
    }
    
=head2 memory

 Title   : memory
 Usage   : my $memory = $obj->memory();
 Function: Get the max memory used of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : int (s)
 Args    : n/a

=cut
    method memory {
        return $self->_get_result(2);
    }
    
=head2 cmd

 Title   : cmd
 Usage   : my $cmd = $obj->cmd();
 Function: Get the command-line of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : string
 Args    : n/a

=cut
    method cmd {
        return $self->_get_result(0);
    }
    
=head2 queue

 Title   : queue
 Usage   : my $queue = $obj->queue();
 Function: Get the command-line of the current record, or the last record if
           next_record() hasn't been called yet.
 Returns : string
 Args    : n/a

=cut
    method queue {
        return $self->_get_result(6);
    }
}

1;