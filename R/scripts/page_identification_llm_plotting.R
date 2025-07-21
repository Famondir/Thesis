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

df_binary %>% filter(classification_type == "Aktiva") %>% 
  filter(loop == 0) %>% 
  filter(n_examples <= 3 | is.na(n_examples)) %>% 
  ggplot(aes(x = norm_runtime, y = f1_score)) +
  # ggplot(aes(x = norm_runtime, y = recall)) +
  # ggplot(aes(x = norm_runtime, y = precision)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(classification_type~model) +
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
