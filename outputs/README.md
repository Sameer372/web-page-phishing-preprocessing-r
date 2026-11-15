# Outputs

The repository includes pre-generated exploratory figures and raw-data audit tables so the project
can be reviewed directly on GitHub.

Run `source("R/01_preprocess_and_eda.R")` from the project in RStudio to regenerate the figures,
tables, preprocessing parameters, run summary, and local processed train/test CSV files.

Generated train/test CSV files are excluded from Git by `.gitignore` because they can be
reproduced from the included raw dataset and R script.
