# ================================================================
# Web Page Phishing Detection
# Data Quality Audit, Preprocessing and Exploratory Data Analysis
#
# Recommended:
#   Open web-page-phishing-preprocessing-r.Rproj in RStudio.
#   Run: source("R/01_preprocess_and_eda.R")
#
# The workflow uses the original benchmark CSV without modifying it.
# It does not train or deploy a phishing-classification model.
# ================================================================

# 1. Resolve the project root ---------------------------------------

find_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)

  if (length(file_arg) > 0) {
    return(sub("^--file=", "", file_arg[1]))
  }

  frames <- sys.frames()
  if (length(frames) > 0) {
    for (i in rev(seq_along(frames))) {
      candidate <- frames[[i]]$ofile
      if (!is.null(candidate) && length(candidate) == 1) {
        return(candidate)
      }
    }
  }

  return(NULL)
}

script_path <- find_script_path()

if (!is.null(script_path)) {
  project_root <- normalizePath(
    file.path(dirname(script_path), ".."),
    winslash = "/",
    mustWork = TRUE
  )
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

if (!file.exists(file.path(project_root, "web-page-phishing-preprocessing-r.Rproj"))) {
  stop(
    "Project root could not be identified. Open the .Rproj file in RStudio ",
    "or run this script from the repository root."
  )
}

setwd(project_root)

# 2. Check dependencies ---------------------------------------------

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop(
    "The ggplot2 package is required.\n",
    "Install it once with: install.packages(\"ggplot2\")"
  )
}

# 3. Define paths and create output folders -------------------------

data_file <- file.path("data", "raw", "dataset_phishing.csv")
processed_dir <- file.path("data", "processed")
figures_dir <- file.path("outputs", "figures")
tables_dir <- file.path("outputs", "tables")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(data_file)) {
  stop("Dataset not found: ", data_file)
}

# 4. Load and validate the source dataset ---------------------------

raw_df <- utils::read.csv(
  data_file,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  na.strings = c("", "NA"),
  fileEncoding = "UTF-8"
)

required_columns <- c(
  "url", "status", "domain_age", "domain_registration_length",
  "length_url", "length_hostname", "nb_hyperlinks", "web_traffic"
)

missing_columns <- setdiff(required_columns, names(raw_df))

if (length(missing_columns) > 0) {
  stop(
    "Required columns are missing: ",
    paste(missing_columns, collapse = ", ")
  )
}

if (anyNA(raw_df$url) || any(trimws(raw_df$url) == "")) {
  stop("The URL identifier column contains missing or empty values.")
}

raw_df$status <- factor(
  tolower(trimws(as.character(raw_df$status))),
  levels = c("legitimate", "phishing")
)

if (anyNA(raw_df$status)) {
  stop("Unexpected or missing labels found in the status column.")
}

numeric_features <- setdiff(
  names(raw_df)[vapply(raw_df, is.numeric, logical(1))],
  "status"
)

non_numeric_feature_columns <- setdiff(
  setdiff(names(raw_df), c("url", "status")),
  numeric_features
)

if (length(non_numeric_feature_columns) > 0) {
  stop(
    "Unexpected non-numeric feature columns: ",
    paste(non_numeric_feature_columns, collapse = ", ")
  )
}

if (length(numeric_features) == 0) {
  stop("No numeric predictor features were detected.")
}

# 5. Initial data-quality audit -------------------------------------

initial_rows <- nrow(raw_df)
initial_columns <- ncol(raw_df)
initial_missing_cells <- sum(is.na(raw_df))
initial_duplicates <- sum(duplicated(raw_df))

url_frequency <- table(raw_df$url)
repeated_url_groups <- sum(url_frequency > 1)
repeated_url_rows <- sum(url_frequency[url_frequency > 1] - 1)

invalid_domain_age <- sum(raw_df$domain_age <= 0, na.rm = TRUE)
negative_domain_age <- sum(raw_df$domain_age < 0, na.rm = TRUE)
zero_domain_age <- sum(raw_df$domain_age == 0, na.rm = TRUE)

invalid_registration_length <- sum(
  raw_df$domain_registration_length <= 0,
  na.rm = TRUE
)
negative_registration_length <- sum(
  raw_df$domain_registration_length < 0,
  na.rm = TRUE
)
zero_registration_length <- sum(
  raw_df$domain_registration_length == 0,
  na.rm = TRUE
)

long_urls <- sum(raw_df$length_url > 2000, na.rm = TRUE)
url_length_mismatches <- sum(
  raw_df$length_url != nchar(raw_df$url, type = "chars"),
  na.rm = TRUE
)

