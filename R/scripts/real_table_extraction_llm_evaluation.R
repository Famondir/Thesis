library(jsonlite)
library(tidyverse)

units_real_tables <- read_csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% mutate(
  filepath = paste0('/pvc/benchmark_truth/real_tables/', company, '__', filename),
  T_EUR = (T_in_year + T_in_previous_year)>0,
  T_EUR_both = (T_in_year + T_in_previous_year)>1
) %>% select(filepath, T_EUR, T_EUR_both)

#### Final ####

df <- readRDS("data_storage/real_table_extraction_llm.rds")
df <- df %>% left_join(units_real_tables)

##### regression #####

table_characteristics <- read.csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% 
  mutate(
    filepath = paste0("/pvc/benchmark_truth/real_tables/", company, "__", filename)
  ) %>% as_tibble()

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  ) %>% filter(str_detect(filename, "multi"))
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml") | str_ends(filename, "vllm_batched.yaml")))
norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
  add_column(n_examples = list(c(7,9,11,13), c(5))) %>% unnest(n_examples)

df_characteristics <- df %>% rowwise() %>% mutate(
  mean_tokens = mean(request_tokens[[1]])
) %>% 
  select(
    filepath, 
    method_family, model_family, 
    percentage_correct_total, 
    n_examples, 
    model, method,
    mean_tokens
  ) %>% 
  left_join(table_characteristics, by = "filepath")

df_characteristics <- df_characteristics %>% filter(n_examples <= 5) %>% 
  left_join(
    norm_factors_few_examples %>% select(model_name, parameter_count), 
    by = c("model" = "model_name")
  )

lm0 <- lm(
  data = df_characteristics,
  formula = percentage_correct_total ~ 
    method_family +
    model_family +
    n_examples +
    # mean_tokens +
    parameter_count +
    parameter_count:model_family +
    n_columns + 
    T_in_previous_year + 
    T_in_year + 
    sum_same_line + 
    passiva_same_page +
    spacer +
    vorjahr +
    header_span
)
summary(lm0)

# df_characteristics %>% select(is.numeric) %>% colMeans(na.rm= TRUE)

backward <- step(lm0, direction = "backward", trace = 0)

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

##### plotting #####

library(ggh4x)

model_by_size <- c(
  'google_gemma-3-4b-it', 'google_gemma-3n-E4B-it', "google_gemma-3-12b-it",
  "google_gemma-3-27b-it", "meta-llama_Llama-3.1-8B-Instruct", 
  "meta-llama_Llama-3.1-70B-Instruct", "meta-llama_Llama-3.3-70B-Instruct",
  "meta-llama_Llama-4-Scout-17B-16E-Instruct", "meta-llama_Llama-4-Maverick-17B-128E-Instruct-FP8",
  "mistralai_Ministral-8B-Instruct-2410", "mistralai_Mistral-Small-3.1-24B-Instruct-2503",
  "mistralai_Mistral-Large-Instruct-2411", "Qwen_Qwen2.5-0.5B-Instruct",
  "Qwen_Qwen2.5-1.5B-Instruct", "Qwen_Qwen2.5-3B-Instruct", "Qwen_Qwen2.5-7B-Instruct",
  "Qwen_Qwen2.5-14B-Instruct", "Qwen_Qwen2.5-32B-Instruct", "Qwen_Qwen2.5-72B-Instruct",
  "Qwen_Qwen3-0.6B", "Qwen_Qwen3-1.7B", "Qwen_Qwen3-4B",
  "Qwen_Qwen3-8B", "Qwen_Qwen3-14B", "Qwen_Qwen3-30B-A3B-Instruct-2507", "Qwen_Qwen3-32B", "Qwen_Qwen3-235B-A22B-Instruct-2507",
  "gpt-4.1-nano", "gpt-4.1-mini", "gpt-4.1",
  "tiiuae_Falcon3-10B-Instruct", "microsoft_phi-4"
)

method_order <- c("top_n_rag_examples", "n_random_examples", "top_n_rag_examples_out_of_sample", "static_example", "zero_shot" )

