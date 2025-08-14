library(tidyverse)
library(jsonlite)

# Initialize a counter for the total page count
page_list <- list()

# Get the list of PDF files in the specified directory
pdf_files <- list.files(path = "../Geschaeftsberichte", pattern = "\\.pdf$", full.names = TRUE, recursive = TRUE)

# Loop through each PDF file to count pages
for (pdf_file in pdf_files) {
  path_split <- str_split(pdf_file, "/")[[1]]
  
  # Use the pdftools package to count pages
  page_list[[pdf_file]] <- list(filepath = pdf_file, company = path_split[length(path_split)-1], file_name = path_split[length(path_split)], pages = pdftools::pdf_info(pdf_file)$pages)
}

df_pages <- bind_rows(page_list)

# Read the CSV file
df_targets_no_ocr <- read.csv("../benchmark_truth/aktiva_passiva_guv_table_pages_no_ocr.csv")

df_pages <- df_pages %>% mutate(needs_ocr = !filepath %in% df_targets_no_ocr$filepath) %>% select(-filepath)

# Get the unique count of document paths in the "filepath" column
num_documents <- nrow(df_pages %>% filter(!needs_ocr))
total_pages <- sum(df_pages$pages)
total_pages_no_ocr <- df_pages %>% filter(!needs_ocr) %>% pull(pages) %>% sum()
num_target_pages <- df_targets_no_ocr %>% nrow()
num_companies <- df_pages$company %>% unique() %>% length

# Split the "type" column by '&' and explode it into multiple rows
data_unnested <- df_targets_no_ocr %>%
  mutate(type = strsplit(as.character(type), "&")) %>%
  unnest(type)

num_tables <- data_unnested %>% nrow()

num_two_tables_on_one_page <- df_targets_no_ocr %>% filter(type == 'Aktiva&Passiva') %>% 
  nrow()

# Count rows where the next row is identical in all columns except "page",
# and the "page" of the second row is equal to "page + 1" of the first row
consecutive_pages <- df_targets_no_ocr %>%
  arrange(filepath, page) %>%
  group_by(filepath) %>%
  mutate(next_page = lead(page), next_type = lead(type)) %>%
  filter(
    next_page == page + 1 &
      next_type == type
  )

num_consecutive_pages <- consecutive_pages %>%
  nrow()