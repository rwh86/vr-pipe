use VRPipe::Base;

class VRPipe::Steps::stampy_map_fastq with VRPipe::StepRole {
    method options_definition {
        return { reference_fasta => VRPipe::StepOption->get(description => 'absolute path to genome reference file to map against'),
                 stampy_map_options => VRPipe::StepOption->get(description => 'options for stampy mapping, excluding the output, input fastq(s), reference, --bwa and --bwaoptions options',
                                                               optional => 1),
                 stampy_bwa_options => VRPipe::StepOption->get(description => 'to use bwa for premapping, supply the string you would give to --bwaoptions, excluding the reference',
                                                               optional => 1),
                 stampy_exe => VRPipe::StepOption->get(description => 'path to your stampy.py executable',
                                                       optional => 1,
                                                       default_value => 'stampy.py'),
                 bwa_exe => VRPipe::StepOption->get(description => 'path to your bwa executable',
                                                    optional => 1,
                                                    default_value => 'bwa') };
    }
    method inputs_definition {
        return { fastq_files => VRPipe::StepIODefinition->get(type => 'fq',
                                                              max_files => -1,
                                                              description => 'fastq file(s) to be mapped',
                                                              metadata => {lane => 'lane name (a unique identifer for this sequencing run)',
                                                                           library => 'library name',
                                                                           sample => 'sample name',
                                                                           center_name => 'center name',
                                                                           platform => 'sequencing platform, eg. ILLUMINA|LS454|ABI_SOLID',
                                                                           study => 'name of the study, put in the DS field of the RG header line',
                                                                           insert_size => 'expected (mean) insert size if paired',
                                                                           analysis_group => 'project analysis group',
                                                                           population => 'sample population',
                                                                           bases => 'total number of base pairs',
                                                                           reads => 'total number of reads (sequences)',
                                                                           paired => '0=unpaired; 1=reads in this file are forward; 2=reads in this file are reverse',
                                                                           mate => 'if paired, the path to the fastq that is our mate',
                                                                           chunk => 'if the fastq file was produced by fastq_split Step, the chunk number',
                                                                           optional => ['mate', 'chunk', 'library', 'insert_size', 'analysis_group', 'population', 'sample', 'center_name', 'platform', 'study']}) };
    }
    method body_sub {
        return sub {
            my $self = shift;
            my $options = $self->options;
            my $ref = Path::Class::File->new($options->{reference_fasta});
            $self->throw("reference_fasta must be an absolute path") unless $ref->is_absolute;
            
            my $stampy_exe = $options->{stampy_exe};
            my $stampy_opts = $options->{stampy_map_options};
            if ($stampy_opts =~ /$ref|-h|-g|--bwa=|bwaoptions|-M|-o|-f/) {
                $self->throw("stampy_map_options should not include the output, input fastq(s), reference, --bwa nor --bwaoptions options");
            }
            
            my $bwa_opts = $options->{stampy_bwa_options};
            if ($bwa_opts) {
                if ($bwa_opts =~ /$ref/) {
                    $self->throw("stampy_bwa_options should not include the reference");
                }
                $stampy_opts .= ' --bwa='.$options->{bwa_exe}.' --bwaoptions={'.$bwa_opts.' '.$ref.'}'; # {} instead of "" because of quoting in shell issues
            }
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'stampy.py', version => VRPipe::StepCmdSummary->determine_version($stampy_exe, '^stampy v(\S+)'), summary => 'stampy.py '.$stampy_opts.' -g $ref.fa -h $ref.fa -o $out.sam -M $fastq(s)'));
            
            my $req = $self->new_requirements(memory => 5900, time => 2);
            my $cmd = $stampy_exe.' '.$stampy_opts." -g $ref -h $ref ";
            
            # we can handle the input of both a single-ended fastq, and 2
            # paired-end fastqs, and groups of these (up to) 3 files for
            # multiple different lanes
            my @fq_files = @{$self->inputs->{fastq_files}};
            my %fqs_by_lane;
            my %fqs_by_path;
            foreach my $fq (@fq_files) {
                my $fq_meta = $fq->metadata;
                my $paired = $fq_meta->{paired};
                my $path = $fq->resolve->path->stringify; # since we're storing this path in output metadata, we want the real path of the fq, not that of a symlink
                my $lane = $fq_meta->{lane};
                my $chunk = $fq_meta->{chunk} || 0;
                $fqs_by_path{$path} = [$lane, $chunk, $paired, $fq_meta];
                $fqs_by_lane{$lane}->{$chunk}->{$paired} = $path;
            }
            
