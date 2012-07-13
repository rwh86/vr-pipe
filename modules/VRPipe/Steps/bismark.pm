=head1 NAME

VRPipe::Steps::bismark - a step

=head1 DESCRIPTION

*** more documentation to come

=head1 AUTHOR

NJWalker <nw11@sanger.ac.uk>.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012 Genome Research Limited.

This file is part of VRPipe.

VRPipe is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see L<http://www.gnu.org/licenses/>.

=cut

use VRPipe::Base;

class VRPipe::Steps::bismark with VRPipe::StepRole {
use File::Basename;
use Data::Dumper;
     method options_definition {
        return {
                  bismark_exe => VRPipe::StepOption->get(description => 'path to your bismark executable', optional => 1, default_value => $ENV{BISMARK_EXE}),
                 paired => VRPipe::StepOption->get(description => 'path to your bismark executable', optional => 1, default_value => '0'),
                 bismark_genome_folder => VRPipe::StepOption->get( description => 'path to your bismark genome folder', optional => 1, default_value => $ENV{BISMARK_GENOME_FOLDER} )
        }
    }

    method inputs_definition {
        return {
                # sequence file - fastq for now
    fastq_files => VRPipe::StepIODefinition->get(type => 'fq', max_files => -1, description => '1 or more fastq files')
        };
    }

    method body_sub {
        return sub {
            # We need to ensure that the bismark version is >= 0.7.4 since this allows full paths to the input files
            my $self = shift;
            my $options = $self->options;
            my $bismark_exe = $options->{bismark_exe};
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'bismark', version => VRPipe::StepCmdSummary->determine_version($bismark_exe . ' --version', 'Bismark Version:  (.+) '), summary => 'bismark -o output_file bismark_genome_folder input_file'));
            my $req = $self->new_requirements(memory =>500, time => 1); #16GB RAM? Could be 8GB?
        
            # Single end case
            my @input_file =  @{$self->inputs->{fastq_files}};
            $self->throw("One input file expected") unless ( @input_file == 1);            
 
            my ($name) = fileparse( $input_file[0]->basename, ('.fastq') );
            
            my $output_file_1 = $self->output_file( output_key => 'bismark_report',
                                          basename => $name . "/$name.fastq_Bismark_mapping_report.txt",
                                          type => 'txt',
                                          metadata => $input_file[0]->metadata);
            
            my $output_file_2 = $self->output_file( output_key => 'bismark_sam',
                                          basename => $name . "/$name.fastq_bismark.sam",
                                          type => 'txt',
                                          metadata => $input_file[0]->metadata);
          
	   #* Think about whether need any of the info bismark spits out, prob not 
           #* my $stdoutput_file = $self->output_file( output_key => 'bismark_output',
           #*                              basename => $name . '.out.txt',
           #*                              type => 'txt',
           #*                              metadata => $input_file[0]->metadata);
           #* my $stdoutput_file_path = $stdoutput_file->path;

            my $bismark_genome_folder = $options->{bismark_genome_folder};
            my $output_file_dir = $output_file_1->dir->stringify;
            my $input_file_path  = $input_file[0]->path;
            my $cmd ="perl $bismark_exe -o $output_file_dir $bismark_genome_folder $input_file_path";
           #* my $cmd ="perl $bismark_exe -o $output_file_dir $bismark_genome_folder $input_file_path >& $stdoutput_file_path";
            my $out = $self->dispatch([ qq[$cmd], $req, { output_files => [$output_file_1, $output_file_2 ] } ] );
       } 
    }

    method outputs_definition {
        return { 
              bismark_sam => VRPipe::StepIODefinition->get(type => 'txt', description => 'bismark mapped sequences files in sam format'),
              bismark_report => VRPipe::StepIODefinition->get(type => 'txt', description => 'bismark mapped sequences files in sam format')
        };
    } 

    method description {
        return  "Step for bismark Bisulfite sequencing mapper";
    }

    method post_process_sub {
        return sub { return 1; };
    }

    method max_simultaneous {
        return 0; # meaning unlimited
    }

}
