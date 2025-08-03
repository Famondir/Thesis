library(tidyverse)

df_2_predictors_test <- read_csv("/home/simon/Documents/data_science/Thesis/benchmark_results/page_identification/term_frequency_results_2_predictors_test.csv") %>% 
  mutate(data_split = 'test', n_predictors = 2)
df_2_predictors_train <- read_csv("/home/simon/Documents/data_science/Thesis/benchmark_results/page_identification/term_frequency_results_2_predictors_train.csv") %>% 
  mutate(data_split = 'train', n_predictors = 2)
df_4_predictors_test <- read_csv("/home/simon/Documents/data_science/Thesis/benchmark_results/page_identification/term_frequency_results_4_predictors_test.csv") %>% 
  mutate(data_split = 'test', n_predictors = 4)
df_4_predictors_train <- read_csv("/home/simon/Documents/data_science/Thesis/benchmark_results/page_identification/term_frequency_results_4_predictors_train.csv") %>% 
  mutate(data_split = 'train', n_predictors = 4)

df_rf_results <- bind_rows(
  df_2_predictors_train, df_2_predictors_test,
  df_4_predictors_train, df_4_predictors_test
  )

max_rank = df_rf_results %>% filter(is_truth == 1) %>% pull(rank) %>% max()
results <- map_dfr(1:max_rank, function(i_rank) {
  df_rf_results %>% 
    filter(is_truth == 1) %>% 
    group_by(type, data_split, n_predictors) %>% 
    mutate(le = if_else(rank <= i_rank, 1, 0)) %>% 
    summarise(mean = mean(le), .groups = "drop") %>% 
    mutate(i_rank = i_rank)
})

library(ggh4x)

results %>% ggplot() +
  geom_col(aes(x = i_rank, y = mean)) +
  facet_nested(type ~ data_split + n_predictors) +
  labs(
    x = "rank",
    y = "top n accuracy",
    # title = "Top n accuracy for different ranks, data splits and number of predictors"
  )

# Auc ROC

df_temp <- df_rf_results %>% filter(n_predictors == 4, data_split == "test")
roc_obj <- roc(df_temp$is_truth ~ df_temp$score)
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

# PR ROC

library(PRROC)

# Calculate PR curve per "type"
pr_list <- df_temp %>%
  group_by(type) %>%
  group_map(~{
    pr.curve(
      scores.class0 = .x$score[.x$is_truth == 1],
      scores.class1 = .x$score[.x$is_truth == 0],
      curve = TRUE
    )
  })
pr_list[4] <- list(pr.curve(scores.class0 = df_temp$score[df_temp$is_truth == 1],
                                 scores.class1 = df_temp$score[df_temp$is_truth == 0],
                                 curve = TRUE))

# Extract PR curve data and combine into a tibble
pr_df <- map2_dfr(pr_list, unique(c(df_temp$type, 'micro')), ~{
  tibble(
    type = .y,
    recall = .x$curve[, 1],
    precision = .x$curve[, 2],
    threshold = .x$curve[, 3],
    pr_auc = round(.x$auc.integral, 3)
  )
}) %>%
  mutate(f1 = 2 * precision * recall / (precision + recall))

# Plot PR curves per type
# library(ggplot2)
# library(viridis)

# pr_df %>%
#   ggplot(aes(x = recall, y = precision, color = type)) +
#   geom_line(size = 1.2) +
#   labs(
#     title = "Precision-Recall Curve per type",
#     x = "Recall",
#     y = "Precision",
#     color = "Type"
#   ) +
#   coord_cartesian(ylim = c(0,1)) +
#   theme(legend.position = "bottom")

#

library(PRROC)
library(patchwork)

df_temp <- df_rf_results %>% filter(n_predictors == 4, data_split == "test")

pr_obj <- pr.curve(scores.class0 = df_temp$score[df_temp$is_truth == 1],
           scores.class1 = df_temp$score[df_temp$is_truth == 0],
           curve = TRUE)

# plot(pr_obj, color = "orange", main = "Precision-Recall Curve")
# ggprroc(pr_obj)

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
  coord_cartesian(ylim = c(0,1)) +
  theme(
    legend.position = "bottom"
  )

  g1 + g2
  