class_counts <- table(raw_df$status)

raw_zero_variance <- numeric_features[
  vapply(
    raw_df[numeric_features],
    function(x) length(unique(x[!is.na(x)])) <= 1,
    logical(1)
  )
]

audit_metrics <- c(
  "Rows in raw dataset",
  "Columns in raw dataset",
  "Numeric predictor features",
  "Actual missing cells",
  "Exact duplicate rows",
  "Unique URL identifiers",
  "Repeated URL groups",
  "Additional rows from repeated URLs",
  "Non-positive domain_age values",
  "  Negative domain_age values",
  "  Zero domain_age values",
  "Non-positive domain_registration_length values",
  "  Negative domain_registration_length values",
  "  Zero domain_registration_length values",
  "URLs longer than 2000 characters",
  "length_url values inconsistent with URL character count",
  "Zero-variance numeric features in raw dataset",
  "Phishing records",
  "Legitimate records"
)

audit_values <- c(
  initial_rows,
  initial_columns,
  length(numeric_features),
  initial_missing_cells,
  initial_duplicates,
  length(unique(raw_df$url)),
  repeated_url_groups,
  repeated_url_rows,
  invalid_domain_age,
  negative_domain_age,
  zero_domain_age,
  invalid_registration_length,
  negative_registration_length,
  zero_registration_length,
  long_urls,
  url_length_mismatches,
  length(raw_zero_variance),
  unname(class_counts["phishing"]),
  unname(class_counts["legitimate"])
)

raw_audit <- data.frame(
  stage = "raw",
  metric = audit_metrics,
  value = as.character(audit_values),
  stringsAsFactors = FALSE
)