bind_rows(df, df_azure %>% filter(!str_detect(model, "azure"))) %>% 
  filter(str_detect(filepath, "Statistik"), method_family == "top_n_rag_examples") %>% 
  # select(c(model, method, percentage_correct_numeric, percentage_correct_total, model_family, method_family)) %>% 
  filter(model %in% model_by_size) %>%
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  # pivot_longer(cols = -c(model, method, model_family)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = percentage_correct_total, fill = model_family)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family + n_examples ~ out_of_company) +
  theme(
    legend.position = "bottom"
  )

bind_rows(df, df_azure %>% filter(!str_detect(model, "azure"))) %>% 
  filter(out_of_company != TRUE | is.na(out_of_company), n_examples <= 3) %>% 
  # select(c(model, method, percentage_correct_numeric, percentage_correct_total, model_family, method_family)) %>% 
  filter(model %in% model_by_size) %>%
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
    ) %>% 
  # pivot_longer(cols = -c(model, method, model_family)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = percentage_correct_total, fill = model_family)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family + n_examples ~ .)

bind_rows(df, df_azure %>% filter(!str_detect(model, "azure"))) %>% 
  filter(out_of_company != TRUE) %>% 
  select(c(model, method, percentage_correct_numeric, percentage_correct_total, model_family)) %>% 
  filter(model %in% model_by_size) %>% 
  mutate(model = factor(model, levels = model_by_size)) %>% 
  # pivot_longer(cols = -c(model, method, model_family)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = percentage_correct_numeric, fill = model_family)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% filter(out_of_company != TRUE) %>% 
  select(c(model, method, percentage_correct_numeric, percentage_correct_total, model_family, T_EUR)) %>% 
  filter(model %in% c("mistralai_Ministral-8B-Instruct-2410")) %>% 
  mutate(
    model = factor(model, levels = model_by_size)
  ) %>% 
  pivot_longer(cols = -c(model, method, model_family, T_EUR)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  geom_jitter(aes(x = model, y = value, color = T_EUR), alpha = .5) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

bind_rows(df, df_azure %>% filter(!str_detect(model, "azure"))) %>% 
  filter(out_of_company != TRUE) %>% 
  select(c(model, method, NA_F1, model_family)) %>% 
  filter(model %in% model_by_size) %>% 
  mutate(model = factor(model, levels = model_by_size)) %>% 
  # pivot_longer(cols = -c(model, method, model_family)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = NA_F1, fill = model_family)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
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

###### confidence ######

confidence_vs_truth <- df %>% 
  # filter(model == "Qwen_Qwen3-8B") %>% 
  filter(model == "mistralai_Ministral-8B-Instruct-2410") %>% 
  group_by(method, model) %>% mutate(
    mean_percentage_correct_total = mean(percentage_correct_total, na.rm=TRUE), .before = 1
    ) %>% ungroup() %>% 
  arrange(desc(mean_percentage_correct_total)) %>% 
  slice_max(mean_percentage_correct_total, n = 1, with_ties = TRUE) %>% 
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

confidence_vs_truth %>% ggplot() +
  geom_boxplot(
    aes(x = match, y = confidence, fill = truth_NA), 
    position = position_dodge2(preserve = "single")) +
  scale_fill_discrete(drop = FALSE) +
  scale_x_discrete(drop = FALSE)# +
  # coord_cartesian(ylim = c(0.95, 1))
  # geom_jitter(aes(x = match, y = confidence))

# confidence_vs_truth %>%
#   mutate(conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.01), include.lowest = TRUE)) %>%
#   group_by(conf_interval, predicted_NA) %>%
#   summarize(
#     n_true = sum(match == TRUE, na.rm = TRUE),
#     n_false = sum(match == FALSE, na.rm = TRUE),
#     total = n_true + n_false,
#     chance_false = if_else(total > 0, n_false / total * 100, NA_real_)
#   ) %>% tail(20)

confidence_vs_truth %>%
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.005
  ) %>%
  group_by(conf_center, predicted_NA) %>%
  summarize(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    .groups = "drop"
  ) %>%
  ggplot(aes(x = conf_center, y = chance_false, color = predicted_NA)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(x = "Confidence Interval Center", y = "Chance False (%)", color = "Predicted NA") +
  coord_cartesian(ylim = c(0, 100), xlim = c(0,1))

#### Synth Context ####

df_synth <- readRDS("data_storage/real_table_extraction_synth.rds")
df_synth <- df_synth %>% left_join(units_real_tables)

##### plotting #####

bind_rows(
  df_synth %>% mutate(context = "synth"), 
  df %>% mutate(context = "real")
  ) %>% 
  filter(model %in% c("Qwen_Qwen3-8B","mistralai_Ministral-8B-Instruct-2410")) %>% 
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  ggplot() +
  geom_boxplot(aes(x = 1,, fill=context, y = percentage_correct_total), alpha = .3) +
  # geom_jitter(
  #   data = . %>% filter(n_col_T_EUR > 0), 
  #   aes(x = 1, group=ignore_units, color = factor(n_col_T_EUR), y = percentage_correct_total), 
  #   height = 0, alpha = .5, width = 0.3
  # ) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~model)

df_synth %>% 
  # select(c(
  # model, method, percentage_correct_numeric, percentage_correct_total, ignore_units,
  # T_EUR, T_EUR_both)) %>% 
  # pivot_longer(cols = -c(model, method, ignore_units, T_EUR, T_EUR_both)) %>% 
  mutate(n_col_T_EUR = T_EUR_both + T_EUR) %>% 
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  ggplot() +
  geom_boxplot(aes(x = 1, fill=ignore_units, y = percentage_correct_total), alpha = .3) +
  geom_jitter(
    data = . %>% filter(n_col_T_EUR > 0), 
    aes(x = 1, group=ignore_units, color = factor(n_col_T_EUR), y = percentage_correct_total), 
    height = 0, alpha = .5, width = 0.3
    ) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~model+ignore_units)
  # facet_grid(method~name)

