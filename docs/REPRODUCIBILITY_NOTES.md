# Reproducibility and Methodology Notes

This file records important differences between the original working files and the reproducible repository workflow.

## 1. File path and filename

The original R script referenced a machine-specific path and a file named `dataset_phishing_dirty.csv`. The supplied archive contains `dataset_phishing.csv`. The updated script uses the relative path:

```text
data/raw/dataset_phishing.csv
```

## 2. Actual missing values and invalid/sentinel values

The supplied CSV contains no actual `NA` cells. However, it contains:
- 1,837 `domain_age` values less than or equal to zero (including -1, -2, and -12);
- 1,404 `domain_registration_length` values equal to zero.

The updated script treats these values as invalid/sentinel values, converts them to `NA`, and imputes them using medians calculated from the training data only.

## 3. Duplicate records

The supplied CSV contains zero exact duplicate rows. The duplicate check remains in the workflow so that the script can audit a future version of the dataset.

## 4. Class distribution

The supplied dataset is already balanced:
- 5,715 phishing records;
- 5,715 legitimate records.

Therefore, downsampling is not needed for this dataset. The updated script checks the training-set distribution and applies downsampling only if a meaningful imbalance is detected. If used, downsampling is restricted to the training set.

## 5. URL length filter

The original workflow applied the `length_url <= 2000` filter after min-max scaling. That order makes the threshold ineffective because scaled values are between zero and one. The updated script applies the filter before scaling.

The supplied dataset has a maximum URL length of 1,641, so no records are removed by this threshold.

## 6. Data leakage prevention

The original workflow fitted imputation, outlier capping, scaling, and class balancing before splitting the dataset. This can allow information from the testing data to influence training-time preprocessing.

The updated script creates a stratified 70:30 split first. It then:
- calculates numeric medians from training data;
- calculates IQR outlier limits from training data;
- calculates min-max scaling parameters from training data;
- applies those fitted values to the testing data;
- balances the training data only if needed.

## 7. URL identifier

The original `url` column is retained in the raw dataset for traceability, but excluded from the exported training and testing files so it is not accidentally used as a predictor.

## 8. Scope

This repository covers data cleaning, preprocessing, and exploratory data analysis. It does not implement or deploy a final phishing classification model.
