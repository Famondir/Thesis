library(jsonlite)
library(tidyverse)

#### Regex ####

json_files_table_extraction_regex <- list.files(
  "../benchmark_results/table_extraction/regex/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_table_extraction_regex) {
  # print(file)
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
  
  name_split = (basename(file) %>% str_remove(".json") %>% str_split("__"))[[1]]
  # method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = name_split[2],
      # model = name_split[1], 
      method = name_split[3],
      # n_examples = str_match(method, "\\d+")[[1]],
      # out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      # method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      # loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble())
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
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
  ) %>% mutate(
    filepath = if_else(filepath == "../../benchmark_truth/real_tables/Tempelhof Projekt GmbH __TP_Geschaeftsbericht_2020.xlsx", "../../benchmark_truth/real_tables/Tempelhof Projekt GmbH__TP_Geschaeftsbericht_2020.xlsx", filepath)
  )

units_real_tables <- read_csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% mutate(
  filepath = paste0('../../benchmark_truth/real_tables/', company, '__', str_replace(filename, '.pdf', '.xlsx')),
  T_EUR = (T_in_year + T_in_previous_year)>0
) %>% select(filepath, T_EUR)

df <- df %>% left_join(units_real_tables)

df %>% write_csv("data_storage/table_extraction_regex.rds")

##### plotting #####

df %>%
  select(c(model, percentage_correct_numeric, percentage_correct_total, T_EUR, method)) %>% 
  pivot_longer(cols = -c(model, T_EUR, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value, fill = method), alpha = .3) +
  geom_jitter(data= . %>% filter(model == "real_tables"), aes(x = model, y = value, color = T_EUR), alpha = .8, height = 0, shape = 4) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(~name)

df %>% select(c(model, NA_precision, NA_recall, NA_F1, T_EUR, method)) %>% 
  pivot_longer(cols = -c(model, T_EUR, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value, fill = method), alpha = .3) +
  geom_jitter(data= . %>% filter(model == "real_tables"), aes(x = model, y = value, color = T_EUR), alpha = .8, height = 0, shape = 4) +
  # facet_wrap(~name, ncol = 1) +
  scale_fill_manual(values = c("blue", "orange")) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(~name)

# df %>% ggplot() +
#   geom_boxplot(aes(x = model, y = deep_distance)) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) +
#   facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

##### modeling ######

###### Random Forest ######

unit_list = tribble(
  ~unit, ~multiplier,
  'EUR', 1, 
  '€', 1, 
  'Tsd. EUR', 1000, 
  'Mio. EUR', 1000000, 
  'TEUR', 1000, 
  'T€', 1000, 
  'Tsd. €', 1000, 
  'Mio. €', 1000000
)

df_synth <- df %>% 
  filter(model == "synth_tables") %>%
  mutate(
    n_columns = str_match(filepath, "(\\d)_columns")[,2],
    header_span = str_match(filepath, "span_(False|True)")[,2] == "True",
    thin = str_match(filepath, "thin_(False|True)")[,2] == "True",
    year_as = str_match(filepath, "year_as_(.*)__unit")[,2],
    unit_in_first_cell = str_match(filepath, "unit_in_first_cell_(False|True)")[,2] == "True",
    unit_str = str_match(filepath, "unit_in_first_cell_(False|True)__(.*)__enumeration")[,3],
    unit_multiplier = unit_list$multiplier[match(unit_str, unit_list$unit)],
    log_unit_multiplier = log(unit_multiplier),
    enumeration = str_match(filepath, "enumeration_(False|True)")[,2] == "True",
    shuffle_rows = str_match(filepath, "shuffle_(False|True)")[,2] == "True",
    text_around = str_match(filepath, "text_around_(False|True)")[,2] == "True",
    max_line_length = str_match(filepath, "max_length_(\\d+)")[,2],
    sum_same_line = str_match(filepath, "sum_in_same_row_(False|True)")[,2] == "True"
  ) %>% 
  mutate(
    n_columns = ordered(n_columns, c("3", "4", "5"))
  ) %>% mutate(
    many_line_breaks = if_else(max_line_length == 50, TRUE, FALSE)
  )

library(ranger)

# number of features
n_features <- 17-6

# train a default random forest model
forest0 <- ranger(
  percentage_correct_total ~ 
    # method_family +
    method +
    # n_examples +
    # model +
    n_columns + 
    sum_same_line +
    header_span +
    thin +
    # ignore_units +
    # input_format +
    year_as +
    # unit_in_first_cell +
    # unit_str +
    log_unit_multiplier +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks,
  data = df_synth,
  mtry = floor(n_features / 3),
  respect.unordered.factors = "order",
  seed = 123,
  importance = "permutation"
)

