
=head1 NAME

VRPipe::Steps::gmap_build - a step

=head1 DESCRIPTION





GMAP Build creates an index of a genomic sequence for mapping and alignment
using GMAP (Genomic Mapping and Alignment Program for mRNA and EST sequences)
and GSNAP (Genomic Short-read Nucleotide Alignment Program). (GMAP Build uses
GMSP commands: gmap_build, iit_store, psl_splicesites, psl_introns,
gtf_splicesites, gtf_introns, gff3_splicesites, gff3_introns, dbsnp_iit,
snpindex, cmetindex, and atoiindex.)

You will want to read the README

Publication citation: Thomas D. Wu, Colin K. Watanabe Bioinformatics 2005
21(9):1859-1875; doi:10.1093/bioinformatics/bti310

*** more documentation to come

=head1 AUTHOR

NJWalker <nw11@sanger.ac.uk>.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011 Genome Research Limited.

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

class VRPipe::Steps::gmap_build with VRPipe::StepRole {
    use Data::Dumper;
    
    method options_definition {
        return {
            gmap_build_gunzip_file => VRPipe::StepOption->create(
                description   => 'option to gmap_build for building with gunzipped files. Default is for gunzip files.',
                optional      => 1,
                default_value => 1,
            ),
            gmap_build_exe => VRPipe::StepOption->create(
                description   => 'path to your gmap_build executable',
                optional      => 1,
                default_value => 'gmap_build'
            ),
            
            gmap_build_gmap_default_directory => VRPipe::StepOption->create(
                description   => 'Use the default GMAPDB dir as set up in installation. Set to 1 if this is required.',
                optional      => 1,
                default_value => 0
            ),
            
            gmap_build_genome_name => VRPipe::StepOption->create(
                description   => 'name of genome',
                optional      => 0,
                default_value => 'mygenome'
            ),
            
            gmap_build_kmer_size => VRPipe::StepOption->create(
                description   => 'k-mer size used for building the genomic index. The memory requirements for building the index under various k-mer values: 12: 64 MB, 13: 256 MB, 14: 1GB, 15: 4GB. See the gmap README for more details.',
                optional      => 0,
                default_value => 15
              )
        
        };
    }
    
    method inputs_definition {
        return { fastq_files => VRPipe::StepIODefinition->create(type => 'bin', max_files => -1, description => '1 or more fastq files') };
    }
    
    method body_sub {
        return sub {
            my $self    = shift;
            my $options = $self->options;
            
            my $gmap_build_exe                    = $options->{gmap_build_exe};
            my $gmap_build_gunzip_file            = $options->{gmap_build_gunzip_file};
            my $gmap_build_genome                 = $options->{gmap_build_genome_name};
            my $gmap_build_gmap_default_directory = $options->{gmap_build_gmap_default_directory};
            my $gmap_build_kmer_size              = $options->{gmap_build_kmer_size};
            
            my @input_file  = @{ $self->inputs->{fastq_files} };
            my $output_file = $self->output_file(
                output_key => 'gmap_index_txt_file',
                basename   => Path::Class::File->new($gmap_build_genome, $gmap_build_genome . ".chromosome")->stringify,
                type       => 'txt',
                metadata   => $input_file[0]->metadata
            );
            my $output_file_dir = $output_file->dir->parent->stringify;
            my $version = VRPipe::StepCmdSummary->determine_version("perl " . $gmap_build_exe, 'version\W(.+).$');
            
            my $cmd .= $gmap_build_exe;
            $cmd    .= ' -d ' . $gmap_build_genome;
            $cmd    .= ' -k ' . $gmap_build_kmer_size;
            if (!$gmap_build_gmap_default_directory) {
                $cmd .= ' -D ' . $output_file_dir;
            }
            if ($gmap_build_gunzip_file) {
                $cmd .= ' -g';
            }
            $cmd .= ' ' . $input_file[0]->path;
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->create(exe => 'gmap_build', version => $version, summary => $cmd));
            
            $self->dispatch([$cmd, $self->new_requirements(memory => 4500, time => 1), { block_and_skip_if_ok => 1 }]);
        };
    }
    
    method outputs_definition {
        return {
            gmap_index_txt_file => VRPipe::StepIODefinition->create(type => 'txt', description => 'the files produced by gmap index', min_files => 1, max_files => 6),
        };
    }
    
    method post_process_sub {
        return sub { return 1; };
    }
    
    method description {
        return "Indexes a reference genome fasta file, making it suitable for use in subsequent GSNAP mapping";
    }
    
    method max_simultaneous {
        return 0;            # meaning unlimited
    }
}
1;
