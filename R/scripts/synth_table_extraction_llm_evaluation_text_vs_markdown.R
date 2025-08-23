library(tidyverse)
source("report_misc/helper_functions.R")

#### synth table confidence qwen3 235 b ####

df_synth_table_extraction <- readRDS("data_storage/synth_table_extraction_llm.rds") %>%
  # sample_frac(size = .05) %>% 
  filter(!model %in% c("deepseek-ai_DeepSeek-R1-Distill-Qwen-32B", 'google_gemma-3n-E4B-it')) %>% 
  mutate(
    model = gsub("^[^_]+_", "", model)
  )

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors_synth_table_extraction.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  )
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml") | str_ends(filename, "vllm_batched.yaml")))

df_synth_table_extraction <- df_synth_table_extraction %>% left_join(
  norm_factors_few_examples %>% mutate(model_name = gsub("^[^_]+_", "", model_name)) %>% select(model_name, parameter_count, normalization_factor),
  by = c("model" = "model_name")
) %>% mutate(
  normalized_runtime = normalization_factor * runtime
)

confidence_vs_truth_synth_by_format <- df_synth_table_extraction %>% 
  mutate(model = if_else(model == "Qwen3-235B-A22B-Instruct-2507", "Qwen3-235B-A22B-Instruct-2507-FP8", model)) %>% 
  # filter(method_family %in% c("top_n_rag_examples", "n_random_examples")) %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Qwen3-8B", "Qwen3-235B-A22B-Instruct-2507-FP8")) %>% 
  group_by(method, model, loop) %>% mutate(
    mean_percentage_correct_total = mean(percentage_correct_total, na.rm=TRUE), .before = 1,
    respect_units = !ignore_units
  ) %>% group_by(respect_units, model, filepath, input_format) %>% 
  # arrange(desc(mean_percentage_correct_total)) %>% 
  slice_max(mean_percentage_correct_total, n = 1, with_ties = FALSE) %>% 
  mutate(predictions_processed = map(predictions, ~{
    .x %>% 
      select(-"_merge") %>% 
      mutate(
        match = (year_truth == year_result) | (is.na(year_truth) & is.na(year_result)),
        confidence = confidence_this_year,
        truth_NA = is.na(year_truth),
        predicted_NA = is.na(year_result),
        .before = 4
      ) %>% nest(
        tuple_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% 
      mutate(
        confidence = confidence_previous_year,
        match = (previous_year_truth == previous_year_result) | (is.na(previous_year_truth) & is.na(previous_year_result)),
        truth_NA = is.na(previous_year_truth),
        predicted_NA = is.na(previous_year_result),
        .before = 4
      ) %>% nest(
        tuple_previous_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% select(
        -c(year_truth, previous_year_truth, year_result, previous_year_result,
           confidence_this_year, confidence_previous_year)
      ) %>% 
      pivot_longer(-c("E1", "E2", "E3")) %>% 
      unnest(cols = value) %>% mutate(
        match = if_else(is.na(match), FALSE, match)
      )
  })) %>% 
  unnest(predictions_processed) %>% mutate(
    match = factor(match, levels = c(F, T)),
    truth_NA = factor(truth_NA, levels = c(F, T))
  )

confidence_intervals_synth_by_format <- confidence_vs_truth_synth_by_format %>% #rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.025
  ) %>%
  group_by(conf_center, predicted_NA, model, respect_units, input_format) %>%
  summarise(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    chance_zero = chance_false == 0,
    chance_below_1 = chance_false < 1,
    chance_low = if_else(chance_zero, 0, if_else(chance_below_1, 1, 2)),
    chance_low = factor(chance_low, levels = c(0,1,2), labels = c("equls 0 %", "below 1 %", "more"))
  ) %>% group_by(predicted_NA, model, respect_units, input_format) %>% mutate(
    perc = total/sum(total)*100
  ) %>% ungroup() %>% 
  mutate(
    chance_false_interval = cut(
      chance_false,
      breaks = c(0, 1, 2, 4, 8, 16, 32, 64, Inf),
      labels = c("[0,1)", "[1,2)", "[2,4)", "[4,8)", 
                 "[8,16)", "[16,32)", "[32,64)", "[64,Inf)"),
      right = FALSE,
      ordered_result = TRUE
    ),
  )

confidence_intervals_synth_by_format %>%
  ggplot() +
  geom_col(aes(
    x = conf_center, y = perc, 
    color = chance_low, 
    fill = chance_false_interval
  ), alpha = 1) +
  # geom_text(
  #   aes(x = conf_center, y = perc, label = round(perc, 0)), 
  #   position = position_stack(vjust = 1), vjust = -0.6, 
  #   size = 3, color = "black"
  # ) +
  scale_color_manual(values = c("equls 0 %" = "#00CC00", "below 1 %" = "orange", "more" = "#555555")) +
  scale_fill_manual(values = rev(c("#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#e6f598", "#abdda4", "#66c2a5", "#3288bd")), drop = FALSE) +
  labs(
    x = "Confidence Interval Center", 
    y = "Percentage of predictions", 
    color = "mistake rate") +
  coord_cartesian(
    ylim = c(0, 100), 
    xlim = c(0,1)
  ) +
  facet_nested(paste("respect units:", respect_units)+paste("predicted NA:", predicted_NA) ~ model+input_format)

confidence_intervals_synth_by_format %>% saveRDS("data_storage/confidence_intervals_synth_by_format.rds")

confidence_vs_truth_synth <- df_synth_table_extraction %>% 
  mutate(model = if_else(model == "Qwen3-235B-A22B-Instruct-2507", "Qwen3-235B-A22B-Instruct-2507-FP8", model)) %>% 
  # filter(method_family %in% c("top_n_rag_examples", "n_random_examples")) %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Qwen3-8B", "Qwen3-235B-A22B-Instruct-2507-FP8")) %>% 
  group_by(method, model, loop) %>% mutate(
    mean_percentage_correct_total = mean(percentage_correct_total, na.rm=TRUE), .before = 1,
    respect_units = !ignore_units
  ) %>% group_by(respect_units, model, filepath) %>% 
  # arrange(desc(mean_percentage_correct_total)) %>% 
  slice_max(mean_percentage_correct_total, n = 1, with_ties = FALSE) %>% 
  mutate(predictions_processed = map(predictions, ~{
    .x %>% 
      select(-"_merge") %>% 
      mutate(
        match = (year_truth == year_result) | (is.na(year_truth) & is.na(year_result)),
        confidence = confidence_this_year,
        truth_NA = is.na(year_truth),
        predicted_NA = is.na(year_result),
        .before = 4
      ) %>% nest(
        tuple_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% 
      mutate(
        confidence = confidence_previous_year,
        match = (previous_year_truth == previous_year_result) | (is.na(previous_year_truth) & is.na(previous_year_result)),
        truth_NA = is.na(previous_year_truth),
        predicted_NA = is.na(previous_year_result),
        .before = 4
      ) %>% nest(
        tuple_previous_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% select(
        -c(year_truth, previous_year_truth, year_result, previous_year_result,
           confidence_this_year, confidence_previous_year)
      ) %>% 
      pivot_longer(-c("E1", "E2", "E3")) %>% 
      unnest(cols = value) %>% mutate(
        match = if_else(is.na(match), FALSE, match)
      )
  })) %>% 
  unnest(predictions_processed) %>% mutate(
    match = factor(match, levels = c(F, T)),
    truth_NA = factor(truth_NA, levels = c(F, T))
  )

confidence_intervals_synth <- confidence_vs_truth_synth %>% #rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.025
  ) %>%
  group_by(conf_center, predicted_NA, model, respect_units) %>%
  summarise(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    chance_zero = chance_false == 0,
    chance_below_1 = chance_false < 1,
    chance_low = if_else(chance_zero, 0, if_else(chance_below_1, 1, 2)),
    chance_low = factor(chance_low, levels = c(0,1,2), labels = c("equls 0 %", "below 1 %", "more"))
  ) %>% group_by(predicted_NA, model, respect_units) %>% mutate(
    perc = total/sum(total)*100
  ) %>% ungroup() %>% 
  mutate(
    chance_false_interval = cut(
      chance_false,
      breaks = c(0, 1, 2, 4, 8, 16, 32, 64, Inf),
      labels = c("[0,1)", "[1,2)", "[2,4)", "[4,8)", 
                 "[8,16)", "[16,32)", "[32,64)", "[64,Inf)"),
      right = FALSE,
      ordered_result = TRUE
    ),
  )

confidence_intervals_synth %>% saveRDS("data_storage/confidence_intervals_synth.rds")

#### old ####

df  <- readRDS("data_storage/synth_table_extraction_llm.rds")

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  ) # %>% filter(str_detect(filename, "multi"))
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml") | str_ends(filename, "vllm_batched.yaml")))
# norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
#   add_column(n_examples = list(c(7,9,11,13), c(5))) %>% unnest(n_examples)

#### h2o final modeling ####

library(shapviz)
library(h2o)

# h2o.shutdown()
h2o.init(max_mem_size = "16G")

results <- readRDS("data_storage/synth_table_extraction_h2o_results_sample_100_shap_100.rds")

results$perc_numeric$shap_values$rf %>% sv_importance(show_numbers = TRUE)
results$perc_numeric$shap_values$rf %>% sv_importance(kind = "beeswarm")
results$perc_numeric$shap_values$rf %>% sv_dependence("method_family")
# results$perc_numeric$shap_values$rf %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

##### percentage_correct_total #####

sample_size <- 1000

df2 <- df %>% filter(n_examples <= 5) %>% 
  left_join(
    norm_factors_few_examples %>% select(model_name, parameter_count), 
    by = c("model" = "model_name")
    ) %>% mutate(
      log10_unit_multiplier = log10(unit_multiplier),
      respect_units = !ignore_units,
      n_columns = as.character(n_columns)
    ) %>% sample_n(sample_size)

# just use basic contrats, the missing columns will have value 0 and are not missing when summing up
# contr.none <- function(n, levels = NULL, ...) {
#   if (is.null(levels)) {
#     if (is.character(n)) {
#       levels <- n
#       n <- length(n)
#     } else {
#       levels <- as.character(seq_len(n))
#     }
#   }
#   mat <- diag(n)
#   colnames(mat) <- levels
#   rownames(mat) <- levels
#   mat
# }
# options(contrasts = c("contr.none", "contr.none"))

formula_perc_numeric_pdf = percentage_correct_total ~
  method_family +
  n_examples +
  model_family +
  parameter_count +
  n_columns +
  n_columns:input_format +
  sum_same_line +
  sum_same_line:input_format +
  header_span +
  header_span:input_format +
  header_span:respect_units +
  thin +
  respect_units +
  respect_units:input_format +
  input_format +
  year_as +
  unit_in_first_cell +
  unit_in_first_cell:input_format +
  log10_unit_multiplier +
  log10_unit_multiplier:input_format +
  enumeration +
  shuffle_rows +
  text_around +
  many_line_breaks +
  many_line_breaks:input_format

# df_modeling_perc_numeric_pdf <- df2 %>% 
#   # filter(input_format == "pdf") %>% 
#   model.matrix(
#     data = ., object = formula_perc_numeric_pdf,
#     contrasts.arg = list(
#       input_format = "contr.none", n_columns = "contr.none", 
#       method_family = "contr.none", model_family = "contr.none"
#       )
#     ) %>% 
#   as_tibble() %>% select(-any_of("(Intercept)")) %>% mutate(
#     target = df2$percentage_correct_total, .before = 1
#   )

df_modeling_perc_numeric_pdf <- df2 %>% select(all.vars(formula_perc_numeric_pdf)) %>% 
  mutate(across(where(is.character), as.factor))

df_modeling_perc_numeric_pdf %>% colnames()

df_modeling_perc_numeric_pdf.h2o <- as.h2o(df_modeling_perc_numeric_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_perc_numeric_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_perc_numeric_pdf)[-1]

# Linear model
fit_lm_perc_numeric <- h2o.glm(x = xvars, y = colnames(df_modeling_perc_numeric_pdf)[1], training_frame = train, validation_frame = test)
# fit_lm_perc_numeric_ia <- h2o.glm(
#   x = xvars, y = colnames(df_modeling_perc_numeric_pdf)[1], training_frame = train, validation_frame = test,
#   interaction_pairs = list(
#     c('input_format', 'n_columns'), c('input_format', 'sum_same_line'), 
#     c('input_format', 'log10_unit_multiplier'), 
#     c('input_format', 'respect_units')
#   ))

shap_test_sample <- test # sample_n(as_tibble(test), size = 100)
# shap_test_sample <- sample_n(as_tibble(test), size = 1000)

# aggregate_shap_values <- list(
#   method_family = c("method_familystatic_example", "method_familytop_n_rag_examples_out_of_sample", "method_familyzero_shot"),
#   n_columns = c("n_columns4", "n_columns5"),
#   input_format = c("input_formatmarkdown", "input_formatpdf"),
#   model_family = c("model_familyLlama.3", "model_familyLlama.4", "model_familymistralai", "model_familyQwen.2.5", "model_familyQwen.3")
# )
# 
# collapse_shap(
#   shp_lm_perc_numeric$S,
#   aggregate_shap_values
#   ) %>% abs() %>% colMeans()

shp_lm_perc_numeric <- shapviz(
  fit_lm_perc_numeric, X_pred = shap_test_sample, background_frame = train
  )

# lm_test <- lm(data = bind_cols(
#   shp$S %>% as_tibble() %>%  mutate(type1 = "importance") %>% 
#     pivot_longer(cols = -type1, names_to = "colname1", values_to = "importance"),
#   shp$X %>% as_tibble() %>%  mutate(type2 = "value") %>%
#     pivot_longer(cols = -type2, names_to = "colname2", values_to = "value")
# ) %>% filter(colname1 == "input_formatpdf.log10_unit_multiplier"), importance ~ value)
# lm_test$coefficients["value"]

# sv_force(shp_lm_perc_numeric, row_id = 1)
sv_dependence(shp_lm_perc_numeric, xvars)
sv_importance(shp_lm_perc_numeric, show_numbers = TRUE)
sv_importance(shp_lm_perc_numeric, kind = "beeswarm")
# sv_importance(shp_lm_perc_numeric, kind = "no")

shp_lm_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))


