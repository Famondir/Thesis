library(jsonlite)
library(tidyverse)

temp_list <- readRDS("data_storage/page_identification_llm.rds")
df_binary <- temp_list$df_binary
df_multi <- temp_list$df_multi

method_families <- c("zero_shot", "law_context", "top_n_rag_examples", "n_random_examples", 'n_rag_examples')
method_familiy_colors <- c(
  "zero_shot" = "#e41a1c", 
  "law_context" = "#377eb8", 
  "top_n_rag_examples" = "#4daf4a", 
  "n_random_examples" = "#984ea3", 
  'n_rag_examples' = "#ff7f00"
  )

#### Binary ####

##### Plotting #####

# df_binary %>% filter(model == "mistralai_Ministral-8B-Instruct-2410", loop < 2) %>% 
#   ggplot(aes(x = runtime, y = f1_score)) +
#   geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
#   scale_shape(na.value = 15, guide = "legend") +
#   geom_text(aes(label = n_examples)) +
#   facet_grid(model~classification_type) +
#   theme(legend.position = "bottom") +
#   guides(
#     color = guide_legend(ncol = 1, title.position = "top"),
#     shape = guide_legend(ncol = 1, title.position = "top")
#   )

df_binary %>% filter(model == "mistralai_Ministral-8B-Instruct-2410", loop < 2) %>% 
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(model~classification_type) +
  scale_color_manual(values = method_familiy_colors) +
  # theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

df_binary %>% filter(model == "mistralai_Ministral-8B-Instruct-2410", loop < 3) %>% 
  filter(n_examples <= 5 | is.na(n_examples)) %>% 
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  scale_color_manual(values = method_familiy_colors) +
  facet_grid(model~classification_type) +
  # theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

df_binary %>% filter(model == "mistralai_Ministral-8B-Instruct-2410", loop < 2) %>% 
  filter(n_examples > 1 | is.na(n_examples)) %>% 
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  scale_color_manual(values = method_familiy_colors) +
  geom_text(aes(label = n_examples)) +
  facet_grid(model~classification_type) +
  # theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

design = "
ABCD##W
EFGHI#x
JKL####
MNOPQRS
TUV####
"

# df_binary_arragned <- df_binary %>% select(model, parameter_count, model_family) %>% unique() %>%
  # arrange(tolower(model_family), parameter_count)
# model_letters <- tibble(model = df_binary_arragned %>% pull(model), facet = LETTERS[1:(df_binary_arragned %>% nrow())])
model_by_size <- c('google_gemma-3-4b-it-0-9-1', 'google_gemma-3n-E4B-it-0-9-1', "google_gemma-3-12b-it-0-9-1",
  "google_gemma-3-27b-it-0-9-1", "meta-llama_Llama-3.1-8B-Instruct", 
  "meta-llama_Llama-3.1-70B-Instruct", "meta-llama_Llama-3.3-70B-Instruct",
  "meta-llama_Llama-4-Scout-17B-16E-Instruct", "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8",
  "mistralai_Ministral-8B-Instruct-2410", "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
  "mistralai_Mistral-Large-Instruct-2411", "Qwen_Qwen2.5-0.5B-Instruct",
  "Qwen_Qwen2.5-1.5B-Instruct", "Qwen_Qwen2.5-3B-Instruct", "Qwen_Qwen2.5-7B-Instruct",
  "Qwen_Qwen2.5-14B-Instruct", "Qwen_Qwen2.5-32B-Instruct", "Qwen_Qwen2.5-72B-Instruct",
  "Qwen_Qwen3-8B", "Qwen_Qwen3-32B", "Qwen_Qwen3-235B-A22B-Instruct-2507",
  "tiiuae_Falcon3-10B-Instruct", "microsoft_phi-4"
  )