# Feature-level quality audit
feature_quality <- do.call(
  rbind,
  lapply(numeric_features, function(column_name) {
    x <- raw_df[[column_name]]
    non_missing <- x[!is.na(x)]

    data.frame(
      feature = column_name,
      missing_values = sum(is.na(x)),
      unique_values = length(unique(non_missing)),
      zero_variance = length(unique(non_missing)) <= 1,
      minimum = if (length(non_missing) > 0) min(non_missing) else NA_real_,
      maximum = if (length(non_missing) > 0) max(non_missing) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
)

utils::write.csv(
  feature_quality,
  file.path(tables_dir, "feature_quality_audit.csv"),
  row.names = FALSE
)

# 6. Exploratory data analysis ---------------------------------------

class_plot_data <- data.frame(
  status = names(class_counts),
  records = as.numeric(class_counts)
)

p_class <- ggplot2::ggplot(
  class_plot_data,
  ggplot2::aes(x = status, y = records, fill = status)
) +
  ggplot2::geom_col(width = 0.62) +
  ggplot2::geom_text(
    ggplot2::aes(label = format(records, big.mark = ",")),
    vjust = -0.45,
    fontface = "bold",
    size = 4
  ) +
  ggplot2::scale_fill_manual(
    values = c("legitimate" = "#16877A", "phishing" = "#D95F45")
  ) +
  ggplot2::scale_y_continuous(
    expand = ggplot2::expansion(mult = c(0, 0.12))
  ) +
  ggplot2::labs(
    title = "Class Distribution",
    subtitle = "Web page phishing detection benchmark",
    x = "Website status",
    y = "Number of records"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "none")

ggplot2::ggsave(
  file.path(figures_dir, "class_distribution.png"),
  p_class, width = 7, height = 5, dpi = 180
)

p_url_length <- ggplot2::ggplot(
  raw_df,
  ggplot2::aes(x = length_url, colour = status, fill = status)
) +
  ggplot2::geom_density(alpha = 0.18, size = 0.7, na.rm = TRUE) +
  ggplot2::scale_fill_manual(
    values = c("legitimate" = "#16877A", "phishing" = "#D95F45")
  ) +
  ggplot2::scale_colour_manual(
    values = c("legitimate" = "#16877A", "phishing" = "#D95F45")
  ) +
  ggplot2::labs(
    title = "URL Length Distribution",
    subtitle = "Distribution by website status",
    x = "URL length (dataset feature)",
    y = "Density",
    colour = "Status",
    fill = "Status"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  file.path(figures_dir, "url_length_distribution.png"),
  p_url_length, width = 8, height = 5, dpi = 180
)

p_hyperlinks <- ggplot2::ggplot(
  raw_df,
  ggplot2::aes(x = status, y = log1p(nb_hyperlinks), fill = status)
) +
  ggplot2::geom_boxplot(
    width = 0.62,
    alpha = 0.85,
    outlier.alpha = 0.25,
    na.rm = TRUE
  ) +
  ggplot2::scale_fill_manual(
    values = c("legitimate" = "#16877A", "phishing" = "#D95F45")
  ) +
  ggplot2::labs(
    title = "Hyperlink Count by Website Status",
    subtitle = "Vertical axis uses log(1 + hyperlink count) to show skewed values",
    x = "Website status",
    y = "log(1 + hyperlink count)"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "none")

ggplot2::ggsave(
  file.path(figures_dir, "hyperlinks_by_status.png"),
  p_hyperlinks, width = 7, height = 5, dpi = 180
)

quality_plot_data <- data.frame(
  issue = c(
    "Non-positive domain age",
    "Non-positive registration length",
    "Repeated URL rows",
    "URL length inconsistencies"
  ),
  count = c(
    invalid_domain_age,
    invalid_registration_length,
    repeated_url_rows,
    url_length_mismatches
  )
)

p_quality <- ggplot2::ggplot(
  quality_plot_data,
  ggplot2::aes(x = reorder(issue, count), y = count)
) +
  ggplot2::geom_col(fill = "#426A9A", width = 0.68) +
  ggplot2::geom_text(
    ggplot2::aes(label = count),
    hjust = -0.18,
    fontface = "bold",
    size = 3.8
  ) +
  ggplot2::coord_flip() +
  ggplot2::scale_y_continuous(
    expand = ggplot2::expansion(mult = c(0, 0.15))
  ) +
  ggplot2::labs(
    title = "Data Quality Findings",
    subtitle = "Issues identified in the supplied raw CSV",
    x = NULL,
    y = "Number of records"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  file.path(figures_dir, "data_quality_issues.png"),
  p_quality, width = 8, height = 5, dpi = 180
)

# 7. Descriptive statistics -----------------------------------------

descriptive_stats <- do.call(
  rbind,
  lapply(levels(raw_df$status), function(label) {
    group_data <- raw_df[raw_df$status == label, , drop = FALSE]

    data.frame(
      status = label,
      records = nrow(group_data),
      mean_url_length = mean(group_data$length_url, na.rm = TRUE),
      median_url_length = median(group_data$length_url, na.rm = TRUE),
      mean_hyperlinks = mean(group_data$nb_hyperlinks, na.rm = TRUE),
      median_hyperlinks = median(group_data$nb_hyperlinks, na.rm = TRUE),
      mean_web_traffic = mean(group_data$web_traffic, na.rm = TRUE),
      median_web_traffic = median(group_data$web_traffic, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
)

utils::write.csv(
  descriptive_stats,
  file.path(tables_dir, "descriptive_statistics_by_status.csv"),
  row.names = FALSE
)

# 8. Clean exact duplicates and apply URL-length filter --------------

clean_df <- raw_df[!duplicated(raw_df), , drop = FALSE]
rows_after_duplicate_removal <- nrow(clean_df)

clean_df <- clean_df[
  is.na(clean_df$length_url) | clean_df$length_url <= 2000,
  ,
  drop = FALSE
]
rows_after_length_filter <- nrow(clean_df)

if (nrow(clean_df) == 0) {
  stop("No records remain after the initial cleaning steps.")
}

# 9. Validate URL labels and create a stratified URL-grouped split ---

url_label_groups <- split(as.character(clean_df$status), clean_df$url)

url_label_conflicts <- names(url_label_groups)[
  vapply(
    url_label_groups,
    function(x) length(unique(x)) > 1,
    logical(1)
  )
]

if (length(url_label_conflicts) > 0) {
  stop(
    "Some exact URL identifiers have conflicting class labels. ",
    "Resolve these records before splitting."
  )
}

url_groups <- unique(
  data.frame(
    url = clean_df$url,
    status = as.character(clean_df$status),
    stringsAsFactors = FALSE
  )
)

set.seed(42)
train_urls <- character(0)

for (class_label in c("legitimate", "phishing")) {
  class_urls <- unique(url_groups$url[url_groups$status == class_label])

  if (length(class_urls) < 2) {
    stop("Not enough unique URLs in class: ", class_label)
  }

  n_train_urls <- floor(0.70 * length(class_urls))
  selected_urls <- sample(class_urls, size = n_train_urls, replace = FALSE)
  train_urls <- c(train_urls, selected_urls)
}

train_df <- clean_df[clean_df$url %in% train_urls, , drop = FALSE]
test_df <- clean_df[!(clean_df$url %in% train_urls), , drop = FALSE]

if (nrow(train_df) == 0 || nrow(test_df) == 0) {
  stop("The train/test split produced an empty partition.")
}

if (length(intersect(unique(train_df$url), unique(test_df$url))) > 0) {
  stop("Exact URL leakage detected between training and testing partitions.")
}

if (length(unique(train_df$status)) < 2 || length(unique(test_df$status)) < 2) {
  stop("Both classes must be represented in the training and testing partitions.")
}

# 10. Convert invalid duration values to missing ---------------------

train_df$domain_age[train_df$domain_age <= 0] <- NA
test_df$domain_age[test_df$domain_age <= 0] <- NA

train_df$domain_registration_length[
  train_df$domain_registration_length <= 0
] <- NA

test_df$domain_registration_length[
  test_df$domain_registration_length <= 0
] <- NA

# 11. Median imputation fitted on training data only -----------------

model_numeric_features <- setdiff(
  names(train_df)[vapply(train_df, is.numeric, logical(1))],
  "status"
)

training_medians <- vapply(
  model_numeric_features,
  function(column_name) {
    median(train_df[[column_name]], na.rm = TRUE)
  },
  numeric(1)
)

if (any(!is.finite(training_medians))) {
  bad_features <- names(training_medians)[!is.finite(training_medians)]
  stop(
    "No finite training median could be calculated for: ",
    paste(bad_features, collapse = ", ")
  )
}

for (column_name in model_numeric_features) {
  train_missing <- is.na(train_df[[column_name]])
  test_missing <- is.na(test_df[[column_name]])

  if (any(train_missing)) {
    train_df[[column_name]][train_missing] <- training_medians[[column_name]]
  }

  if (any(test_missing)) {
    test_df[[column_name]][test_missing] <- training_medians[[column_name]]
  }
}

imputation_parameters <- data.frame(
  feature = names(training_medians),
  training_median = as.numeric(training_medians),
  stringsAsFactors = FALSE
)

utils::write.csv(
  imputation_parameters,
  file.path(tables_dir, "imputation_parameters.csv"),
  row.names = FALSE
)

# 12. IQR outlier capping fitted on training data only ---------------

outlier_columns <- c(
  "length_url",
  "nb_hyperlinks",
  "web_traffic",
  "domain_age",
  "domain_registration_length"
)

outlier_columns <- intersect(outlier_columns, model_numeric_features)

outlier_bounds <- do.call(
  rbind,
  lapply(outlier_columns, function(column_name) {
    quartiles <- stats::quantile(
      train_df[[column_name]],
      probs = c(0.25, 0.75),
      na.rm = TRUE,
      names = FALSE
    )

    iqr_value <- quartiles[2] - quartiles[1]

    data.frame(
      feature = column_name,
      lower_bound = quartiles[1] - 1.5 * iqr_value,
      upper_bound = quartiles[2] + 1.5 * iqr_value,
      stringsAsFactors = FALSE
    )
  })
)

for (i in seq_len(nrow(outlier_bounds))) {
  column_name <- outlier_bounds$feature[i]
  lower_bound <- outlier_bounds$lower_bound[i]
  upper_bound <- outlier_bounds$upper_bound[i]

  train_df[[column_name]] <- pmin(
    pmax(train_df[[column_name]], lower_bound),
    upper_bound
  )

  test_df[[column_name]] <- pmin(
    pmax(test_df[[column_name]], lower_bound),
    upper_bound
  )
}

utils::write.csv(
  outlier_bounds,
  file.path(tables_dir, "outlier_bounds.csv"),
  row.names = FALSE
)

# 13. Remove zero-variance predictors based on training data --------

candidate_predictors <- setdiff(
  names(train_df)[vapply(train_df, is.numeric, logical(1))],
  "status"
)

zero_variance_features <- candidate_predictors[
  vapply(
    train_df[candidate_predictors],
    function(x) length(unique(x[!is.na(x)])) <= 1,
    logical(1)
  )
]

if (length(zero_variance_features) > 0) {
  train_df <- train_df[
    ,
    setdiff(names(train_df), zero_variance_features),
    drop = FALSE
  ]

  test_df <- test_df[
    ,
    setdiff(names(test_df), zero_variance_features),
    drop = FALSE
  ]
}

utils::write.csv(
  data.frame(feature = zero_variance_features),
  file.path(tables_dir, "removed_zero_variance_features.csv"),
  row.names = FALSE
)

# 14. Min-max scaling fitted on training data only -------------------

scale_columns <- c(
  "length_url",
  "length_hostname",
  "nb_hyperlinks",
  "web_traffic",
  "domain_age",
  "domain_registration_length"
)

scale_columns <- intersect(
  scale_columns,
  setdiff(names(train_df), c("url", "status"))
)

scale_parameters <- do.call(
  rbind,
  lapply(scale_columns, function(column_name) {
    data.frame(
      feature = column_name,
      training_minimum = min(train_df[[column_name]], na.rm = TRUE),
      training_maximum = max(train_df[[column_name]], na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
)

for (i in seq_len(nrow(scale_parameters))) {
  column_name <- scale_parameters$feature[i]
  minimum_value <- scale_parameters$training_minimum[i]
  maximum_value <- scale_parameters$training_maximum[i]

  if (maximum_value == minimum_value) {
    train_df[[column_name]] <- 0
    test_df[[column_name]] <- 0
  } else {
    train_df[[column_name]] <-
      (train_df[[column_name]] - minimum_value) /
      (maximum_value - minimum_value)

    test_df[[column_name]] <-
      (test_df[[column_name]] - minimum_value) /
      (maximum_value - minimum_value)
  }
}

utils::write.csv(
  scale_parameters,
  file.path(tables_dir, "scaling_parameters.csv"),
  row.names = FALSE
)

# 15. Final validation and export ------------------------------------

train_export <- train_df[
  ,
  setdiff(names(train_df), "url"),
  drop = FALSE
]

test_export <- test_df[
  ,
  setdiff(names(test_df), "url"),
  drop = FALSE
]

if (anyNA(train_export) || anyNA(test_export)) {
  stop("Missing values remain after preprocessing.")
}

if (length(intersect(names(train_export), names(test_export))) != ncol(train_export)) {
  stop("Training and testing feature columns do not match.")
}

if (any(!vapply(train_export[vapply(train_export, is.numeric, logical(1))],
                function(x) all(is.finite(x)), logical(1)))) {
  stop("Non-finite numeric values remain in the training export.")
}

if (any(!vapply(test_export[vapply(test_export, is.numeric, logical(1))],
                function(x) all(is.finite(x)), logical(1)))) {
  stop("Non-finite numeric values remain in the testing export.")
}

train_class_counts <- table(train_export$status)
test_class_counts <- table(test_export$status)

final_metrics <- c(
  "Training records",
  "Testing records",
  "Training missing cells",
  "Testing missing cells",
  "Training phishing records",
  "Training legitimate records",
  "Testing phishing records",
  "Testing legitimate records",
  "Exact URL identifiers shared across partitions",
  "Zero-variance predictors removed",
  "Predictor features in final export",
  "Rows removed as exact duplicates",
  "Rows removed by URL-length filter"
)

final_values <- c(
  nrow(train_export),
  nrow(test_export),
  sum(is.na(train_export)),
  sum(is.na(test_export)),
  unname(train_class_counts["phishing"]),
  unname(train_class_counts["legitimate"]),
  unname(test_class_counts["phishing"]),
  unname(test_class_counts["legitimate"]),
  length(intersect(unique(train_df$url), unique(test_df$url))),
  length(zero_variance_features),
  length(setdiff(names(train_export), "status")),
  initial_rows - rows_after_duplicate_removal,
  rows_after_duplicate_removal - rows_after_length_filter
)

final_audit <- data.frame(
  stage = "final",
  metric = final_metrics,
  value = as.character(final_values),
  stringsAsFactors = FALSE
)

utils::write.csv(
  rbind(raw_audit, final_audit),
  file.path(tables_dir, "data_quality_audit.csv"),
  row.names = FALSE
)

utils::write.csv(
  train_export,
  file.path(processed_dir, "train_data.csv"),
  row.names = FALSE
)

utils::write.csv(
  test_export,
  file.path(processed_dir, "test_data.csv"),
  row.names = FALSE
)

# 16. Save a concise run summary -------------------------------------

run_summary <- c(
  "Preprocessing completed successfully.",
  paste("Project root:", project_root),
  paste("Raw records:", initial_rows),
  paste("Raw numeric features:", length(numeric_features)),
  paste("Training records:", nrow(train_export)),
  paste("Testing records:", nrow(test_export)),
  paste("Zero-variance predictors removed:", length(zero_variance_features)),
  "Exact URL identifiers shared across train/test: 0",
  "The URL identifier is excluded from the exported predictor datasets.",
  "No model was trained."
)

writeLines(
  run_summary,
  con = file.path(tables_dir, "run_summary.txt")
)

cat(paste(run_summary, collapse = "\n"), "\n")
cat("Figures:", figures_dir, "\n")
cat("Tables:", tables_dir, "\n")
cat("Processed datasets:", processed_dir, "\n")