df_synth %>% 
  # select(c(
  # model, method, percentage_correct_numeric, percentage_correct_total, ignore_units,
  # T_EUR, T_EUR_both)) %>% 
  # pivot_longer(cols = -c(model, method, ignore_units, T_EUR, T_EUR_both)) %>% 
  mutate(n_col_T_EUR = T_EUR_both + T_EUR) %>% 
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  ggplot() +
  geom_boxplot(aes(x = 1, fill=ignore_units, y = percentage_correct_numeric), alpha = .3) +
  geom_jitter(
    data = . %>% filter(n_col_T_EUR > 0), 
    aes(x = 1, group=ignore_units, color = factor(n_col_T_EUR), y = percentage_correct_numeric), 
    height = 0, alpha = .5, width = 0.3
  ) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~model+ignore_units)
# facet_grid(method~name)

df_synth %>% 
  # select(c(
  # model, method, percentage_correct_numeric, percentage_correct_total, ignore_units,
  # T_EUR, T_EUR_both)) %>% 
  # pivot_longer(cols = -c(model, method, ignore_units, T_EUR, T_EUR_both)) %>% 
  mutate(n_col_T_EUR = T_EUR_both + T_EUR) %>% 
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  ) %>% 
  ggplot() +
  geom_boxplot(aes(x = 1, fill=ignore_units, y = NA_F1), alpha = .3) +
  geom_jitter(
    data = . %>% filter(n_col_T_EUR > 0), 
    aes(x = 1, group=ignore_units, color = factor(n_col_T_EUR), y = NA_F1), 
    height = 0, alpha = .5, width = 0.3
  ) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~model+ignore_units)
# facet_grid(method~name)

