start_time <- Sys.time()

library(tidyverse)
source("report_misc/helper_functions.R")

# units_real_tables <- read_csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% mutate(
#   filepath = paste0('/pvc/benchmark_truth/real_tables/', company, '__', filename),
#   T_EUR = (T_in_year + T_in_previous_year)>0,
#   T_EUR_both = (T_in_year + T_in_previous_year)>1
# ) %>% select(filepath, T_EUR, T_EUR_both)

#### Final ####

df <- readRDS("data_storage/table_extraction_regex.rds") %>% filter(
  table_type == "real_tables"
)

##### regression #####

table_characteristics <- read.csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% 
  mutate(
    filepath = paste0("../../benchmark_truth/real_tables/", company, "__", filename) %>% str_replace(".pdf", ".xlsx")
  ) %>% as_tibble()

# norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
#   mutate(
#     model_name = model_name %>% str_replace("/", "_")
#   ) %>% filter(str_detect(filename, "multi"))
# norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml")))
# norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
#   add_column(n_examples = list(c(7,9,11,13), c(5))) %>% unnest(n_examples)

df_characteristics <- df %>% 
#   rowwise() %>% mutate(
#   mean_tokens = mean(request_tokens[[1]])
# ) %>% 
  # select(
  #   filepath, 
  #   method_family, model_family, 
  #   percentage_correct_total, 
  #   n_examples, 
  #   model, method,
  #   mean_tokens
  # ) %>% 
  left_join(table_characteristics, by = "filepath") %>% ungroup()

# df_characteristics <- df_characteristics %>% filter(n_examples <= 5) %>% 
#   left_join(
#     norm_factors_few_examples %>% select(model_name, parameter_count), 
#     by = c("model" = "model_name")
#   ) %>% mutate(
#     respect_units = !ignore_units,
#   )

#### h2o final modelin ####

##### percentage_correct_total #####

library(shapviz)
library(h2o)

# h2o.shutdown()
h2o.init(max_mem_size = "8G", port = 54326)

