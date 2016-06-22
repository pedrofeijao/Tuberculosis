#!/bin/bash
# Shell script for calling SNPs on a single sample using BCF tools and GATK
# Author: Fang Zhang
# Date: 2016.4.5
# E-mail: fza34@sfu.ca

# $var1 = directory of destination folder
# $var2 = path to  reference file
# $var3 = name of refrence fasta file
# $var4 = name of sample
# $var5 = directory of fastq files of sample
# $var6 = path to risistant SNPs gzip vcf file
# fatsq files are assumed to be names $5/$4_1.fastq and $5/$4_2.fastq

# Load tools  ----------------------------------------
module load samtools/1.3
module load bcftools/1.3
module load java/1.7.0_67
export PERL5LIB=/global/software/vcftools/vcftools_0.1.12b/perl:$PERL5LIB
export PATH=/global/software/htslib/htslib121/bin:$PATH
export PATH=/global/software/vcftools/vcftools_0.1.12b/bin:$PATH

# Reading parameters  ----------------------------------------
destination=${1}    # Main directory of the experiment
reference_path=${2} # Path to directory of original reference file
reference_name=${3} # Name of reference fasta file
reference_fasta=${reference_path}/${reference_name}.fasta # Path to original reference fasta file
sample_name=${4}    # Name of analyzed sample
sample_path_to_fastq=${5}  # Path to sample fatsq files
resi_snp_vcf=${6}
sample_fastq1_gz=${sample_path_to_fastq}/${sample_name}_1.fastq.gz
sample_fastq2_gz=${sample_path_to_fastq}/${sample_name}_2.fastq.gz
sample_fastq1=${sample_path_to_fastq}/${sample_name}_1.fastq
sample_fastq2=${sample_path_to_fastq}/${sample_name}_2.fastq
gunzip -c ${sample_fastq1_gz} > ${sample_fastq1}
gunzip -c ${sample_fastq2_gz} > ${sample_fastq2}

max_coverage=2000 # Max coverage to call SNPs

# Creating directories ----------------------------------------
mkdir -p ${destination} # Make directory of the experiment

results_folder=${destination}"/results" # Path to directory of results
mkdir -p ${results_folder} # Make directory of results
dir_sample=${results_folder}"/"${sample_name} # Path to directory of sample's results 
rm -r ${dir_sample} # Remove directory of sample's results 
mkdir -p ${dir_sample} # Make directory of sample's results
sample_path_prefix=${dir_sample}"/"${sample_name} # Prefix of result files

norm_reference_fasta_folder=${dir_sample}"/reference" # Path to directory of reference files
rm -r ${norm_reference_fasta_folder} # Remove folder of reference files
mkdir -p ${norm_reference_fasta_folder} # Make directory of reference files
norm_reference_fasta=${norm_reference_fasta_folder}"/reference.fasta" # Directory of normilized reference fasta file
reference_dic=${norm_reference_fasta_folder}"/reference.dict" # Directory of dic file of reference

dir_statistics=${dir_sample}"/statistics" # Path to directory of statistics
mkdir -p ${dir_statistics} # Make directory of statistics

# comparison_folder="./"${destination}"/comparison" # Path to directory of comparison
# mkdir -p ${comparison_folder} # Make directory of comparison
# sample_in_comparison=${comparison_folder}"/"${sample_name} # Path to directory of sample in comparison 
# rm -r ${sample_in_comparison} # Remove directory of sample in comparison 
# mkdir -p ${sample_in_comparison} # Make directory of sample in comparison 
# sample_in_comparison_prefix=${sample_in_comparison}"/"${sample_name} # Prefix of files in sample in comparison

# Indexing reference genome  ----------------------------------------
# Normalizing reference file
java -jar /global/software/picard/picard157/picard-tools-1.57/NormalizeFasta.jar I=${reference_fasta} O=${norm_reference_fasta}
# Generating dict file
java -jar /global/software/picard/picard157/picard-tools-1.57/CreateSequenceDictionary.jar R=${norm_reference_fasta} O=${reference_dic}
# Indexing reference file
/global/software/bwa/bwa075a/bin/bwa index ${norm_reference_fasta}
# Generating fai file
samtools faidx ${norm_reference_fasta}
echo "********** Indexing reference genome finished *************"

# Mapping fastq files onto reference genome  ----------------------------------------
# Mapping -T minimum score to output
/global/software/bwa/bwa075a/bin/bwa mem -T 50 -t 4 -R '@RG\tID:foo\tSM:bar\tLB:library1' ${norm_reference_fasta} ${sample_fastq1} ${sample_fastq2} \
	| samtools import ${norm_reference_fasta}.fai - - \
	| samtools sort -@4 -m5G - -o ${sample_path_prefix}.bam
# samtools view -bF 256 -q 1 ${sample_path_prefix}.bam > ${sample_path_prefix}_dedup.bam
# mv ${sample_path_prefix}_dedup.bam ${sample_path_prefix}.bam
# Indexing bam file
samtools index ${sample_path_prefix}.bam
echo "********** Mapping finished *************"

# Calculating DoC  ----------------------------------------
java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T DepthOfCoverage -R ${norm_reference_fasta} -o ${dir_statistics}/${sample_name} -I ${sample_path_prefix}.bam 
DoC=`sed -n 2p ${dir_statistics}/${sample_name}.sample_summary | awk '{print $3}'`
DoC_min=$(echo "$DoC*0.025"|bc)
echo "********** Calculating DoC finished *************"