            while (my ($lane, $chunks) = each %fqs_by_lane) {
                while (my ($chunk, $ends) = each %$chunks) {
                    while (my ($paired, $path) = each %$ends) {
                        next if $paired == 2;
                        
                        my @fqs = ($path);
                        my $fq_meta = $fqs_by_path{$fqs[0]}->[3];
                        my $reads = $fq_meta->{reads};
                        my $bases = $fq_meta->{bases};
                        
                        my $this_cmd;
                        if ($paired == 0) {
                            $this_cmd = $cmd."-M $fqs[0]";
                        }
                        else {
                            my $mate_path = $ends->{2};
                            push(@fqs, $mate_path);
                            
                            $this_cmd = $cmd."-M $fqs[0],$fqs[1]";
                            
                            $reads += $fqs_by_path{$fqs[1]}->[3]->{reads};
                            $bases += $fqs_by_path{$fqs[1]}->[3]->{bases};
                        }
                        
                        # add metadata and construct readgroup info
                        my $rg_arg = 'ID:'.$lane;
                        my $sam_meta = {lane => $lane,
                                        bases => $bases,
                                        reads => $reads,
                                        paired => $paired,
                                        mapped_fastqs => join(',', @fqs),
                                        $chunk ? (chunk => $chunk) : ()};
                        if (defined $fq_meta->{library}) {
                            my $lb = $fq_meta->{library};
                            $sam_meta->{library} = $lb;
                            $rg_arg .= ',LB:'.$lb;
                        }
                        if (defined $fq_meta->{sample}) {
                            my $sm = $fq_meta->{sample};
                            $sam_meta->{sample} = $sm;
                            $rg_arg .= ',SM:'.$sm;
                        }
                        if (defined $fq_meta->{insert_size}) {
                            my $pi = $fq_meta->{insert_size};
                            $sam_meta->{insert_size} = $pi;
                            $rg_arg .= ',PI:'.sprintf("%0.0f", $pi); # stampy enforces an int for PL
                        }
                        if (defined $fq_meta->{center_name}) {
                            my $cn = $fq_meta->{center_name};
                            $sam_meta->{center_name} = $cn;
                            $rg_arg .= ',CN:'.$cn;
                        }
                        if (defined $fq_meta->{platform}) {
                            my $pl = $fq_meta->{platform};
                            $sam_meta->{platform} = $pl;
                            $rg_arg .= ',PL:'.$pl;
                        }
                        if (defined $fq_meta->{study}) {
                            my $ds = $fq_meta->{study};
                            $sam_meta->{study} = $ds;
                            $rg_arg .= ',DS:'.$ds;
                        }
                        if (defined $fq_meta->{analysis_group}) {
                            $sam_meta->{analysis_group} = $fq_meta->{analysis_group};
                        }
                        if (defined $fq_meta->{population}) {
                            $sam_meta->{population} = $fq_meta->{population};
                        }
                        
                        my $ended = $paired ? 'pe' : 'se';
                        my $sam_file = $self->output_file(output_key => 'stampy_sam_files',
                                                          basename => $chunk ? "$lane.$ended.$chunk.sam" : "$lane.$ended.sam",
                                                          type => 'txt',
                                                          metadata => $sam_meta);
                        
                        $this_cmd .= " --readgroup=$rg_arg -o ".$sam_file->path;
                        $self->dispatch_wrapped_cmd('VRPipe::Steps::stampy_map_fastq', 'map_and_check', [$this_cmd, $req, {output_files => [$sam_file]}]);
                    }
                }
            }
        };
    }
    method outputs_definition {
        return { stampy_sam_files => VRPipe::StepIODefinition->get(type => 'txt',
                                                                   max_files => -1,
                                                                   description => 'mapped sam file per endedness and lane',
                                                                   metadata => {lane => 'lane name (a unique identifer for this sequencing run, aka read group)',
                                                                                library => 'library name',
                                                                                sample => 'sample name',
                                                                                center_name => 'center name',
                                                                                platform => 'sequencing platform, eg. ILLUMINA|LS454|ABI_SOLID',
                                                                                study => 'name of the study, put in the DS field of the RG header line',
                                                                                insert_size => 'expected (mean) insert size if paired',
                                                                                analysis_group => 'project analysis group',
                                                                                population => 'sample population',
                                                                                bases => 'total number of base pairs',
                                                                                reads => 'total number of reads (sequences)',
                                                                                paired => '0=unpaired reads were mapped; 1=paired reads were mapped',
                                                                                mapped_fastqs => 'comma separated list of the fastq file(s) that were mapped',
                                                                                chunk => 'if this was mapped with fastqs that were chunks of an original fastq, this tells you which chunk',
                                                                                optional => ['chunk', 'library', 'insert_size', 'analysis_group', 'population', 'sample', 'center_name', 'platform', 'study']}) };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Maps the input fastq(s) with stampy to the reference";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
    
    method map_and_check (ClassName|Object $self: Str $cmd_line) {
        my ($sam_path) = $cmd_line =~ /-o (\S+)/;
        $sam_path || $self->throw("cmd_line [$cmd_line] had no -o output specified");
        $cmd_line =~ s/\{/"/;
        $cmd_line =~ s/\}/"/;
        
        my $sam_file = VRPipe::File->get(path => $sam_path);
        my $expected_reads = $sam_file->metadata->{reads};
        
        $sam_file->disconnect;
        system($cmd_line) && $self->throw("failed to run [$cmd_line]");
        
        $sam_file->update_stats_from_disc(retries => 3);
        my $lines = $sam_file->lines;
        
        if ($lines > $expected_reads) {
            return 1;
        }
        else {
            $sam_file->unlink;
            $self->throw("cmd [$cmd_line] failed because $lines lines were generated in the sam file, yet there were $expected_reads reads in the fastq file(s)");
        }
    }
}

1;