# get OOB RMSE
(default_rmse <- sqrt(forest0$prediction.error))

vip::vip(forest0, num_features = 10, bar = FALSE)

###### xgboost ######

library(xgboost)

# Prepare data for xgboost
library(Matrix)

# Select features and target
features <- df_synth %>% select(
  method,
  n_columns,
  sum_same_line,
  header_span,
  thin,
  unit_in_first_cell,
  year_as,
  log_unit_multiplier,
  enumeration,
  shuffle_rows,
  text_around,
  many_line_breaks
)

# Convert categorical variables to factors
features[] <- lapply(features, function(x) if(is.character(x) || is.logical(x)) as.factor(x) else x)

# Create model matrix (one-hot encoding for factors)
X_xgb <- model.matrix(~ . - 1, data = features)
y_xgb <- df_synth$percentage_correct_total

X_xgb <- model.matrix(
   ~ 
    # method_family +
    # n_examples +
    # model +
    method +
    n_columns +
    sum_same_line +
    header_span +
    thin +
    # ignore_units +
    # input_format +
    year_as +
    unit_in_first_cell +
    # unit_str +
    # unit_multiplier +
    log_unit_multiplier +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks - 1, 
  data = features)

X_xgb <- model.matrix(
  ~ 
    # method_family +
    # n_examples +
    # model_family +
    # model +
    method +
    # parameter_count +
    n_columns +
    n_columns:method +
    sum_same_line +
    sum_same_line:method +
    header_span +
    header_span:method +
    thin +
    # ignore_units +
    # ignore_units:input_format +
    # input_format +
    year_as +
    unit_in_first_cell +
    unit_in_first_cell:method +
    # unit_str +
    log_unit_multiplier +
    log_unit_multiplier:method +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks +
    many_line_breaks:method -1,
  data = features)

# Train xgboost regression model
# xgb_model <- xgboost(
#   data = X_xgb,
#   label = y_xgb,
#   nrounds = 100,
#   objective = "reg:squarederror",
#   verbose = 0,
#   seed = 123
# )

# Get feature importance
# vip::vip(xgb_model, num_features = 10)

library(shapviz)

fit <- xgb.train(
  params = list(learning_rate = 0.1, nthread = 1), 
  data = xgb.DMatrix(data.matrix(X_xgb), label = y_xgb, nthread = 1),
  nrounds = 65
)

# Calculate RMSE on training data
preds <- predict(fit, data.matrix(X_xgb))
rmse <- sqrt(mean((y_xgb - preds)^2))
print(rmse)

X_explain <- X_xgb[sample(nrow(X_xgb), 2000), ]
shp <- shapviz(fit, X_pred = data.matrix(X_explain), X = X_explain)

sv_importance(shp, show_numbers = TRUE)

sv_importance(shp, kind = "beeswarm")

# Compute SHAP values for the random forest model
sv_rf <- shapviz(xgb_model, X = X_explain,
  X_pred = data.matrix(X_explain)
)

# Beeswarm plot for SHAP values
plot(sv_rf, kind = "beeswarm")

###### lm ######

df_select <- df_synth %>% mutate(
  log10_unit_multiplier = log10(unit_multiplier),
  # logit_correct_total = percentage_correct_total %>% logit()
) %>% select(
  percentage_correct_total,
  # logit_correct_total,
  # method_family,
  method,
  # n_examples,
  # model,
  # parameter_count,
  # model_family,
  n_columns, 
  sum_same_line,
  header_span,
  thin,
  # ignore_units,
  # input_format,
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

lm0 <- lm(
  data = df_select,
  formula = percentage_correct_total ~ 
    # method_family +
    # n_examples +
    # model +
    method +
    n_columns +
    sum_same_line +
    header_span +
    thin +
    # ignore_units +
    # input_format +
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


lm1 <- lm(
  data = df_select,
  formula = percentage_correct_total ~ 
    # method_family +
    # n_examples +
    # model_family +
    # model +
    method +
    # parameter_count +
    n_columns +
    n_columns:method +
    sum_same_line +
    sum_same_line:method +
    header_span +
    header_span:method +
    thin +
    # ignore_units +
    # ignore_units:input_format +
    # input_format +
    year_as +
    unit_in_first_cell +
    unit_in_first_cell:method +
    # unit_str +
    log10_unit_multiplier +
    log10_unit_multiplier:method +
    enumeration +
    shuffle_rows +
    text_around +
    many_line_breaks +
    many_line_breaks:method
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