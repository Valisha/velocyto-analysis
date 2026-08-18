# RNA velocity from IGSC experiment 1 FASTQs

This workflow reuses the established Irene Exp2 alevin-fry pipeline for the 12 IGSC Exp1 samples across lanes L005-L008:
`E2 E3 E4 E6 M1 M2 N1 N2 N3 P4 P5 P6`.

The reproduced settings are:

- Salmon 1.10.3 with `mm10-2.1.0_splici_fl146_idx`.
- Paired-end Chromium mapping with library type `ISR` and Salmon `--sketch` mode.
- alevin-fry 0.11.2, forward orientation, knee-based permit list, and collation.
- `splici_fl146_t2g_3col.tsv`, `cr-like` resolution, and Matrix Market output.
- USA mode, retaining unspliced, spliced, and ambiguous molecule assignments.

The final stage loads each USA matrix with pyroe's velocity representation, combines cells with unique `SAMPLE:BARCODE` identifiers, fits the scVelo dynamical model, and calculates a velocity graph and latent time.

## Reference and configuration

The reused reference is configured independently of the repository location:

```text
/data/vashah/CELLRANGER_PIPELINE/Input_data_to_pipeline/velocyto_pipeline/
├── mm10-2.1.0_splici_fl146_idx/
└── mm10_2.1.0_splici_fl146/
    └── splici_fl146_t2g_3col.tsv
```

If it is moved, export `REFERENCE_ROOT=/new/reference/parent` before validation. Review [config/config.env](config/config.env), particularly `PROJECT_DIR`, `FASTQ_DIR`, and reference paths. The previous Pool2 metadata is not needed at runtime because its confirmed settings are encoded directly in the mapping and quantification scripts.

Add the true experimental conditions, biological replicates, and timepoints to [config/samples.tsv](config/samples.tsv). They are deliberately blank because sample names alone do not establish developmental direction.

## Software

Activate the same Salmon 1.10.3 and alevin-fry 0.11.2 environment used for Irene Exp2. The validator warns if different versions are found. For the analysis environment:

```bash
python -m venv rna-velocity-env
source rna-velocity-env/bin/activate
pip install -r requirements.txt
```

## Validate and run

From the repository root on `implk-01`:

```bash
chmod +x scripts/*.sh scripts/*.py
./scripts/00_validate_inputs.sh
```

`implk-01` does not expose SLURM. Start its scheduler-free runner in the background so the analysis survives an SSH disconnect:

```bash
mkdir -p logs
nohup ./scripts/submit_pipeline.sh > logs/pipeline_local.log 2>&1 &
echo $!
tail -f logs/pipeline_local.log
```

The launcher detects whether `sbatch` exists. Without it, samples run sequentially using 16 threads each; completed mapping and quantification outputs are skipped safely when resuming. With SLURM, it submits dependency-linked arrays. Both modes run three stages:

1. `01_salmon_alevin_map.sbatch`: four-lane Salmon/alevin mapping per sample.
2. `02_alevin_fry_quant.sbatch`: permit-list generation, collation, and USA quantification.
3. `03_scvelo.sbatch`: combined dynamical RNA-velocity and trajectory analysis.

A downstream stage starts only after the preceding stage succeeds. On a SLURM system, monitor with:

```bash
squeue -u "$USER"
tail -f logs/salmon_map_JOB_TASK.out
```

Existing sample output directories are never overwritten. Remove or rename a failed partial directory manually only after inspecting its log.

## Biological annotations and trajectory root

Set these optional fields in `config/config.env` to use a curated h5ad and a justified starting population:

```text
ANNOTATION_H5AD="/path/to/curated_annotation.h5ad"
PLOT_COLOR="cell_type"
ROOT_KEY="cell_type"
ROOT_CLUSTER="Progenitor"
```

Annotation cell IDs must use `SAMPLE:BARCODE`, such as `E2:AAAC...-1`. Without a supplied root, scVelo estimates root and terminal states from the velocity transition matrix. Treat that as exploratory inference rather than independent proof of lineage direction.

## Outputs

- `${QUANT_ROOT}/IGSC_Exp1_SAMPLE_map/map.rad`: mapping output.
- `${QUANT_ROOT}/IGSC_Exp1_SAMPLE_quant_res/`: USA spliced/unspliced/ambiguous matrices.
- `${ANALYSIS_ROOT}/rna_velocity.h5ad`: combined fitted model.
- `${ANALYSIS_ROOT}/velocity_stream_umap.png`: velocity stream.
- `${ANALYSIS_ROOT}/latent_time_umap.png`: inferred dynamical progression.
- `${ANALYSIS_ROOT}/splicing_proportions.png`: splicing-count QC.
- `${ANALYSIS_ROOT}/run_summary.json`: cell/gene counts and root definition.
