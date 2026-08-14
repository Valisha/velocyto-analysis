#!/usr/bin/env python3
"""Combine alevin-fry USA matrices and perform scVelo trajectory analysis."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import anndata as ad
import matplotlib.pyplot as plt
import pandas as pd
import scanpy as sc
import scvelo as scv
from pyroe import load_fry


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--quant-root", required=True, type=Path)
    p.add_argument("--output-prefix", required=True)
    p.add_argument("--samples", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--annotation", type=Path, help="Optional h5ad with matching cell IDs and curated annotations")
    p.add_argument("--color", default="condition", help="obs column used in plots")
    p.add_argument("--root-cell", help="Exact combined cell ID to use as the trajectory root")
    p.add_argument("--root-cluster", help="Value in --root-key marking the biological starting population")
    p.add_argument("--root-key", default="cell_type", help="obs column containing --root-cluster")
    p.add_argument("--n-top-genes", type=int, default=3000)
    p.add_argument("--n-pcs", type=int, default=30)
    p.add_argument("--n-neighbors", type=int, default=30)
    p.add_argument("--seed", type=int, default=0)
    return p.parse_args()


def locate_quant(root: Path, prefix: str, sample: str) -> Path:
    result = root / f"{prefix}_{sample}_quant_res"
    required = [result / "quant.json", result / "alevin" / "quants_mat.mtx"]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError(f"Incomplete alevin-fry output for {sample}: {', '.join(missing)}")
    return result


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    metadata = pd.read_csv(args.samples, sep="\t", dtype=str).fillna("")
    if metadata["sample"].duplicated().any():
        raise ValueError("Sample names must be unique")

    datasets = []
    for row in metadata.to_dict("records"):
        sample = row["sample"]
        quant_dir = locate_quant(args.quant_root, args.output_prefix, sample)
        x = load_fry(str(quant_dir), output_format="velocity", quiet=False)
        required_layers = {"spliced", "unspliced"}
        if not required_layers.issubset(x.layers):
            raise RuntimeError(
                f"{sample} lacks velocity layers; found {sorted(x.layers.keys())}"
            )
        x.var_names_make_unique()
        # Standardize to SAMPLE:BARCODE so identifiers remain unique after merging.
        x.obs_names = [f"{sample}:{name.split(':')[-1]}" for name in x.obs_names]
        for key, value in row.items():
            x.obs[key] = value
        datasets.append(x)
    adata = ad.concat(datasets, join="inner", merge="same", index_unique=None)
    if not adata.obs_names.is_unique:
        raise ValueError("Combined cell identifiers are not unique")

    if args.annotation:
        annotated = sc.read_h5ad(args.annotation)
        overlap = adata.obs_names.intersection(annotated.obs_names)
        if not len(overlap):
            raise ValueError("Annotation h5ad has no cell IDs matching SAMPLE:BARCODE IDs")
        adata = adata[overlap].copy()
        for col in annotated.obs.columns:
            adata.obs[col] = annotated.obs.loc[overlap, col].values

    scv.pp.filter_and_normalize(adata, min_shared_counts=20, n_top_genes=args.n_top_genes)
    sc.tl.pca(adata, n_comps=args.n_pcs, random_state=args.seed)
    sc.pp.neighbors(adata, n_neighbors=args.n_neighbors, n_pcs=args.n_pcs, random_state=args.seed)
    sc.tl.umap(adata, random_state=args.seed)
    if "leiden" not in adata.obs:
        sc.tl.leiden(adata, key_added="leiden", random_state=args.seed)
    scv.pp.moments(adata, n_pcs=args.n_pcs, n_neighbors=args.n_neighbors)
    scv.tl.recover_dynamics(adata, n_jobs=8)
    scv.tl.velocity(adata, mode="dynamical")
    scv.tl.velocity_graph(adata, n_jobs=8)
    scv.tl.velocity_confidence(adata)
    scv.tl.terminal_states(adata)

    latent_root_key = None
    root_description = "velocity-inferred root_cells"
    if args.root_cell:
        if args.root_cell not in adata.obs_names:
            raise ValueError(f"Root cell not found: {args.root_cell}")
        adata.obs["user_root"] = 0.0
        adata.obs.loc[args.root_cell, "user_root"] = 1.0
        latent_root_key = "user_root"
        root_description = args.root_cell
    elif args.root_cluster:
        if args.root_key not in adata.obs:
            raise ValueError(f"Root key not in obs: {args.root_key}")
        root_mask = adata.obs[args.root_key].astype(str) == args.root_cluster
        candidates = adata.obs_names[root_mask]
        if len(candidates) == 0:
            raise ValueError(f"No cells match {args.root_key}={args.root_cluster}")
        adata.obs["user_root"] = root_mask.astype(float)
        latent_root_key = "user_root"
        root_description = f"{args.root_key}={args.root_cluster} ({len(candidates)} cells)"

    scv.tl.latent_time(adata, root_key=latent_root_key)
    adata.write_h5ad(args.output / "rna_velocity.h5ad", compression="gzip")

    color = args.color if args.color in adata.obs else "leiden"
    adata.obs[color] = adata.obs[color].astype("category")
    scv.pl.velocity_embedding_stream(adata, basis="umap", color=color, legend_loc="right margin", show=False)
    plt.savefig(args.output / "velocity_stream_umap.png", dpi=300, bbox_inches="tight")
    plt.close()
    scv.pl.scatter(adata, basis="umap", color="latent_time", color_map="gnuplot", show=False)
    plt.savefig(args.output / "latent_time_umap.png", dpi=300, bbox_inches="tight")
    plt.close()
    scv.pl.proportions(adata, groupby=color, show=False)
    plt.savefig(args.output / "splicing_proportions.png", dpi=300, bbox_inches="tight")
    plt.close()

    summary = {
        "n_cells": int(adata.n_obs),
        "n_genes": int(adata.n_vars),
        "samples": metadata["sample"].tolist(),
        "plot_color": color,
        "root_definition": root_description,
    }
    (args.output / "run_summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