sample_size <- 50000
test_sample_size <- 2000
# sample_size <- 100
# test_sample_size <- 100
print(paste(sample_size, test_sample_size))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_minutes <- floor(as.numeric(runtime) / 60)
remaining_seconds <- as.numeric(runtime) %% 60
cat("\033[1;32mRuntime after init:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

df2 <- df_characteristics %>% slice_sample(n = sample_size)

formula_perc_numeric_pdf = percentage_correct_total ~
  # method_family +
  # n_examples +
  # model_family +
  extraction_backend +
  # parameter_count +
  n_columns +
  # n_columns:input_format +
  sum_same_line +
  # sum_same_line:input_format +
  header_span +
  # header_span:input_format +
  # header_span:respect_units +
  # thin +
  # respect_units +
  # respect_units:input_format +
  # input_format +
  # year_as +
  # unit_in_first_cell +
  # unit_in_first_cell:input_format +
  # log10_unit_multiplier +
  # log10_unit_multiplier:input_format +
  enumeration +
  # shuffle_rows +
  # text_around +
  # many_line_breaks +
  # many_line_breaks:input_format
  T_in_previous_year + 
  T_in_year + 
  passiva_same_page +
  # spacer +
  vorjahr +
  vis_seperated_cols +
  vis_seperated_rows

df_modeling_perc_numeric_pdf <- df2 %>% select(all.vars(formula_perc_numeric_pdf)) %>% 
  mutate(across(where(is.character), as.factor))

# df_modeling_perc_numeric_pdf <- df2 %>% 
#   # filter(input_format == "pdf") %>% 
#   model.matrix(data = ., object = formula_perc_numeric_pdf) %>% 
#   as_tibble() %>% select(-"(Intercept)") %>% 
#   mutate(
#     target = df2$percentage_correct_total, .before = 1
#   )

df_modeling_perc_numeric_pdf.h2o <- as.h2o(df_modeling_perc_numeric_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_perc_numeric_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_perc_numeric_pdf)[-1]

# Linear model
fit_lm_perc_numeric <- h2o.glm(x = xvars, y = colnames(df_modeling_perc_numeric_pdf)[1], training_frame = train, validation_frame = test,
                               compute_p_values = TRUE, remove_collinear_columns = TRUE)

# shap_test_sample <- test # sample_n(as_tibble(test), size = 100)
shap_test_sample <- as.h2o(test %>% as_tibble() %>% slice_sample(n = test_sample_size))

shp_lm_perc_numeric <- shapviz(
  fit_lm_perc_numeric, X_pred = shap_test_sample, background_frame = train, #collapse = aggregate_shap_values, X = as_tibble(test)[,-1]
  )

# lm_test <- lm(data = bind_cols(
#   shp$S %>% as_tibble() %>%  mutate(type1 = "importance") %>% 
#     pivot_longer(cols = -type1, names_to = "colname1", values_to = "importance"),
#   shp$X %>% as_tibble() %>%  mutate(type2 = "value") %>%
#     pivot_longer(cols = -type2, names_to = "colname2", values_to = "value")
# ) %>% filter(colname1 == "input_formatpdf.log10_unit_multiplier"), importance ~ value)
# lm_test$coefficients["value"]

# sv_force(shp_lm_perc_numeric, row_id = 1)
# sv_dependence(shp_lm_perc_numeric, xvars)
# sv_importance(shp_lm_perc_numeric, show_numbers = TRUE)
sv_importance(shp_lm_perc_numeric, kind = "beeswarm")

# shp_lm_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_lm_perc_numeric plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# Evaluate metrics on test set
# pred_lm <- as.vector(h2o.predict(fit_lm, test))
# true_lm <- as.vector(test[1])
# rmse_lm <- sqrt(mean((pred_lm - true_lm)^2))
# cat("Linear Model RMSE on test set:", rmse_lm, "\n")

# Random forest
fit_rf_perc_numeric <- h2o.randomForest(x = xvars, y = colnames(df_modeling_perc_numeric_pdf)[1], training_frame = train, validation_frame = test)

shp_rf_perc_numeric <- shapviz(fit_rf_perc_numeric, X_pred = shap_test_sample)
# sv_force(shp_rf_perc_numeric, row_id = 1)
# sv_dependence(shp_rf_perc_numeric, xvars)
# sv_importance(shp_rf_perc_numeric, show_numbers = TRUE)
sv_importance(shp_rf_perc_numeric, kind = "beeswarm")

# shp_rf_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_rf_perc_numeric plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# Evaluate metrics on test set
# pred_rf <- as.vector(h2o.predict(fit_rf, test))
# true_rf <- as.vector(test$Sepal.Length)
# rmse_rf <- sqrt(mean((pred_rf - true_rf)^2))
# cat("Random Forest RMSE on test set:", rmse_rf, "\n")

# H2O XGBoost model

# # Train H2O XGBoost model
# fit_xgb_h2o_perc_numeric <- h2o.xgboost(
#   x = xvars,
#   y = colnames(df_modeling_perc_numeric_pdf)[1],
#   training_frame = train,
#   validation_frame = test,
#   ntrees = 500,
#   max_depth = 8,
#   learn_rate = 0.01,
#   seed = 42
# )
# 
# # SHAP values with shapviz
# shp_xgb_perc_numeric <- shapviz(fit_xgb_h2o_perc_numeric, X_pred = shap_test_sample, background_frame = train)
# # sv_force(shp_xgb_perc_numeric, row_id = 1)
# # sv_dependence(shp_xgb, xvars)
# sv_importance(shp_xgb_perc_numeric, show_numbers = TRUE)
# sv_importance(shp_xgb_perc_numeric, kind = "beeswarm")
# 
# shp_xgb_perc_numeric %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))
# 
# runtime <- difftime(Sys.time(), start_time, units = "secs")
# runtime_seconds <- as.numeric(runtime)
# runtime_minutes <- floor(runtime_seconds / 60)
# remaining_seconds <- runtime_seconds %% 60
# cat("\033[1;32mRuntime after shp_xgb_perc_numeric plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")
# 
# # Evaluate metrics on test set
# # pred_xgb <- as.vector(h2o.predict(fit_xgb_h2o, test_h2o))
# # true_xgb <- as.vector(test_h2o$percentage_correct_total)
# # rmse_xgb <- sqrt(mean((pred_xgb - true_xgb)^2))
# # cat("H2O XGBoost RMSE on test set:", rmse_xgb, "\n")

##### F1 NA ######

df2 <- df_characteristics %>% 
  filter(!is.na(NA_F1)) %>% slice_sample(n = sample_size)

# df2 <- df %>% filter(n_examples <= 5) %>% 
#   filter(!is.na(NA_F1)) %>% 
#   left_join(
#     norm_factors_few_examples %>% select(model_name, parameter_count), 
#     by = c("model" = "model_name")
#   ) %>% mutate(
#     log10_unit_multiplier = log10(unit_multiplier),
#     respect_units = !ignore_units,
#     n_columns = factor(n_columns)
#   ) %>% sample_n(sample_size)

formula_NA_F1_pdf = NA_F1 ~ 
  # method_family +
  # n_examples +
  # model_family +
  extraction_backend +
  # parameter_count +
  n_columns +
  # n_columns:input_format +
  sum_same_line +
  # sum_same_line:input_format +
  header_span +
  # header_span:input_format +
  # header_span:respect_units +
  # thin +
  # respect_units +
  # respect_units:input_format +
  # input_format +
  # year_as +
  # unit_in_first_cell +
  # unit_in_first_cell:input_format +
  # log10_unit_multiplier +
  # log10_unit_multiplier:input_format +
  enumeration +
  # shuffle_rows +
  # text_around +
  # many_line_breaks +
  # many_line_breaks:input_format
  T_in_previous_year + 
  T_in_year + 
  passiva_same_page +
  # spacer +
  vorjahr +
  vis_seperated_cols +
  vis_seperated_rows

# df_modeling_NA_F1_pdf <- df2 %>% 
#   # filter(input_format == "pdf") %>% 
#   model.matrix(data = ., object = formula_NA_F1_pdf) %>% 
#   as_tibble() %>% select(-"(Intercept)") %>% mutate(
#     target = df2$NA_F1, .before = 1
#   )

df_modeling_NA_F1_pdf <- df2 %>% select(all.vars(formula_NA_F1_pdf)) %>% 
  mutate(across(where(is.character), as.factor))

df_modeling_NA_F1_pdf.h2o <- as.h2o(df_modeling_NA_F1_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_NA_F1_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_NA_F1_pdf)[-1]

# Linear model
fit_lm_NA_F1 <- h2o.glm(x = xvars, y = colnames(df_modeling_NA_F1_pdf)[1], training_frame = train, validation_frame = test,
                        compute_p_values = TRUE, remove_collinear_columns = TRUE)

shap_test_sample <- as.h2o(test %>% as_tibble() %>% slice_sample(n = test_sample_size))

shp_lm_NA_F1 <- shapviz(fit_lm_NA_F1, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_lm, row_id = 1)
# sv_dependence(shp_lm, xvars)
# sv_importance(shp_lm, show_numbers = TRUE)
sv_importance(shp_lm_NA_F1, kind = "beeswarm")

# shp_lm_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_lm_NA_F1 plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# Random forest
fit_rf_NA_F1 <- h2o.randomForest(x = xvars, y = colnames(df_modeling_NA_F1_pdf)[1], training_frame = train, validation_frame = test)

shp_rf_NA_F1 <- shapviz(fit_rf_NA_F1, X_pred = shap_test_sample)
# sv_force(shp_rf, row_id = 1)
# sv_dependence(shp_rf, xvars)
# sv_importance(shp_rf, show_numbers = TRUE)
sv_importance(shp_rf_NA_F1, kind = "beeswarm")

# shp_rf_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_rf_NA_F1 plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# # H2O XGBoost model
# 
# # Train H2O XGBoost model
# fit_xgb_h2o_NA_F1 <- h2o.xgboost(
#   x = xvars,
#   y = colnames(df_modeling_NA_F1_pdf)[1],
#   training_frame = train,
#   validation_frame = test,
#   ntrees = 500,
#   max_depth = 8,
#   learn_rate = 0.01,
#   seed = 42
# )
# 
# # SHAP values with shapviz
# shp_xgb_NA_F1 <- shapviz(fit_xgb_h2o_NA_F1, X_pred = shap_test_sample, background_frame = train)
# # sv_force(shp_xgb, row_id = 1)
# # sv_dependence(shp_xgb, xvars)
# # sv_importance(shp_xgb, show_numbers = TRUE)
# sv_importance(shp_xgb_NA_F1, kind = "beeswarm")
# 
# shp_xgb_NA_F1 %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))
# 
# runtime <- difftime(Sys.time(), start_time, units = "secs")
# runtime_seconds <- as.numeric(runtime)
# runtime_minutes <- floor(runtime_seconds / 60)
# remaining_seconds <- runtime_seconds %% 60
# cat("\033[1;32mRuntime after shp_xgb_NA_F1 plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

##### binomial #####

df2 <- df_characteristics %>%
  unnest(predictions) %>%
  mutate(
    .before = 1,
    match_this_year = (is.na(year_truth) & is.na(year_result)) | year_truth == year_result,
    match_this_year = if_else(is.na(match_this_year), FALSE, match_this_year),
    missing_this_year = is.na(year_truth),
    match_previous_year = (is.na(previous_year_truth) & is.na(previous_year_result)) | previous_year_truth == previous_year_result,
    match_previous_year = if_else(is.na(match_previous_year), FALSE, match_previous_year),
    missing_previous_year = is.na(previous_year_truth),
    label_length = if_else(!is.na(E3), nchar(E3), if_else(!is.na(E2), nchar(E2), nchar(E1))),
    label = factor(paste(E1, E2, E3))
  ) %>% 
  # sample_n(min(2*sample_size, nrow(df_characteristics))) %>% 
  pivot_longer(
    cols = c(starts_with("match")),
    values_to = "match",
    names_to = "year", names_prefix = "match_"
  ) %>% mutate(
    .before = 1, 
    missing = if_else(year == "this_year", missing_this_year, missing_previous_year)
  ) %>% 
  group_by(match) %>% slice_sample(n = sample_size/2) # %>% mutate(match = factor(match))

formula_binomial_pdf = match ~
  # method_family +
  # n_examples +
  # model_family +
  extraction_backend +
  # parameter_count +
  n_columns +
  # n_columns:input_format +
  sum_same_line +
  # sum_same_line:input_format +
  header_span +
  # header_span:input_format +
  # header_span:respect_units +
  # thin +
  # respect_units +
  # respect_units:input_format +
  # input_format +
  # year_as +
  # unit_in_first_cell +
  # unit_in_first_cell:input_format +
  # log10_unit_multiplier +
  # log10_unit_multiplier:input_format +
  enumeration +
  # shuffle_rows +
  # text_around +
  # many_line_breaks +
  # many_line_breaks:input_format
  T_in_previous_year +
  T_in_year +
  passiva_same_page +
  # spacer +
  vorjahr +
  vis_seperated_cols +
  vis_seperated_rows +
  label_length +
  label +
  missing

# df_modeling_binomial_pdf <- df2 %>%
#   # filter(input_format == "pdf") %>%
#   model.matrix(data = ., object = formula_binomial_pdf) %>%
#   as_tibble() %>% select(-"(Intercept)") %>% mutate(
#     target = df2$confidence, .before = 1
#   )

df_modeling_binomial_pdf <- df2 %>% select(all.vars(formula_binomial_pdf)) %>%
  mutate(across(where(is.character), as.factor))

# library(shapviz)
# library(h2o)
#
# # h2o.shutdown()
# h2o.init()

df_modeling_binomial_pdf.h2o <- as.h2o(df_modeling_binomial_pdf)

# Train-test split
set.seed(42)
split <- h2o.splitFrame(df_modeling_binomial_pdf.h2o, ratios = 0.7, seed = 42)
train <- split[[1]]
test <- split[[2]]

xvars <- colnames(df_modeling_binomial_pdf)[-1]

# Linear model
fit_lm_binomial <- h2o.glm(x = xvars, y = colnames(
  df_modeling_binomial_pdf)[1], training_frame = train, validation_frame = test,
  family = "binomial") #,
  # compute_p_values = TRUE, remove_collinear_columns = TRUE)

shap_test_sample <- as.h2o(test %>% as_tibble() %>% slice_sample(n = test_sample_size))

shp_lm_binomial <- shapviz(fit_lm_binomial, X_pred = shap_test_sample, background_frame = train)
# sv_force(shp_lm, row_id = 1)
# sv_dependence(shp_lm, xvars)
# sv_importance(shp_lm, show_numbers = TRUE)
sv_importance(shp_lm_binomial, kind = "beeswarm")

# shp_lm_binomial %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_lm_binomial plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# Random forest
fit_rf_binomial <- h2o.randomForest(x = xvars, y = colnames(df_modeling_binomial_pdf)[1], training_frame = train, validation_frame = test)

shp_rf_binomial <- shapviz(fit_rf_binomial, X_pred = shap_test_sample)
# sv_force(shp_rf, row_id = 1)
# sv_dependence(shp_rf, xvars)
# sv_importance(shp_rf, show_numbers = TRUE)
sv_importance(shp_rf_binomial, kind = "beeswarm")
sv_waterfall(shp_rf_binomial, 1)

# shp_rf_binomial %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))

runtime <- difftime(Sys.time(), start_time, units = "secs")
runtime_seconds <- as.numeric(runtime)
runtime_minutes <- floor(runtime_seconds / 60)
remaining_seconds <- runtime_seconds %% 60
cat("\033[1;32mRuntime after shp_rf_binomial plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

# # H2O XGBoost model
#
# # Train H2O XGBoost model
# fit_xgb_h2o_binomial <- h2o.xgboost(
#   x = xvars,
#   y = colnames(df_modeling_binomial_pdf)[1],
#   training_frame = train,
#   validation_frame = test,
#   ntrees = 500,
#   max_depth = 8,
#   learn_rate = 0.01,
#   seed = 42
# )
#
# # SHAP values with shapviz
# shp_xgb_binomial <- shapviz(fit_xgb_h2o_binomial, X_pred = shap_test_sample, background_frame = train)
# # sv_force(shp_xgb, row_id = 1)
# # sv_dependence(shp_xgb, xvars)
# # sv_importance(shp_xgb, show_numbers = TRUE)
# sv_importance(shp_xgb_binomial, kind = "beeswarm")
#
# shp_xgb_binomial %>% plot_shap_importance_signed(max_label_length = 30) +
#   coord_cartesian(xlim = c(0, 0.15))
#
# runtime <- difftime(Sys.time(), start_time, units = "secs")
# runtime_seconds <- as.numeric(runtime)
# runtime_minutes <- floor(runtime_seconds / 60)
# remaining_seconds <- runtime_seconds %% 60
# cat("\033[1;32mRuntime after shp_xgb_binomial plot:\033[0m", runtime_minutes, "minutes and", round(remaining_seconds), "seconds\n")

##### export #####

list(
  perc_numeric = list(
    models = list(
      lm = fit_lm_perc_numeric,
      rf = fit_rf_perc_numeric#,
      # xgb = fit_xgb_h2o_perc_numeric
    ),
    shap_values = list(
      lm = shp_lm_perc_numeric, 
      rf = shp_rf_perc_numeric#, 
      # xgb = shp_xgb_perc_numeric
    )
  ),
  NA_F1 = list(
    models = list(
      lm = fit_lm_NA_F1,
      rf = fit_rf_NA_F1#,
      # xgb = fit_xgb_h2o_NA_F1
    ),
    shap_values = list(
      lm = shp_lm_NA_F1, 
      rf = shp_rf_NA_F1#, 
      # xgb = shp_xgb_NA_F1
    )
  ),
  binomial = list(
    models = list(
      lm = fit_lm_binomial,
      rf = fit_rf_binomial#,
      # xgb = fit_xgb_h2o_NA_F1
    ),
    shap_values = list(
      lm = shp_lm_binomial, 
      rf = shp_rf_binomial#, 
      # xgb = shp_xgb_NA_F1
    )
  )
  # confidence = list(
  #   models = list(
  #     lm = fit_lm_confidence,
  #     rf = fit_rf_confidence#,
  #     # xgb = fit_xgb_h2o_confidence
  #   ),
  #   shap_values = list(
  #     lm = shp_lm_confidence, 
  #     rf = shp_rf_confidence#, 
  #     # xgb = shp_xgb_confidence
  #   )
  # )
) %>% saveRDS(paste0("data_storage/h2o/real_table_extraction_regex_h2o_results_sample_",sample_size,"_shap_",test_sample_size,".rds"))