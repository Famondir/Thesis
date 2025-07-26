temp_list <- readRDS("data_storage/page_identification_llm.rds")
df_binary <- temp_list$df_binary
df_multi <- temp_list$df_multi

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
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

design = "
ABCD###
EFGHI##
JKL####
MNOPQRS
TUV####
"

# df_binary_arragned <- df_binary %>% select(model, parameter_count, model_family) %>% unique() %>%
  # arrange(tolower(model_family), parameter_count)
# model_letters <- tibble(model = df_binary_arragned %>% pull(model), facet = LETTERS[1:(df_binary_arragned %>% nrow())])
model_by_size <- c('google_gemma-3-4b-it', 'google_gemma-3n-E4B-it', "google_gemma-3-12b-it",
  "google_gemma-3-27b-it", "meta-llama_Llama-3.1-8B-Instruct", 
  "meta-llama_Llama-3.1-70B-Instruct", "meta-llama_Llama-3.3-70B-Instruct",
  "meta-llama_Llama-4-Scout-17B-16E-Instruct", "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8",
  "mistralai_Ministral-8B-Instruct-2410", "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
  "mistralai_Mistral-Large-Instruct-2411", "Qwen_Qwen2.5-0.5B-Instruct",
  "Qwen_Qwen2.5-1.5B-Instruct", "Qwen_Qwen2.5-3B-Instruct", "Qwen_Qwen2.5-7B-Instruct",
  "Qwen_Qwen2.5-14B-Instruct", "Qwen_Qwen2.5-32B-Instruct", "Qwen_Qwen2.5-72B-Instruct",
  "Qwen_Qwen3-8B", "Qwen_Qwen3-32B", "Qwen_Qwen3-235B-A22B-Instruct-2507")

df_binary %>% filter(classification_type == "Aktiva") %>% 
  filter(loop == 0) %>% 
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

df_temp <- (df_binary %>% arrange(desc(f1_score)))[1,"predictions"][[1]][[1]] %>% as_tibble()
df_flipped_score <- df_temp %>% 
  mutate(
    confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
    is_aktiva = str_detect(type, "Aktiva")
  )

df_flipped_score %>% 
  ggplot() +
  geom_boxplot(aes(x = predicted_type, y = confidence_score)) +
  geom_jitter(aes(x = predicted_type, y = confidence_score, color = match), alpha = .2) +
  facet_wrap(~type)

library(pROC)

# ROC curve
roc_obj <- roc(df_flipped_score$is_aktiva, df_flipped_score$confidence_score)

# Plot ROC curve
plot(roc_obj, main = "ROC Curve for Aktiva Classification")
auc_val <- auc(roc_obj)
legend("bottomright", legend = paste("AUC =", round(auc_val, 3)))

#### Multiclass ####

##### Plotting #####

df_selected <- df_multi %>% unnest(metrics) %>% filter(metric_type == "Aktiva")

df_selected %>% 
  filter(model %in% c(
    "mistralai_Ministral-8B-Instruct-2410", 
    "mistralai_Mistral-Large-Instruct-2411",
    "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
    "meta-llama_Llama-4-Scout-17B-16E-Instruct",
    "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8"
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
  ggplot(aes(x = norm_runtime, y = f1_score)) +
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
