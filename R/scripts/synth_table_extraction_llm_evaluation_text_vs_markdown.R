df  <-  read_csv("data_storage/synth_table_extraction_llm.rds")

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  ) %>% filter(str_detect(filename, "multi"))
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml")))
norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
  add_column(n_examples = list(c(7,9,11,13), c(5))) %>% unnest(n_examples)

df2 <- df %>% filter(n_examples <= 5) %>% 
  left_join(
    norm_factors_few_examples %>% select(model_name, parameter_count), 
    by = c("model" = "model_name")
    )

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

##### regression #####

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
    # model +
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

##### Random Forest #####

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

##### xgboost #####

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

##### Plotting ######

df %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total, ignore_units, input_format)) %>% 
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

#### Synth ####

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