# Evaluate metrics on test set
# pred_lm <- as.vector(h2o.predict(fit_lm, test))
# true_lm <- as.vector(test[1])
# rmse_lm <- sqrt(mean((pred_lm - true_lm)^2))
# cat("Linear Model RMSE on test set:", rmse_lm, "\n")

# Random forest
fit_rf_perc_numeric <- h2o.randomForest(x = xvars, y = colnames(df_modeling_perc_numeric_pdf)[1], training_frame = train, validation_frame = test)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

shp_rf_perc_numeric <- shapviz(fit_rf_perc_numeric, X_pred = shap_test_sample)
# sv_force(shp_rf_perc_numeric, row_id = 1)
# sv_dependence(shp_rf_perc_numeric, xvars)
# sv_importance(shp_rf_perc_numeric, show_numbers = TRUE)
sv_importance(shp_rf_perc_numeric, kind = "beeswarm")

shp_rf_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))


# Evaluate metrics on test set
# pred_rf <- as.vector(h2o.predict(fit_rf, test))
# true_rf <- as.vector(test$Sepal.Length)
# rmse_rf <- sqrt(mean((pred_rf - true_rf)^2))
# cat("Random Forest RMSE on test set:", rmse_rf, "\n")

# H2O XGBoost model

# Train H2O XGBoost model
fit_xgb_h2o_perc_numeric <- h2o.xgboost(
  x = xvars,
  y = colnames(df_modeling_perc_numeric_pdf)[1],
  training_frame = train,
  validation_frame = test,
  ntrees = 500,
  max_depth = 8,
  learn_rate = 0.01,
  seed = 42
)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