df_binary %>% filter(classification_type == "Aktiva") %>% 
  filter(loop == 0) %>% filter(model %in% model_by_size) %>% 
  mutate(norm_runtime = norm_runtime/60) %>% 
  filter(n_examples <= 3 | is.na(n_examples)) %>% 
  # left_join(model_letters, by = "model") %>%
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  # ggplot(aes(x = norm_runtime, y = recall)) +
  # ggplot(aes(x = norm_runtime, y = precision)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  # facet_grid(classification_type~model) +
  ggh4x::facet_manual(~factor(model, levels = model_by_size), design = design) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

# mistral
target <- "Aktiva"
df_filtered <- df_binary %>% filter(classification_type == target) %>% 
  arrange(desc(f1_score))
df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
df_flipped_score <- df_temp %>% 
  mutate(
    confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
    is_target = str_detect(type, target)
  )
model_name_best_f1_aktiva <- df_filtered[1, "model"]
method__best_f1_aktiva <- df_filtered[1, "method"]

df_flipped_score %>% 
  ggplot() +
  geom_boxplot(aes(x = predicted_type, y = confidence_score)) +
  geom_jitter(aes(x = predicted_type, y = confidence_score, color = match), alpha = .3) +
  facet_wrap(~type) +
  labs(title = model_name_best_f1_aktiva,
       subtitle = method__best_f1_aktiva)

# qwen
df_filtered <- df_binary %>% filter(classification_type == "Aktiva", model_family=="Qwen") %>% 
  arrange(desc(f1_score))
df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
df_flipped_score <- df_temp %>% 
  mutate(
    confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
    is_aktiva = str_detect(type, "Aktiva")
  )
model_name_best_f1_aktiva <- df_filtered[1, "model"]
method__best_f1_aktiva <- df_filtered[1, "method"]

df_flipped_score %>% 
  ggplot() +
  geom_boxplot(aes(x = predicted_type, y = confidence_score)) +
  geom_jitter(aes(x = predicted_type, y = confidence_score, color = match), alpha = .3) +
  facet_wrap(~type) +
  labs(title = model_name_best_f1_aktiva,
       subtitle = method__best_f1_aktiva)

###### ROC ######

library(pROC)

# ROC curve
roc_obj <- roc(df_flipped_score$match, df_flipped_score$confidence_score)

# Plot ROC curve
plot(roc_obj, main = "ROC Curve for Aktiva Classification")
auc_val <- auc(roc_obj)
legend("bottomright", legend = paste("AUC =", round(auc_val, 3)))

### all targets combined

library(pROC)

l_temp <- list()

for (target in c('Aktiva', 'GuV', 'Passiva')) {
  df_filtered <- df_binary %>% 
    filter(
      classification_type == target,
      model == model_name_best_f1_aktiva,
      method == method__best_f1_aktiva
      ) %>% 
    arrange(desc(f1_score))
  df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
  df_flipped_score <- df_temp %>% 
    mutate(
      confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
      target = target
    )
  l_temp[target] <- list(df_flipped_score)
}

df_temp2 <- bind_rows(l_temp)

# ROC curve
roc_obj <- roc(df_temp2$match, df_temp2$confidence_score)
auc_value <- roc_obj$auc %>% round(3)

ggroc(roc_obj, color = 'orange') +
  geom_label(
      data = df_temp2[1,],
      label = str_c("AUC: ", auc_value),
      aes(x = 0, y = 0),
      hjust = 1
    ) +
  labs(
    x = "False Positive Rate",
    y = "True Positive Rate"
  ) +
  geom_abline(
    slope = 1, intercept = 1,
    linetype = 'longdash',
    color = 'blue'
    )

# Plot ROC curve
plot(roc_obj, main = "ROC Curve for Aktiva Classification")
auc_val <- auc(roc_obj)
legend("bottomright", legend = paste("AUC =", round(auc_val, 3)))

### all seperate