# Calling SNPs using BCF tools  ----------------------------------------
# -m minimum read depth, -L maximum read depth, -u generate uncompressed VCF/BCF output, -g generate genotype likelihoods in BCF format -f faidx indexed reference sequence file
samtools mpileup -m ${DoC_min} -L ${max_coverage} -ugf ${norm_reference_fasta} -o ${sample_path_prefix}_mpileup.bcf ${sample_path_prefix}.bam 
bcftools call -V indels -vcO v -o ${sample_path_prefix}_mpileup.vcf ${sample_path_prefix}_mpileup.bcf
cat ${sample_path_prefix}_mpileup.vcf | vcf-convert -r ${norm_reference_fasta} -v 4.1 > ${sample_path_prefix}_mpileup1.vcf
mv ${sample_path_prefix}_mpileup1.vcf ${sample_path_prefix}_mpileup.vcf
echo "********** Calling SNPs using BCF finished *************"

# Calling SNPs using GATK  ----------------------------------------
# Generating sample_gatk.vcf
java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T UnifiedGenotyper -R ${norm_reference_fasta} -I ${sample_path_prefix}.bam -o ${sample_path_prefix}_gatk.vcf -ploidy 1
echo "********** Calling SNPs using GATK finished *************"

# Calling intersection  ----------------------------------------
# Preprocessing for comparison
bgzip -c ${sample_path_prefix}_gatk.vcf > ${sample_path_prefix}_gatk.vcf.gz
bgzip -c ${sample_path_prefix}_mpileup.vcf > ${sample_path_prefix}_mpileup.vcf.gz 
tabix -p vcf ${sample_path_prefix}_gatk.vcf.gz
tabix -p vcf ${sample_path_prefix}_mpileup.vcf.gz

# intersection and subtractions of sample by using vcf-isec
vcf-isec -o -n +2 ${sample_path_prefix}_gatk.vcf.gz ${sample_path_prefix}_mpileup.vcf.gz > ${sample_path_prefix}_intersect.vcf

# Calling resistant SNPs   ----------------------------------------
bgzip -c ${sample_path_prefix}_intersect.vcf > ${sample_path_prefix}_intersect.vcf.gz
tabix -p vcf ${sample_path_prefix}_intersect.vcf.gz
vcf-isec -o -n +2 ${sample_path_prefix}_intersect.vcf.gz ${6} > ${sample_path_prefix}_resi.vcf

# Calling intersection  ----------------------------------------
# intersection and subtractions of sample by using gatk
# java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T CombineVariants --genotypemergeoption UNIQUIFY -R ${norm_reference_fasta} -V ${sample_path_prefix}_gatk.vcf -V ${sample_path_prefix}_mpileup.vcf -o ${sample_path_prefix}_union.vcf

# java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T SelectVariants -select 'set == "Intersection"' -R ${norm_reference_fasta} -V ${sample_path_prefix}_union.vcf -o ${sample_path_prefix}_intersect.vcf

# java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T SelectVariants -select 'set == "variant"' -R ${norm_reference_fasta} -V ${sample_path_prefix}_union.vcf -o ${sample_path_prefix}_gatk_unique.vcf

# java -jar /global/software/gatk/gatk322/GenomeAnalysisTK.jar -T SelectVariants -select 'set == "variant1"' -R ${norm_reference_fasta} -V ${sample_path_prefix}_union.vcf -o ${sample_path_prefix}_mpileup_unique.vcf
# echo "********** Calling SNPs intersections finished *************"

# remove files  ----------------------------------------
rm ${sample_fastq1}
rm ${sample_fastq2}
rm ${sample_path_prefix}_mpileup.bcf
rm ${sample_path_prefix}.bam
rm -rf ${dir_statistics}
rm -rf ${norm_reference_fasta_folder}
echo "********** Removing files finished *************"

# Comparing the two sets of called SNPs  ----------------------------------------
# Preprocessing for comparison
# bgzip -c ${sample_path_prefix}_gatk.vcf > ${sample_path_prefix}_gatk.vcf.gz
# bgzip -c ${sample_path_prefix}_mpileup.vcf > ${sample_path_prefix}_mpileup.vcf.gz 
# tabix -p vcf ${sample_path_prefix}_gatk.vcf.gz
# tabix -p vcf ${sample_path_prefix}_mpileup.vcf.gz
# Comparison of gatk.vcf and mpileup.vcf
# vcf-compare ${sample_path_prefix}_mpileup.vcf.gz ${sample_path_prefix}_gatk.vcf.gz > ${sample_in_comparison_prefix}_mpileup_gatk_comparison.txt
# bcftools stats -F ${norm_reference_fasta} ${sample_path_prefix}_gatk.vcf.gz ${sample_path_prefix}_mpileup.vcf.gz > ${sample_in_comparison_prefix}_gatk_mpileup.vchk
# Plotting the comparison result
# plot-vcfstats -p ${comparison_folder}/${sample_name}/plots/ ${sample_in_comparison_prefix}_gatk_mpileup.vchk
# Plotting histograms of variant depth 
# python vcf-plot.py ${sample_path_prefix}_gatk.vcf ${sample_in_comparison}/plots/${sample_name}_gatk.jpg
# python vcf-plot.py ${sample_path_prefix}_mpileup.vcf ${sample_in_comparison}/plots/${sample_name}_mpileup.jpg