# SHAP values with shapviz
shp_xgb_perc_numeric <- shapviz(fit_xgb_h2o_perc_numeric, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_xgb_perc_numeric, row_id = 1)
# sv_dependence(shp_xgb, xvars)
sv_importance(shp_xgb_perc_numeric, show_numbers = TRUE)
sv_importance(shp_xgb_perc_numeric, kind = "beeswarm")

shp_xgb_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

# Evaluate metrics on test set
# pred_xgb <- as.vector(h2o.predict(fit_xgb_h2o, test_h2o))
# true_xgb <- as.vector(test_h2o$percentage_correct_total)
# rmse_xgb <- sqrt(mean((pred_xgb - true_xgb)^2))
# cat("H2O XGBoost RMSE on test set:", rmse_xgb, "\n")

##### F1 NA ######

df2 <- df %>% filter(n_examples <= 5) %>% 
  filter(!is.na(NA_F1)) %>% 
  left_join(
    norm_factors_few_examples %>% select(model_name, parameter_count), 
    by = c("model" = "model_name")
  ) %>% mutate(
    log10_unit_multiplier = log10(unit_multiplier),
    respect_units = !ignore_units,
    n_columns = factor(n_columns)
  ) %>% sample_n(sample_size)

formula_NA_F1_pdf = NA_F1 ~ 
  method_family +
  n_examples +
  model_family +
  parameter_count +
  n_columns +
  n_columns:input_format +
  sum_same_line +
  sum_same_line:input_format +
  header_span +
  header_span:input_format +
  header_span:respect_units +
  # thin +
  respect_units +
  respect_units:input_format +
  input_format +
  year_as +
  unit_in_first_cell +
  unit_in_first_cell:input_format +
  log10_unit_multiplier +
  log10_unit_multiplier:input_format +
  enumeration +
  shuffle_rows +
  text_around +
  many_line_breaks +
  many_line_breaks:input_format