df_synth %>% select(c(model, method, NA_precision, NA_recall, NA_F1, ignore_units)) %>% 
  pivot_longer(cols = -c(model, method, ignore_units)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=ignore_units, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

df_synth %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df_synth %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df_synth %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df_synth %>% ggplot() +
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

###### confidence ######

confidence_vs_truth <- df_synth %>% 
  # filter(model == "Qwen_Qwen3-8B") %>% 
  filter(model == "mistralai_Ministral-8B-Instruct-2410") %>% 
  group_by(method, model) %>% mutate(
    mean_percentage_correct_total = mean(percentage_correct_total, na.rm=TRUE), .before = 1
  ) %>% group_by(ignore_units) %>% 
  arrange(desc(mean_percentage_correct_total)) %>% 
  slice_max(mean_percentage_correct_total, n = 1, with_ties = TRUE) %>% 
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

confidence_vs_truth %>% ggplot() +
  geom_boxplot(
    aes(x = match, y = confidence, fill = truth_NA), 
    position = position_dodge2(preserve = "single")) +
  scale_fill_discrete(drop = FALSE) +
  scale_x_discrete(drop = FALSE) +
  facet_wrap(~ignore_units) # +
# coord_cartesian(ylim = c(0.95, 1))
# geom_jitter(aes(x = match, y = confidence))

# confidence_vs_truth %>%
#   mutate(conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.01), include.lowest = TRUE)) %>%
#   group_by(conf_interval, predicted_NA) %>%
#   summarize(
#     n_true = sum(match == TRUE, na.rm = TRUE),
#     n_false = sum(match == FALSE, na.rm = TRUE),
#     total = n_true + n_false,
#     chance_false = if_else(total > 0, n_false / total * 100, NA_real_)
#   ) %>% tail(20)

confidence_vs_truth %>%
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.005
  ) %>%
  group_by(conf_center, predicted_NA, ignore_units) %>%
  summarize(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    .groups = "drop"
  ) %>%
  ggplot(aes(x = conf_center, y = chance_false, color = predicted_NA)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(x = "Confidence Interval Center", y = "Chance False (%)", color = "Predicted NA") +
  coord_cartesian(ylim = c(0, 100), xlim = c(0,1)) +
  facet_wrap(~ignore_units)

##### regression #####

lm1 <- lm(
  data = df_characteristics,
  formula = percentage_correct_total ~ 
    method +
    model +
    n_columns + 
    T_in_previous_year + 
    T_in_year + 
    sum_same_line + 
    passiva_same_page +
    spacer +
    vorjahr +
    header_span
)
summary(lm1)

df_characteristics %>% select(is.numeric) %>% colMeans(na.rm= TRUE)

#### Azure ####

df_azure <- readRDS("data_storage/real_table_extraction_azure.rds")

##### plotting #####

df_azure %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total)) %>%
  pivot_longer(cols = -c(model, method)) %>%
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

# df_azure %>% select(c(model, method, NA_precision, NA_recall, NA_F1)) %>% 
#   pivot_longer(cols = -c(model, method)) %>% 
#   ggplot() +
#   geom_boxplot(aes(x = model, y = value)) +
#   # facet_wrap(~name, ncol = 1) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) +
#   facet_grid(name~method)
# 
# # df_azure %>% ggplot() +
# #   geom_boxplot(aes(x = model, y = deep_distance)) +
# #   scale_x_discrete(guide = guide_axis(angle = 30)) +
# #   facet_grid(method~1)
# 
# df_azure %>% ggplot() +
#   geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) +
#   coord_cartesian(ylim = c(0, 1500)) +
#   facet_grid(method~1)
# 
# df_azure %>% ggplot() +
#   geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) +
#   coord_cartesian(ylim = c(0, 1)) +
#   facet_grid(method~1)
# 
# df_azure %>% ggplot() +
#   geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
#   facet_grid(method~1)


costs_azure <- read_csv("../CostManagement_master-thesis_2025.csv")

token_prop <- df %>% group_by(model, method, n_examples) %>% summarize(
  request_tokens_total = sum(request_tokens[[1]])) %>% 
  group_by(method, n_examples) %>% 
  summarize(mean = mean(request_tokens_total, na.rm = TRUE)) %>% mutate(five_examples = n_examples == 5) %>% group_by(five_examples) %>% summarise(sum = sum(mean))

five_ex_tokens <- token_prop %>% filter(five_examples == TRUE) %>% pull(sum)
other_tokens <- token_prop %>% filter(five_examples == FALSE) %>% pull(sum)

costs_azure %>% mutate(
  Cost_all_tasks = Cost,
  Cost_all_tasks = if_else(Meter == "gpt 4.1 Inp glbl Tokens", Cost_all_tasks+Cost_all_tasks*five_ex_tokens/other_tokens, Cost_all_tasks),
  Cost_all_tasks = if_else(Meter == "gpt 4.1 Outp glbl Tokens", Cost_all_tasks+Cost_all_tasks*3/11, Cost_all_tasks)
)
