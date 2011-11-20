use VRPipe::Base;

#Example generic command for multi-sample SNP calling
# java -jar GenomeAnalysisTK.jar \
#   -R resources/Homo_sapiens_assembly18.fasta \
#   -T UnifiedGenotyper \
#   -I sample1.bam [-I sample2.bam ...] \
#   --dbsnp dbSNP.vcf \
#   -o snps.raw.vcf \
#   -stand_call_conf [50.0] \
#   -stand_emit_conf 10.0 \
#   -dcov [50] \

class VRPipe::Steps::gatk_genotype extends VRPipe::Steps::gatk {
    around options_definition {
        return { %{$self->$orig},
                 genotyper_opts => VRPipe::StepOption->get(description => 'options for GATK UnifiedGenotyper, excluding -R,-D,-I,-o'),
                 dbsnp_ref => VRPipe::StepOption->get(description => 'absolute path to dbsnp reference file used to populate the vcf ID column', optional => 1, default_value => '/lustre/scratch105/projects/g1k/ref/broad_recal_data/dbsnp_130_b37.rod'),
                 reference_fasta => VRPipe::StepOption->get(description => 'absolute path to reference genome fasta', optional => 1, default_value => '/lustre/scratch105/projects/g1k/ref/main_project/human_g1k_v37.fasta'),
                 max_cmdline_bams => VRPipe::StepOption->get(description => 'max number of bam filenames to allow on command line', optional => 1, default_value => 10),
               };
    }

    method inputs_definition {
        return { bam_files => VRPipe::StepIODefinition->get(type => 'bam', max_files => -1, description => '1 or more bam files to call variants') };
    }

    method body_sub {
        return sub {
            use VRPipe::Utils::gatk;
            
            my $self = shift;
            my $options = $self->options;
            my $gatk = VRPipe::Utils::gatk->new(gatk_path => $options->{gatk_path}, java_exe => $options->{java_exe});
            
            my $reference_fasta = $options->{reference_fasta};
            my $dbsnp_ref = $options->{dbsnp_ref};
            my $genotyper_opts = $options->{genotyper_opts};
            my $max_cmdline_bams = $options->{max_cmdline_bams};
            
            $self->set_cmd_summary(VRPipe::StepCmdSummary->get(exe => 'GenomeAnalysisTK', 
                                  version => $gatk->determine_gatk_version(),
                                 summary => 'java $jvm_args -jar GenomeAnalysisTK.jar -T UnifiedGenotyper -R $reference_fasta -D $dbsnp_ref $genotyper_opts -I $bam_path -o $vcf_path'));
            
            my $req = $self->new_requirements(memory => 1200, time => 1);
            my $jvm_args = $gatk->jvm_args($req->memory);

			if (scalar (@{$self->inputs->{bam_files}}) > $max_cmdline_bams) {
				$self->warn("[todo] Generate a bam fofn");
			}
            
			my $bam_list;
            foreach my $bam (@{$self->inputs->{bam_files}}) {
                my $bam_path = $bam->path;
				$bam_list .= "-I $bam_path ";
            }
			my $vcf_file = $self->output_file(output_key => 'vcf_files', basename => "gatk_var.vcf.gz", type => 'bin');
			my $vcf_path = $vcf_file->path;

			my $cmd = $gatk->java_exe.qq[ $jvm_args -jar ].$gatk->jar.qq[ -T UnifiedGenotyper -R $reference_fasta -D $dbsnp_ref $genotyper_opts $bam_list -o $vcf_path ];
			$self->dispatch([$cmd, $req, {output_files => [$vcf_file]}]); 
        };
    }
    method outputs_definition {
        return { vcf_files => VRPipe::StepIODefinition->get(type => 'bin', max_files => -1, description => 'a .vcf.gz file for each set of input bam files') };
    }
    method post_process_sub {
        return sub { return 1; };
    }
    method description {
        return "Run gatk UnifiedGenotyper for one or more bams, generating one vcf per set of bams";
    }
    method max_simultaneous {
        return 0; # meaning unlimited
    }
}

1;