df_modeling_NA_F1_pdf <- df2 %>% 
  # filter(input_format == "pdf") %>% 
  model.matrix(data = ., object = formula_NA_F1_pdf) %>% 
  as_tibble() %>% select(-"(Intercept)") %>% mutate(
    target = df2$NA_F1, .before = 1
  )

library(shapviz)
library(h2o)

# h2o.shutdown()
h2o.init()

df_modeling_NA_F1_pdf.h2o <- as.h2o(df_modeling_NA_F1_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_NA_F1_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_NA_F1_pdf)[-1]

# Linear model
fit_lm_NA_F1 <- h2o.glm(x = xvars, y = colnames(df_modeling_NA_F1_pdf)[1], training_frame = train, validation_frame = test)

shap_test_sample <- test # sample_n(as_tibble(test), size = 100)

shp_lm_NA_F1 <- shapviz(fit_lm_NA_F1, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_lm, row_id = 1)
# sv_dependence(shp_lm, xvars)
# sv_importance(shp_lm, show_numbers = TRUE)
sv_importance(shp_lm_NA_F1, kind = "beeswarm")

shp_lm_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

# Random forest
fit_rf_NA_F1 <- h2o.randomForest(x = xvars, y = colnames(df_modeling_NA_F1_pdf)[1], training_frame = train, validation_frame = test)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

shp_rf <- shapviz(fit_rf_NA_F1, X_pred = shap_test_sample)
# sv_force(shp_rf, row_id = 1)
# sv_dependence(shp_rf, xvars)
# sv_importance(shp_rf, show_numbers = TRUE)
sv_importance(shp_rf_NA_F1, kind = "beeswarm")

shp_rf_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

# H2O XGBoost model