# l_rocs <- list()
# 
# for (target in c('Aktiva', 'GuV', 'Passiva')) {
#   df_filtered <- df_binary %>% 
#     filter(
#       classification_type == target,
#       model == model_name_best_f1_aktiva,
#       method == method__best_f1_aktiva
#     ) %>% 
#     arrange(desc(f1_score))
#   df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
#   df_flipped_score <- df_temp %>% 
#     mutate(
#       confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
#       target = target
#     )
#   
#   roc_obj <- roc(df_flipped_score$match, df_flipped_score$confidence_score)
#   l_rocs[target] <- list(roc_obj)
# }
# 
# ggroc(l_rocs) +
#   facet_wrap(~target)
# 
# # Plot ROC curve
# plot(roc_obj, main = "ROC Curve for Aktiva Classification")
# auc_val <- auc(roc_obj)
# legend("bottomright", legend = paste("AUC =", round(auc_val, 3)))

library(PRROC)

l_temp <- list()

for (target in c('Aktiva', 'GuV', 'Passiva')) {
  t <- "Aktiva"
  df_filtered <- df_binary %>% filter(classification_type == t) %>% 
    arrange(desc(f1_score))
  model_name_best_f1_aktiva <- df_filtered[300, "model"]
  method__best_f1_aktiva <- df_filtered[300, "method"]
  
  df_filtered <- df_binary %>% 
    filter(
      classification_type == target,
      model == model_name_best_f1_aktiva,
      method == method__best_f1_aktiva
    ) %>% 
    arrange(desc(f1_score))
  df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
  df_flipped_score <- df_temp %>% 
    mutate(
      confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
      target = target
    )
  l_temp[target] <- list(df_flipped_score)
}

df_temp2 <- bind_rows(l_temp) # %>% filter(target == "Passiva")

pr_obj <- pr.curve(scores.class0 = df_temp2$confidence_score[df_temp2$match == 1],
                   scores.class1 = df_temp2$confidence_score[df_temp2$match == 0],
                   curve = TRUE)

plot(pr_obj, color = "orange", main = "Precision-Recall Curve")
ggprroc(pr_obj)

library(PRROC)
library(patchwork)

l_temp <- list()

for (target in c('Aktiva', 'GuV', 'Passiva')) {
  t <- "Aktiva"
  df_filtered <- df_binary %>% filter(classification_type == t) %>% 
    arrange(desc(f1_score))
  model_name_best_f1_aktiva <- df_filtered[300, "model"]
  method__best_f1_aktiva <- df_filtered[300, "method"]
  
  df_filtered <- df_binary %>% 
    filter(
      classification_type == target,
      model == model_name_best_f1_aktiva,
      method == method__best_f1_aktiva,
      loop == 0
    ) %>% 
    arrange(desc(f1_score))
  df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
  df_flipped_score <- df_temp %>% 
    mutate(
      confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
      target = target
    )
  l_temp[target] <- list(df_flipped_score)
}

df_temp2 <- bind_rows(l_temp) # %>% filter(target == "Passiva")
# plot(pr_obj, color = "orange", main = "Precision-Recall Curve")

pr_obj <- pr.curve(scores.class0 = df_temp2$confidence_score[df_temp2$match == 1],
                   scores.class1 = df_temp2$confidence_score[df_temp2$match == 0],
                   curve = TRUE)

# Precision-Recall Curve with ggplot2

pr_df <- tibble(
  recall = pr_obj$curve[, 1],
  precision = pr_obj$curve[, 2],
  threshold = pr_obj$curve[, 3]
) %>%
  mutate(f1 = 2 * precision * recall / (precision + recall))

pr_auc <- round(pr_obj$auc.integral, 3)

g1 <- pr_df %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_line(aes(color = threshold), size = 1.2) +
  scale_color_viridis_c(option = "plasma") +
  labs(
    title = str_c("Precision-Recall Curve (AUC = ", pr_auc, ")"),
    subtitle = str_c(model_name_best_f1_aktiva, " with ", method__best_f1_aktiva),
    x = "Recall",
    y = "Precision"
  ) +
  coord_cartesian(ylim = c(0,1)) +
  theme(
    legend.position = "bottom"
  )

g2 <- pr_df %>%
  ggplot(aes(x = recall, y = precision, color = f1)) +
  geom_line(size = 1.2) +
  scale_color_viridis_c(option = "viridis") +
  labs(
    # title = "Precision-Recall Curve colored by F1 score",
    x = "Recall",
    y = NULL,
    color = "F1 score"
  ) +
  coord_cartesian(ylim = c(0,1))+
  theme(
    legend.position = "bottom"
  )

