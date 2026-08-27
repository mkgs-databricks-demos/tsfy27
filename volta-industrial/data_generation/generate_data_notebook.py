# Databricks notebook source
# DBTITLE 1,Overview
# MAGIC %md
# MAGIC # Volta Industrial — Downtime & Maintenance Rescue · Synthetic Data Generator
# MAGIC
# MAGIC Produces the raw datasets for the Volta demo under `<catalog>.<schema>` using Spark
# MAGIC (Databricks Connect serverless when run locally, the runtime's `spark` when run as a
# MAGIC job). Follows the `databricks-synthetic-data-gen` skill: `spark.range` + `F.when` +
# MAGIC broadcast joins + Window + `F.element_at` — no driver loops, no `.collect()` on big tables.
# MAGIC
# MAGIC **The load-bearing anomaly** (one driver, two visible symptoms): a high-utilization run
# MAGIC ~3 weeks ago wore a cluster of production lines toward failure — rising vibration/temperature
# MAGIC telemetry + open corrective work orders + parts that would need expediting — while the rest of
# MAGIC the fleet runs to plan. The hero is `LINE-04` at `PLANT-03` (Ohio, failure risk ~0.87, part not
# MAGIC local); the maintenance play the heuristic ranks first is **pull_now**. See `specifications/01-lakeflow.md`.
# MAGIC
# MAGIC **This is a worked example of the technique, not a fill-in-the-blanks template.** This script
# MAGIC writes the RAW parquet datasets only; silver + gold are the SDP pipeline's job.