# Train H2O XGBoost model
fit_xgb_h2o_NA_F1 <- h2o.xgboost(
  x = xvars,
  y = colnames(df_modeling_NA_F1_pdf)[1],
  training_frame = train,
  validation_frame = test,
  ntrees = 500,
  max_depth = 8,
  learn_rate = 0.01,
  seed = 42
)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

# SHAP values with shapviz
shp_xgb_NA_F1 <- shapviz(fit_xgb_h2o_NA_F1, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_xgb, row_id = 1)
# sv_dependence(shp_xgb, xvars)
# sv_importance(shp_xgb, show_numbers = TRUE)
sv_importance(shp_xgb_NA_F1, kind = "beeswarm")

shp_xgb_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

##### confidence #####

df2 <- df %>% filter(n_examples <= 5) %>% 
  # filter(model_family = "mistral") %>% 
  left_join(
    norm_factors_few_examples %>% select(model_name, parameter_count), 
    by = c("model" = "model_name")
  ) %>% mutate(
    log10_unit_multiplier = log10(unit_multiplier),
    respect_units = !ignore_units,
    n_columns = factor(n_columns)
  ) %>% unnest(predictions) %>% 
  sample_n(2*sample_size) %>% pivot_longer(
    cols = starts_with("confidence"), 
    values_to = "confidence", 
    names_to = "year", names_prefix = "confidence_"
  ) %>% filter(
    !is.na(confidence)
  ) %>% 
  sample_n(sample_size)

formula_confidence_pdf = confidence ~ 
  method_family +
  n_examples +
  model_family +
  parameter_count +
  n_columns +
  n_columns:input_format +
  sum_same_line +
  sum_same_line:input_format +
  header_span +
  header_span:input_format +
  header_span:respect_units +
  # thin +
  respect_units +
  respect_units:input_format +
  input_format +
  year_as +
  unit_in_first_cell +
  unit_in_first_cell:input_format +
  log10_unit_multiplier +
  log10_unit_multiplier:input_format +
  enumeration +
  shuffle_rows +
  text_around +
  many_line_breaks +
  many_line_breaks:input_format

df_modeling_confidence_pdf <- df2 %>% 
  # filter(input_format == "pdf") %>% 
  model.matrix(data = ., object = formula_confidence_pdf) %>% 
  as_tibble() %>% select(-"(Intercept)") %>% mutate(
    target = df2$confidence, .before = 1
  )

# library(shapviz)
# library(h2o)
# 
# # h2o.shutdown()
# h2o.init()

df_modeling_confidence_pdf.h2o <- as.h2o(df_modeling_confidence_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_confidence_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_confidence_pdf)[-1]

# Linear model
fit_lm_confidence <- h2o.glm(x = xvars, y = colnames(df_modeling_confidence_pdf)[1], training_frame = train, validation_frame = test)

shap_test_sample <- test # sample_n(as_tibble(test), size = 100)

shp_lm_confidence <- shapviz(fit_lm_confidence, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_lm, row_id = 1)
# sv_dependence(shp_lm, xvars)
# sv_importance(shp_lm, show_numbers = TRUE)
sv_importance(shp_lm_confidence, kind = "beeswarm")

shp_lm_confidence %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

# Random forest
fit_rf_confidence <- h2o.randomForest(x = xvars, y = colnames(df_modeling_confidence_pdf)[1], training_frame = train, validation_frame = test)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

shp_rf_confidence <- shapviz(fit_rf_confidence, X_pred = shap_test_sample)
# sv_force(shp_rf, row_id = 1)
# sv_dependence(shp_rf, xvars)
# sv_importance(shp_rf, show_numbers = TRUE)
sv_importance(shp_rf_confidence, kind = "beeswarm")

shp_rf_confidence %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

# H2O XGBoost model

# Train H2O XGBoost model
fit_xgb_h2o_confidence <- h2o.xgboost(
  x = xvars,
  y = colnames(df_modeling_confidence_pdf)[1],
  training_frame = train,
  validation_frame = test,
  ntrees = 500,
  max_depth = 8,
  learn_rate = 0.01,
  seed = 42
)

shap_test_sample <- test #sample_n(as_tibble(test), size = 100)

# SHAP values with shapviz
shp_xgb_confidence <- shapviz(fit_xgb_h2o_confidence, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_xgb, row_id = 1)
# sv_dependence(shp_xgb, xvars)
# sv_importance(shp_xgb, show_numbers = TRUE)
sv_importance(shp_xgb_confidence, kind = "beeswarm")

shp_xgb_confidence %>% plot_shap_importance_signed(max_label_length = 30) +
  coord_cartesian(xlim = c(0, 0.15))

##### export #####

list(
  shp_lm_perc_numeric, shp_rf_perc_numeric, shp_xgb_perc_numeric,
  shp_xgb_NA_F1, shp_xgb_NA_F1, shp_xgb_NA_F1,
  shp_lm_confidence, shp_rf_confidence, shp_xgb_confidence
) %>% saveRDS("data_storage/synth_table_extraction_h2o_results.rds")

