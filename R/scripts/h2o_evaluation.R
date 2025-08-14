library(tidyverse)
library(shapviz)
library(h2o)
library(stringr)
library(ggplot2)

source("report_misc/helper_functions.R")

styled_waterfall <- function(shap, row_id = 1, xlim = c(-0.15,1.05), ylim = c(0,11)) {
  p <- shap %>% sv_waterfall(row_id = row_id)
  p + scale_y_discrete(labels = function(x) str_wrap(x, width = 40)) +
    scale_x_continuous(breaks = seq(0, 1, by = 0.2)) +
    coord_cartesian(xlim = xlim, ylim = ylim)
}

#### real tables regex ####

results <- readRDS("data_storage/h2o/real_table_extraction_regex_h2o_results_sample_50000_shap_2000.rds")

##### numeric #####

###### random forest ######

# results$perc_numeric$model$lm

shap <- results$perc_numeric$shap_values$rf %>% convert_shap_x()
# shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
#   n_columns = factor(as.numeric(n_columns)+1)
# )

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

##### NA_F1 #####

###### random forest ######

shap <- results$NA_F1$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

shap %>% sv_dependence("n_columns", color_var = "sum_same_line")
# shap %>% sv_dependence("vis_seperated_cols")

##### binomial #####

###### random forest ######

shap <- results$binomial$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1], xlim = c(-0.25, 1.05))
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence(colnames(.$X), "label", color_var = "extraction_backend")
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence("header_span")

#### real tables lmm ####

results <- readRDS("data_storage/h2o/real_table_extraction_h2o_results_sample_50000_shap_2000.rds")

##### numeric #####

###### random forest ######

shap <- results$perc_numeric$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

shap %>% sv_dependence("n_examples")
shap %>% sv_dependence("T_in_year")
# shap %>% sv_dependence("model_family") +
#   theme(axis.text.x = element_text(angle = 30, hjust = 1))

##### NA_F1 #####

###### random forest ######

shap <- results$NA_F1$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

##### binomial #####

###### random forest ######

shap <- results$binomial$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE, max_display = 25)
shap %>% sv_importance(kind = "beeswarm", max_display = 25)

shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence("confidence")

##### confidence #####

###### random forest ######

shap <- results$confidence$shap_values$rf
shap$X <- shap$X %>% mutate(across(everything(), convert_binary)) %>% mutate(
  n_columns = factor(as.numeric(n_columns)+1)
)

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE, max_display = 25)
shap %>% sv_importance(kind = "beeswarm", max_display = 25)

shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_dependence("parameter_count", color_var = "model_family")
shap %>% sv_dependence("method_family")

#### real tables lmm synth context ####

results <- readRDS("data_storage/h2o/real_table_extraction_synth_context_h2o_results_sample_50000_shap_2000.rds")

##### numeric #####

###### random forest ######

shap <- results$perc_numeric$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

##### NA_F1 #####

###### random forest ######

shap <- results$NA_F1$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

##### binomial #####

###### random forest ######

shap <- results$binomial$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

##### confidence #####

###### random forest ######

shap <- results$confidence$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

#### synth tables regex ####

results <- readRDS("data_storage/h2o/synth_table_extraction_regex_h2o_results_sample_50000_shap_2000_NA_recoded.rds")

##### numeric #####

###### random forest ######

shap <- results$perc_numeric$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_dependence("extraction_backend") # very interesting!
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_dependence("extraction_backend")
# shap %>% sv_dependence("thin")
shap %>% sv_dependence("header_span", color_var = "extraction_backend")

##### NA_F1 #####

###### random forest ######

shap <- results$NA_F1$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_dependence("extraction_backend") # very interesting!
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence("unit_in_first_cell", color_var = "extraction_backend")

##### binomial #####

###### random forest ######

shap <- results$binomial$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"), color_var = "extraction_backend")
shap %>% sv_dependence("extraction_backend") # very interesting! (repeating)
# shap %>% sv_dependence("extraction_backend", color_var = "n_columns") # not so strong
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm")

#### synth tables lmm ####

results <- readRDS("data_storage/h2o/synth_table_extraction_h2o_results_sample_50000_shap_2000_NA_recoded.rds")

##### numeric #####

###### random forest ######

shap <- results$perc_numeric$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_dependence("method_family")
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm", max_display = 30)

shap %>% sv_dependence(colnames(.$X), color_var = "input_format")
shap %>% sv_dependence(colnames(.$X), color_var = "respect_units")

##### NA_F1 #####

###### random forest ######

shap <- results$NA_F1$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(colnames(.$X))
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm", max_display = 30)

shap %>% sv_dependence(colnames(.$X), color_var = "input_format")
shap %>% sv_dependence(colnames(.$X), color_var = "respect_units")

##### binomial #####

###### random forest ######

shap <- results$binomial$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)], xlim = c(-.4,1.05))
shap %>% styled_waterfall(row_id = idx_lowest[1], xlim = c(-.4,1.05))
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm", max_display = 30)

shap %>% sv_dependence(colnames(.$X), color_var = "input_format")
shap %>% sv_dependence(colnames(.$X), color_var = "respect_units")

##### confidence #####

###### random forest ######

shap <- results$confidence$shap_values$rf

df_shap <- tibble(
  y = (shap$S %>% rowSums())+shap$baseline
) %>% bind_cols(shap$X) %>% rowid_to_column() %>% 
  arrange(y)
idx_lowest <- df_shap %>% pull(rowid)

shap %>% styled_waterfall(row_id = idx_lowest[length(idx_lowest)])
shap %>% styled_waterfall(row_id = idx_lowest[1])
shap %>% sv_force(row_id = idx_lowest[1])
shap %>% sv_dependence(setdiff(colnames(.$X), "label"))
shap %>% sv_dependence("label", color_var = "missing") +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  scale_x_discrete(labels = function(x) {
    trimmed <- str_trim(str_sub(x, -40))
    ifelse(nchar(x) > 40, paste0("...", trimmed), trimmed)
  })
shap %>% sv_importance(show_numbers = TRUE)
shap %>% sv_importance(kind = "beeswarm", max_display = 30)

shap %>% sv_dependence(colnames(.$X), color_var = "input_format")
shap %>% sv_dependence(colnames(.$X), color_var = "respect_units")
shap %>% sv_dependence(colnames(.$X), color_var = "many_line_breaks")