g1 + g2

###### per company ######

no_ocr_needed <- read_csv("../benchmark_truth/aktiva_passiva_guv_table_pages_no_ocr.csv") %>% select(filepath) %>% 
  unique() %>% mutate(filepath = str_replace(filepath, "..", "/pvc")) %>% .[[1]]

l <- list()

for (t in c('Aktiva', 'Passiva', 'GuV')) {
  df_filtered <- df_binary %>% filter(classification_type == t) %>% 
    arrange(desc(f1_score)) %>% select(model_family, method_family, predictions)
  df_temp <- df_filtered %>% unnest(predictions) %>% filter(filepath %in% no_ocr_needed)
  
  df_f1_by_company <- df_temp %>% group_by(company, predicted_type, match, model_family, method_family) %>% reframe(
    n = n()
  ) %>% complete(company, predicted_type, match, model_family, method_family,fill=list(n=0)) %>% 
    mutate(
      metric = if_else(predicted_type == t & match, "true_positive", ''),
      metric = if_else(predicted_type == t & !match, "false_positive", metric),
      metric = if_else(predicted_type != t & !match, "false_negative", metric),
      metric = if_else(predicted_type != t & match, "true_negative", metric),
    ) %>% select(-predicted_type, -match) %>% 
    pivot_wider(names_from = metric, values_from = n) %>% 
    mutate(
      precision = true_positive/(true_positive+false_positive),
      recall = true_positive/(true_positive+false_negative),
      f1_score = 2*precision*recall/(precision+recall),
      classification_type = t
    )
  
  l[t] <- list(df_f1_by_company)
}

df_f1_by_company <- bind_rows(l)

df_f1_by_company %>% ggplot() +
  geom_boxplot(aes(x = company, y = f1_score)) +
  geom_jitter(aes(x = company, y = f1_score, color = model_family), alpha = .4) +
  facet_grid(~classification_type)

for (t in c('Aktiva', 'Passiva', 'GuV')) {
  df_filtered <- df_binary %>% filter(classification_type == t) %>% 
    arrange(desc(f1_score)) %>% select(model, method, predictions, model_family, method_family)
  df_temp <- df_filtered %>% unnest(predictions) %>% filter(filepath %in% no_ocr_needed)
  
  df_f1_by_company <- df_temp %>% group_by(company, predicted_type, match, model,model_family, method, method_family) %>% reframe(
    n = n()
  ) %>% complete(company, predicted_type, match, model,model_family, method, method_family,fill=list(n=0)) %>% 
    mutate(
      metric = if_else(predicted_type == t & match, "true_positive", ''),
      metric = if_else(predicted_type == t & !match, "false_positive", metric),
      metric = if_else(predicted_type != t & !match, "false_negative", metric),
      metric = if_else(predicted_type != t & match, "true_negative", metric),
    ) %>% select(-predicted_type, -match) %>% 
    pivot_wider(names_from = metric, values_from = n) %>% 
    mutate(
      precision = true_positive/(true_positive+false_positive),
      recall = true_positive/(true_positive+false_negative),
      f1_score = 2*precision*recall/(precision+recall),
      classification_type = t
    )
  
  l[t] <- list(df_f1_by_company)
}

# df_filtered <- df_binary %>% filter(classification_type == "Aktiva") %>% 
#   arrange(desc(f1_score)) %>% select(model_family, method_family, predictions)
# df_temp <- df_filtered %>% unnest(predictions)
# 
# df_f1_by_company <- df_temp %>% group_by(company, predicted_type, match, model_family, method_family) %>% reframe(
#   n = n()
# ) %>% complete(company, predicted_type, match, model_family, method_family,fill=list(n=0)) %>% 
#   mutate(
#   metric = if_else(predicted_type == "Aktiva" & match, "true_positive", ''),
#   metric = if_else(predicted_type == "Aktiva" & !match, "false_positive", metric),
#   metric = if_else(predicted_type != "Aktiva" & !match, "false_negative", metric),
#   metric = if_else(predicted_type != "Aktiva" & match, "true_negative", metric),
# ) %>% select(-predicted_type, -match) %>% 
#   pivot_wider(names_from = metric, values_from = n) %>% 
#   mutate(
#     precision = true_positive/(true_positive+false_positive),
#     recall = true_positive/(true_positive+false_negative),
#     f1_score = 2*precision*recall/(precision+recall)
#   )