#### old stuff ####

# # with NAs
# extract_wrong_values <- function(df) {
#   df %>% mutate(
#     mistake_year = (year_truth != year_result) | (is.na(year_truth) & !is.na(year_result)) | (is.na(year_result) & !is.na(year_truth)),
#     mistake_year = if_else(is.na(mistake_year), FALSE, mistake_year),
#     mistake_previous_year =(previous_year_truth != previous_year_result) | (is.na(previous_year_truth) & !is.na(previous_year_result)) | (is.na(previous_year_result) & !is.na(previous_year_truth)),
#     mistake_previous_year = if_else(is.na(mistake_previous_year), FALSE, mistake_previous_year)
#   ) %>% select(
#     year_truth, year_result, 
#     previous_year_truth, previous_year_result,
#     mistake_year, mistake_previous_year
#   ) %>% 
#     filter(mistake_year | mistake_previous_year)  
# }
# 
# # only floats
# extract_wrong_floats <- function(df) {
#   df %>% mutate(
#     mistake_year = (year_truth != year_result),
#     mistake_previous_year =(previous_year_truth != previous_year_result)
#   ) %>% select(
#     year_truth, year_result, 
#     previous_year_truth, previous_year_result,
#     mistake_year, mistake_previous_year
#   ) %>% 
#     filter(mistake_year | mistake_previous_year)
# }
# 
# relative_float_diff <- df %>% 
#   mutate(wrong_floats = map(predictions, extract_wrong_floats)) %>%
#   select(filepath, wrong_floats, model, method) %>% 
#   rowwise() %>% mutate(n_wrong_floats = nrow(wrong_floats)) %>% 
#   filter(n_wrong_floats>0) %>% 
#   unnest(wrong_floats) %>% 
#   mutate(
#     ratio_this_year = year_result/year_truth,
#     ratio_previous_year = previous_year_result/previous_year_truth
#   ) %>% pivot_longer(
#     cols = c(ratio_this_year, ratio_previous_year),
#     names_to = "year_type",
#     values_to = "ratio",
#     names_prefix = "ratio_"
#   ) %>% unique()

#### modeling #####
###### regression ######

probit <- function(x) {
  exp(x)/(exp(x)+1)
}

logit <- function(x) {
  log((x+10^(-6))/(1-x+10^(-6)))
}

df_select <- df2 %>% mutate(
  log10_unit_multiplier = log10(unit_multiplier),
  # logit_correct_total = percentage_correct_total %>% logit()
) %>% select(
  percentage_correct_total,
  # logit_correct_total,
  method_family,
  n_examples,
  # model,
  parameter_count,
  model_family,
  n_columns, 
  sum_same_line,
  header_span,
  thin,
  ignore_units,
  input_format,
  year_as,
  unit_in_first_cell,
  # unit_str,
  # unit_multiplier,
  log10_unit_multiplier,
  
  enumeration,
  shuffle_rows,
  text_around,
  many_line_breaks
)

x <- df_select %>% select(-percentage_correct_total)

# df %>% filter(grammar_error == TRUE)
df %>% group_by(sum_same_line) %>% summarise(n = n())

lm0 <- lm(
  data = df_select,
  formula = percentage_correct_total ~ 
    method_family +
    n_examples +
    # model +
    n_columns +
    sum_same_line +
    header_span +
    thin +
    ignore_units +
    input_format +
    year_as +
    unit_in_first_cell +
    # unit_str +
    # unit_multiplier +
    log10_unit_multiplier +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks
)
summary(lm0)

lm1 <- lm(
  data = df_select,
  formula = percentage_correct_total ~ 
    method_family +
    n_examples +
    model_family +
    parameter_count +
    n_columns +
    n_columns:input_format +
    sum_same_line +
    sum_same_line:input_format +
    header_span +
    header_span:input_format +
    thin +
    ignore_units +
    ignore_units:input_format +
    input_format +
    year_as +
    unit_in_first_cell +
    unit_in_first_cell:input_format +
    # unit_str +
    log10_unit_multiplier +
    log10_unit_multiplier:input_format +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks +
    many_line_breaks:input_format
)
summary(lm1)
# sqrt(mean(lm1$residuals^2))

library(lm.beta)

lm.beta(lm1)

pfun <- function(object, newdata) {
  # browser()
  predict(object, data = newdata)
}

# pfun(lm1, x)

backward <- step(lm1, direction = "backward", trace = 0)

library(vip)

# Extract VI scores
(vi_backward <- vi(backward))

# Plot VI scores; by default, `vip()` displays the top ten features
pal <- palette.colors(2, palette = "Okabe-Ito")  # colorblind friendly palette
vip(
    vi_backward, num_features = length(coef(backward)),  # Figure 3
    # geom = "point", horizontal = FALSE, 
    mapping = aes(fill = Sign)
  ) +
  scale_color_manual(values = unname(pal)) +
  theme_light() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# Load required packages
library(earth)

