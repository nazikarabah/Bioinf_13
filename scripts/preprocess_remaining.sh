#!/bin/bash -l
#SBATCH --job-name=g13_preprocess
#SBATCH --partition=cpu
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --array=0-4%2
#SBATCH --output=preprocess/batch/logs/%A_%a.log

set -euo pipefail
cd /scratch/grp/msc_appbio/RNAseq_Group13

samples=(ERR4553381 ERR4553382 ERR4553383 ERR4553389 ERR4553391)
sample="${samples[$SLURM_ARRAY_TASK_ID]}"
out="preprocess/batch/$sample"
mkdir -p "$out/faqcs" "$out/fastqc"

echo "Processing $sample"
module load py-cutadapt/4.7
cutadapt -j "$SLURM_CPUS_PER_TASK" \
  -a AGATCGGAAGAGCACACGTCTGAACTCCAGTCA \
  -o "$out/$sample.cutadapt.fastq.gz" \
  "raw_fastq/$sample.fastq.gz" > "$out/cutadapt.log" 2>&1

if ! "$HOME/group13-tools/bin/micromamba" run \
  -r "$HOME/group13-tools/mamba" -n faqcs_208 \
  FaQCs -t "$SLURM_CPUS_PER_TASK" -q 20 --min_L 30 -n 3 \
  -u "$out/$sample.cutadapt.fastq.gz" -d "$out/faqcs" \
  > "$out/faqcs.log" 2>&1; then
  if ! grep -qF 'libgfortran.so.3: cannot open shared object file' "$out/faqcs.log"; then
    cat "$out/faqcs.log" >&2
    exit 1
  fi
  echo "FaQCs PDF plotting failed. Checking the FASTQ and read counts."
fi

clean_fastq="$out/faqcs/QC.unpaired.trimmed.fastq"
test -s "$clean_fastq"

module load fastqc/0.12.1
fastqc -t 1 -o "$out/fastqc" "$clean_fastq"

expected=$(awk '/^After Trimming/{after=1} after && /^Reads #:/ {print $3; exit}' "$out/faqcs/QC.stats.txt")
actual=$(unzip -p "$out/fastqc/QC.unpaired.trimmed_fastqc.zip" '*/fastqc_data.txt' |
  awk -F '\t' '$1=="Total Sequences" {print $2}')

if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "Read count mismatch for $sample. FaQCs=$expected FastQC=$actual" >&2
  exit 1
fi

echo "VERIFIED $sample: $actual reads"