df_f1_by_company <- bind_rows(l)

df_f1_by_company %>% ggplot() +
  geom_boxplot(aes(x = company, y = precision)) +
  # geom_jitter(aes(x = company, y = recall, color = method_family), alpha = .4) +
  facet_grid(classification_type~model_family) +
  scale_x_discrete(guide = guide_axis(angle = 30))

n_reports_by_company_no_ocr <- df_temp %>% select(company, filepath) %>% unique() %>% group_by(company) %>% reframe(n = n())
n_reports_by_company <- df_filtered %>% unnest(predictions) %>% select(company, filepath) %>% unique() %>% group_by(company) %>% reframe(n = n())

#### Multiclass ####

##### Plotting #####

df_selected <- df_multi %>% unnest(metrics) %>% filter(metric_type == "Aktiva")

df_selected %>% 
  filter(model %in% c(
    "mistralai_Ministral-8B-Instruct-2410"
    # "mistralai_Mistral-Large-Instruct-2411",
    # "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
    # "meta-llama_Llama-4-Scout-17B-16E-Instruct",
    # "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8"
  )) %>% 
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(model~metric_type) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  ) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df_selected %>%
  ggplot(aes(x = runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(metric_type~model) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  ) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df_temp <- (df_selected %>% arrange(desc(f1_score)))[1,"predictions"][[1]][[1]] %>% as_tibble()

df_temp %>% 
  ggplot() +
  geom_boxplot(aes(x = predicted_type, y = confidence_score)) +
  geom_jitter(aes(x = predicted_type, y = confidence_score, color = match), alpha = .2) +
  facet_wrap(~type)

calc_answer_ratio <- function(df) {
  df %>% 
    group_by(type) %>% 
    mutate(
      n_type = n(),
    ) %>%
    group_by(predicted_type, type) %>%
    reframe(
      n = n(),
      perc = n/n_type,
    ) %>% unique()
}

df_answer_patterns <- df_multi %>% 
  unnest(metrics) %>% 
  filter(metric_type == "micro_minorities") %>%
  group_by(model) %>%
  filter(f1_score == max(f1_score, na.rm = TRUE)) %>%
  mutate(
    answer_ratio = map(predictions, calc_answer_ratio)
  ) %>% 
  unnest(answer_ratio)

df_answer_patterns %>% 
  # select(model, type, predicted_type, method_family, model_family, perc, f1_score) %>% 
  group_by(model, type, predicted_type, model_family) %>%
  reframe(
    f1_score = mean(f1_score, na.rm = TRUE),
    perc = mean(perc, na.rm = TRUE)
  ) %>%
  arrange(model_family, desc(f1_score)) %>%
  ggplot() +
  geom_tile(aes(x = predicted_type, y = type, fill = perc)) +
  facet_wrap(~model)


design = "
ABCD##W
EFGHI#x
JKL####
MNOPQRS
TUV####
"

model_by_size <- c('google_gemma-3-4b-it-0-9-1', 'google_gemma-3n-E4B-it-0-9-1', "google_gemma-3-12b-it-0-9-1",
                   "google_gemma-3-27b-it-0-9-1", "meta-llama_Llama-3.1-8B-Instruct", 
                   "meta-llama_Llama-3.1-70B-Instruct", "meta-llama_Llama-3.3-70B-Instruct",
                   "meta-llama_Llama-4-Scout-17B-16E-Instruct", "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8",
                   "mistralai_Ministral-8B-Instruct-2410", "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
                   "mistralai_Mistral-Large-Instruct-2411", "Qwen_Qwen2.5-0.5B-Instruct",
                   "Qwen_Qwen2.5-1.5B-Instruct", "Qwen_Qwen2.5-3B-Instruct", "Qwen_Qwen2.5-7B-Instruct",
                   "Qwen_Qwen2.5-14B-Instruct", "Qwen_Qwen2.5-32B-Instruct", "Qwen_Qwen2.5-72B-Instruct",
                   "Qwen_Qwen3-8B", "Qwen_Qwen3-32B", "Qwen_Qwen3-235B-A22B-Instruct-2507",
                   "tiiuae_Falcon3-10B-Instruct", "microsoft_phi-4"
)

df_multi %>% unnest(metrics) %>% 
  filter(metric_type %in% c(
    "Aktiva"#, "Passiva", "GuV"
    )) %>% 
  filter(loop == 0) %>% filter(model %in% model_by_size) %>% 
  mutate(norm_runtime = norm_runtime/60) %>% 
  filter(n_examples <= 3 | is.na(n_examples)) %>% 
  # left_join(model_letters, by = "model") %>%
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  # ggplot(aes(x = norm_runtime, y = recall)) +
  # ggplot(aes(x = norm_runtime, y = precision)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  # facet_grid(classification_type~model) +
  ggh4x::facet_manual(~factor(model, levels = model_by_size), design = design) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(nrow = 1),
    shape = guide_legend(nrow = 1)
  )