# Fit a MARS model
mars <- earth(formula = percentage_correct_total ~ 
                method_family +
                n_examples +
                # model +
                n_columns +
                n_columns:input_format +
                sum_same_line +
                sum_same_line:input_format +
                header_span +
                header_span:input_format +
                thin +
                ignore_units +
                ignore_units:input_format +
                input_format +
                year_as +
                unit_in_first_cell +
                unit_in_first_cell:input_format +
                # unit_str +
                log10_unit_multiplier +
                log10_unit_multiplier:input_format +
                enumeration +
                shuffle_rows +
                text_around +
                many_line_breaks +
                many_line_breaks:input_format,
              data = df_select, degree = 1, pmethod = "exhaustive")

# Extract VI scores
vi(mars, type = "gcv")

# Plot VI scores (Figure 4)
vip(mars)

###### Random Forest ######

library(ranger)

# number of features
n_features <- 16+2

# train a default random forest model
forest0 <- ranger(
  percentage_correct_total ~ 
    method_family +
    n_examples +
    model_family +
    # model +
    parameter_count +
    n_columns + 
    sum_same_line +
    header_span +
    thin +
    ignore_units +
    input_format +
    year_as +
    unit_in_first_cell +
    unit_str +
    unit_multiplier +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks,
  data = df2,
  mtry = floor(n_features / 3),
  respect.unordered.factors = "order",
  seed = 123,
  importance = "permutation"
)

# get OOB RMSE
(default_rmse <- sqrt(forest0$prediction.error))

vip::vip(forest0, num_features = 25, bar = FALSE)

library(fastshap)
model <- forest0

# Prediction wrapper
pfun <- function(object, newdata) {
  predict(object, data = newdata)$predictions
}

# Compute fast (approximate) Shapley values using 10 Monte Carlo repetitions
system.time({  # estimate run time
  set.seed(5038)
  shap <- fastshap::explain(model, X = x, pred_wrapper = pfun, nsim = 10)
})

# Load required packages
library(ggplot2)
# theme_set(theme_bw())

# Aggregate Shapley values
shap_imp <- data.frame(
  Variable = names(shap),
  Importance = apply(shap, MARGIN = 2, FUN = function(x) sum(abs(x)))
)

# Plot Shap-based variable importance
ggplot(shap_imp, aes(reorder(Variable, Importance), Importance)) +
  geom_col() +
  coord_flip() +
  xlab("") +
  ylab("mean(|Shapley value|)")


# # train a default random forest model
# forest1 <- ranger(
#   percentage_correct_total ~ 
#     method_family +
#     n_examples +
#     # model +
#     n_columns +
#     n_columns:input_format +
#     sum_same_line +
#     sum_same_line:input_format +
#     header_span +
#     header_span:input_format +
#     thin +
#     ignore_units +
#     ignore_units:input_format +
#     input_format +
#     year_as +
#     unit_in_first_cell +
#     unit_in_first_cell:input_format +
#     # unit_str +
#     unit_multiplier +
#     unit_multiplier:input_format +
#     enumeration +
#     shuffle_rows +
#     text_around +
#     many_line_breaks +
#     many_line_breaks:input_format,
#   data = df,
#   mtry = floor(n_features / 3),
#   respect.unordered.factors = "order",
#   seed = 123
# )

###### xgboost ######

library(xgboost)
# library(caret)
library(caTools)

set.seed(42)
sample_split <- sample.split(Y = df_select$percentage_correct_total, SplitRatio = 0.7)
train_set <- subset(x = df_select, sample_split == TRUE)
test_set <- subset(x = df_select, sample_split == FALSE)

y_train <- train_set$percentage_correct_total
y_test <- test_set$percentage_correct_total
X_train <- train_set %>% select(-percentage_correct_total)
X_test <- test_set %>% select(-percentage_correct_total)

xgb_train <- xgb.DMatrix(data = as.matrix(X_train), label = y_train)
xgb_test <- xgb.DMatrix(data = as.matrix(X_test), label = y_test)
xgb_params <- list(
  booster = "gbtree",
  eta = 0.01,
  max_depth = 8,
  gamma = 4,
  subsample = 0.75,
  colsample_bytree = 1,
  # objective = "multi:softprob",
  # eval_metric = "mlogloss",
  eval_metric = "rmse"
  # num_class = length(levels(iris$Species))
)

xgb_model <- xgb.train(
  params = xgb_params,
  data = xgb_train,
  nrounds = 5000,
  verbose = 1
)
xgb_model

importance_matrix <- xgb.importance(
  feature_names = colnames(xgb_train), 
  model = xgb_model
)
importance_matrix

xgb.plot.importance(importance_matrix)

#### Plotting #####

df2 %>% 
  # mutate(n_col_T_EUR = T_EUR_both + T_EUR) %>% 
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  filter(
    ignore_units,
    input_format == "html"
    ) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=model_family, y = percentage_correct_total), alpha = 1) +
  # geom_jitter(
  #   data = . %>% filter(n_col_T_EUR > 0), 
  #   aes(x = 1, group=ignore_units, color = factor(n_col_T_EUR), y = percentage_correct_total), 
  #   height = 0, alpha = .5, width = 0.3
  # ) +
  # scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~.)