###### ROC ######

library(pROC)

df_selected <- df_multi %>% unnest(metrics)
df_filtered <- df_selected %>% filter(
  metric_type == "micro_minorities"
) %>% 
  arrange(desc(f1_score))
df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()

roc_obj <- roc(df_temp$match, df_temp$confidence_score)
auc_value <- roc_obj$auc %>% round(3)

ggroc(roc_obj, color = 'orange') +
  geom_label(
    data = df_temp2[1,],
    label = str_c("AUC: ", auc_value),
    aes(x = 0, y = 0),
    hjust = 1
  ) +
  labs(
    x = "False Positive Rate",
    y = "True Positive Rate"
  ) +
  geom_abline(
    slope = 1, intercept = 1,
    linetype = 'longdash',
    color = 'blue'
  )

library(PRROC)
library(patchwork)

df_selected <- df_multi %>% unnest(metrics)
df_filtered <- df_selected %>% filter(
  metric_type == "micro_minorities"
) %>% 
  arrange(desc(f1_score))
df_temp <- df_filtered[300,"predictions"][[1]][[1]] %>% as_tibble()

pr_obj <- pr.curve(scores.class0 = df_temp$confidence_score[df_temp$match == 1],
                   scores.class1 = df_temp$confidence_score[df_temp$match == 0],
                   curve = TRUE)

# plot(pr_obj, color = "orange", main = "Precision-Recall Curve")

# Precision-Recall Curve with ggplot2

pr_df <- tibble(
  recall = pr_obj$curve[, 1],
  precision = pr_obj$curve[, 2],
  threshold = pr_obj$curve[, 3]
) %>%
  mutate(f1 = 2 * precision * recall / (precision + recall))

pr_auc <- round(pr_obj$auc.integral, 3)

g1 <- pr_df %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_line(aes(color = threshold), size = 1.2) +
  scale_color_viridis_c(option = "plasma") +
  labs(
    title = str_c("Precision-Recall Curve (AUC = ", pr_auc, ")"),
    x = "Recall",
    y = "Precision"
  ) +
  coord_cartesian(ylim = c(0,1)) +
  theme(
    legend.position = "bottom"
  )

g2 <- pr_df %>%
  ggplot(aes(x = recall, y = precision, color = f1)) +
  geom_line(size = 1.2) +
  scale_color_viridis_c(option = "viridis") +
  labs(
    # title = "Precision-Recall Curve colored by F1 score",
    x = "Recall",
    y = NULL,
    color = "F1 score"
  ) +
  coord_cartesian(ylim = c(0,1))+
  theme(
    legend.position = "bottom"
  )

g1 + g2