df2 %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total, ignore_units, input_format)) %>% 
  pivot_longer(cols = -c(model, method, ignore_units, input_format)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=ignore_units, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name+input_format)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1, ignore_units)) %>% 
  pivot_longer(cols = -c(model, method, ignore_units)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=ignore_units, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
  facet_grid(method~1)

relative_float_diff %>%
  filter(ratio != 1) %>%
  mutate(
    log_ratio = log(ratio, base = 10),
    log_ratio_is_int = (log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
  ) %>%
  ggplot() +
  geom_histogram(aes(x = log_ratio, fill = log_ratio_is_int), binwidth = 1) +
  facet_grid(paste0(year_type,"\n", model)~method)

#### Old synth ####


json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/synth_tables",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

json_files_table_extraction_llm_markdown <- list.files(
  "../benchmark_results/table_extraction/llm/synth_tables_markdown",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

json_files_table_extraction_llm <- c(json_files_table_extraction_llm, json_files_table_extraction_llm_markdown)

meta_list_llm <- list()

skip_files <- c('Qwen_Qwen2.5-7B-Instruct_vllm__benchmark_table_template_filling__temperature_1.0__zero_shot__loop_0_queued.json')

# Loop through each .json file
for (file in json_files_table_extraction_llm) {
  # print(file)
  if (file %in% skip_files) {
    next
  }
  # Read the JSON file
  # Read the JSON file and replace NaN with NULL in the file content
  file_content <- readLines(file, warn = FALSE)
  file_content <- gsub("\\bNaN\\b", "null", file_content)
  file_content <- gsub("\\bInfinity\\b", "null", file_content)
  # Remove incomplete last JSON entry and close the list if file ends early
  if (!grepl("\\]$", file_content[length(file_content)])) {
    # Find the last complete JSON object (ends with "},")
    last_complete <- max(grep('\\.pdf', file_content))
    file_content <- c(file_content[1:last_complete], "}]")
  }
  json_data <- fromJSON(paste(file_content, collapse = "\n"))

  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)

  results <-  json_data %>% as_tibble() %>% rowwise() %>%
    mutate(
      model = name_split[1],
      method = name_split[method_index],
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      markdown = str_detect(file, "synth_tables_markdown"),
      .before = 1
    )
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>%
  filter(grammar_error != TRUE || is.na(grammar_error)) %>%
  unnest_wider(`NA`, names_sep = "_") %>%
  unnest_wider(`relative_numeric_difference`, names_sep = "_") %>%
  unnest_wider(`levenstein_distance`, names_sep = "_") %>%
  # rename_with(~ gsub("^NA_", "NA_", .x)) %>%  # Ensures prefix is NA_
  mutate(
    NA_total_truth = NA_true_positive + NA_false_negative,
    NA_precision = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_positive), NA),
    NA_recall = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_negative), NA),
    NA_F1 = if_else((NA_precision + NA_recall) > 0, (2 * NA_precision * NA_recall)/(NA_precision + NA_recall), 0),
    percentage_correct_numeric = correct_numeric/(correct_numeric + incorrect_numeric),
    percentage_correct_total = (correct_numeric + NA_true_positive)/total_entries
  )

df <- df %>% rowwise() %>% mutate(
  n_columns = str_match(filepath, "(.)_columns")[2],
  span = if_else("True" == str_match(filepath, "span_(False|True)")[2], TRUE, FALSE),
  thin = if_else("True" == str_match(filepath, "thin_(False|True)")[2], TRUE, FALSE),
  year_as = str_match(filepath, "year_as_(.*)_unit")[2],
  unit_in_first_cell = if_else("True" == str_match(filepath, "unit_in_first_cell_(False|True)")[2], TRUE, FALSE),
  unit_str = str_match(filepath, "unit_in_first_cell_(False|True)_(.*)_enumeration")[3],
  enumeration = if_else("True" == str_match(filepath, "enumeration_(False|True)")[2], TRUE, FALSE),
  number_of_table = str_match(filepath, "enumeration_(False|True)_(.*)(_queued)?\\.pdf")[3]
) %>% mutate(model_md = str_c(model, if_else(markdown, "_markdown", ""))) %>% mutate(
  n_columns = ordered(n_columns, c("3", "4", "5"))
) # %>% filter(number_of_table %in% c("0", "1"))

##### plotting #####

df %>% select(c(model_md, method, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -c(model_md, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model_md, y = value)) +
  facet_grid(method~name) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df %>% select(c(model_md, method, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model_md, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model_md, y = value)) +
  facet_grid(method~name) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df %>% ggplot() +
  geom_boxplot(aes(x = model_md, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model_md, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model_md, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model_md, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30))  + # also between number and null?
  facet_grid(method~1)

