render_table <- function(
  df, 
  alignment = NULL, 
  caption = NULL, 
  ref = NULL, 
  dom = "tiprfl",
  row_groups = NULL,      # For LaTeX: list(name, start, end, ...)
  row_group_col = NULL,    # For HTML/DT: column index or name to group by
  colgroups = NULL,
  force_kable = FALSE
) {
  output_HTML <- if_else(force_kable, FALSE, knitr::is_html_output())
  output_LaTeX <- if_else(force_kable, TRUE, knitr::is_latex_output())

  latex_sub <- "([%&_#{}])"

  # Replace **x** with <b>x</b> for HTML and \textbf{x} for LaTeX
  if (output_HTML) {
    df <- df %>%
      mutate_all(~ gsub("\\*\\*(.*?)\\*\\*", "<b>\\1</b>", .))
  } else if (output_LaTeX) {
    df <- df %>%
      mutate_all(~ gsub(latex_sub, "\\\\\\1", .)) %>% # Escape LaTeX special characters
      mutate_all(~ gsub("\\*\\*(.*?)\\*\\*", "\\\\textbf{\\1}", .))
  } else {
    df <- df
  }
  
  # Helper to convert knitr alignment to DT alignment
  get_dt_align <- function(align) {
    sapply(strsplit(paste0("l", align), "")[[1]], function(x) {
      switch(x, l = 'left', c = 'center', r = 'right', 'left')
    })
  }
  
  if (!output_HTML) {
    latex_sub <- "([%&_#{}-])"
    
    # Escape special characters in the caption for LaTeX
    if (!is.null(caption) && output_LaTeX) {
      caption <- gsub(latex_sub, "\\\\\\1", caption) # Escape LaTeX special characters
    }
  
    df <- df %>%
      setNames(gsub(latex_sub, "\\\\\\1", colnames(.))
    ) # Escape LaTeX special characters in column names
  }

  if (output_HTML) {
    sketch = NULL

    # If colgroups provided, create a sketch with the colgroups
    if(!is.null(colgroups)) {
      # Expand the " " entry by its value, keep other named entries as is
      if (" " %in% names(colgroups)) {
        # Replace the " " entry with the appropriate number of columns, using names from colnames(df)
        n_blank <- colgroups[" "]+if_else(is.null(row_group_col), 0 , 1)
        blank_names <- colnames(df)[seq_len(n_blank)]
        other_names <- names(colgroups)[names(colgroups) != " "]
        colgroups <- c(setNames(rep(1, n_blank), blank_names), colgroups[other_names])
        skipped_names <- colnames(df)[-(seq_along(blank_names))]
      }
      
      sketch = htmltools::withTags(table(
        class = 'display',
        thead(
            tr(
                lapply(seq_along(colgroups), function(i) {
                  th(colspan = unname(colgroups)[i], names(colgroups)[i], rowspan = if_else(unname(colgroups)[i] == 1, 2, 1))
                })
            ),
            tr(
                lapply(skipped_names, th)
            )
        )
      ))
    }

    # Set caption
    if (!is.null(caption) & !is.null(ref)) {
      cat("<table>",paste0("<caption>", "(#tab:", ref, ")", caption, "</caption>"),"</table>", sep ="\n")
    }
    
    df <- df %>% mutate(across(where(is.character), ~str_replace_all(., "_", "_<wbr>"))) %>% 
      setNames(str_replace_all(colnames(.), "_", " "))
    
    dt_options <- list(pageLength = 10, scrollX = TRUE, dom = dom)
    dt_extensions <- NULL
    if (!is.null(row_group_col)) {
      # If column name, get index
      if (is.character(row_group_col)) {
        col_idx <- which(names(df) == row_group_col)
      } else {
        col_idx <- row_group_col
      }
      col_idx <- col_idx-if_else(is.null(colgroups), 0 , 1)
      dt_options$rowGroup <- list(dataSrc = col_idx)
      dt_options$ordering <- FALSE
      dt_options$columnDefs <- list(list(visible = FALSE, targets = col_idx))
      dt_extensions <- 'RowGroup'
    }
    if (!is.null(alignment)) {
      dt_align <- get_dt_align(alignment)
      col_defs <- lapply(seq_along(dt_align), function(i) {
        list(targets = i - 1, className = paste0('dt-', dt_align[i]))
      })
      dt_options$columnDefs <- c(dt_options$columnDefs, col_defs)
    }
    # If no colgroups, just use default datatable
    if (is.null(sketch)) {
      datatable(df, escape = FALSE, options = dt_options, extensions = if (is.null(dt_extensions)) character(0) else dt_extensions)
    } else {
      datatable(df, escape = FALSE, options = dt_options, extensions = if (is.null(dt_extensions)) character(0) else dt_extensions, container = sketch, rownames = FALSE)
    }
  } else if (output_LaTeX) {
    # Hide the row_group_col column if specified (by name or index)
    if (!is.null(row_group_col)) {
      generate_row_groups <- function(df, row_group_col, css = "background-color: #666; color: #fff;") {
        # Get the column index if a name is given
        if (is.character(row_group_col)) {
          col_idx <- which(names(df) == row_group_col)
        } else {
          col_idx <- row_group_col
        }
        group_vals <- df[[col_idx]]
        rle_groups <- rle(as.character(group_vals))
        ends <- cumsum(rle_groups$lengths)
        starts <- c(1, head(ends + 1, -1))
        mapply(function(name, start, end) {
          list(name = name, start = start, end = end, css = css)
        }, rle_groups$values, starts, ends, SIMPLIFY = FALSE)
      }

      col_idx <- if (is.character(row_group_col)) {
        which(names(df) == row_group_col)
      } else {
        row_group_col
      }
      row_groups <- generate_row_groups(df, row_group_col = col_idx)
      df <- df %>% ungroup() %>% select(-col_idx)
    }
    kbl_out <- kbl(
      df, escape = FALSE, format = if_else(knitr::is_latex_output(), "latex", "html"), align = alignment, caption = caption, booktabs = T
    ) %>% kable_styling(latex_options = "striped")
    if (!is.null(row_groups)) {
      for (grp in row_groups) {
        kbl_out <- kbl_out %>% pack_rows(grp$name, grp$start, grp$end, label_row_css = grp$css)
      }
    }
    if (!is.null(colgroups)) {
      kbl_out <- kbl_out %>% add_header_above(colgroups)
    }
    kbl_out
  } else {
    knitr::kable(df, align = alignment)
  }
}

bold_value_in_table <- function(df) {
  latex_sub <- "([%&_#{}])"

  # Replace **x** with <b>x</b> for HTML and \textbf{x} for LaTeX
  if (knitr::is_html_output()) {
    df <- df %>%
      mutate_all(~ gsub("\\*\\*(.*?)\\*\\*", "<b>\\1</b>", .))
  } else if (knitr::is_latex_output()) {
    df <- df %>%
      mutate_all(~ gsub(latex_sub, "\\\\\\1", .)) %>% # Escape LaTeX special characters
      mutate_all(~ gsub("\\*\\*(.*?)\\*\\*", "\\\\textbf{\\1}", .))
  } else {
    df <- df
  }
}

create_hypotheses_table <- function(html_path, caption, detect="\\*$") {
  pd <- import("pandas")
  df_two_header_lines <- pd$read_html(html_path, header = 1L)[[1]]

  library(xml2)
  library(rvest)
  library(dplyr)
  library(purrr)
  library(tibble)
  
  html_table <- xml2::read_html(html_path) %>%
    xml2::xml_find_first("//table")
  
  # Get all rows
  rows <- xml_find_all(html_table, ".//tr")
  
  # Skip first two rows (header)
  data_rows <- rows[-c(1,2)]
  
  # Helper to extract info from a cell
  extract_cell_info <- function(cell) {
    # Check for bold (either <b> or <strong> or style)
    is_bold <- length(xml_find_all(cell, ".//b | .//strong")) > 0 ||
      grepl("font-weight:\\s*bold", xml_attr(cell, "style") %||% "", ignore.case = TRUE)
    # Get text color from style attribute
    style <- xml_attr(cell, "style") %||% ""
    color <- NA_character_
    # Try to get color from <font> tag first
    font_tag <- xml_find_first(cell, ".//font[@color]")
    if (!is.na(font_tag) && length(font_tag) > 0) {
      color <- xml_attr(font_tag, "color")
    } else if (grepl("color:", style)) {
      color <- sub(".*color:\\s*([^;]+);?.*", "\\1", style)
    }
    color <- trimws(color)
    # Get text content
    text <- xml_text(cell, trim = TRUE)
    tibble(text = text, bold = is_bold, color = color)
  }
  
  # Build matrix/list of cell info
  cell_info_list <- map(data_rows, function(row) {
    cells <- xml_find_all(row, ".//td|.//th")
    map_dfr(cells, extract_cell_info)
  })

    
  # Find which cells are bold (excluding the first column)
  bold_matrix <- sapply(cell_info_list, function(row) row$bold) %>% t()
  # Set first column to FALSE (never bold)
  if (is.matrix(bold_matrix)) {
    bold_matrix[, 1] <- FALSE
  } else {
    # If only one row, ensure it's a matrix
    bold_matrix[1] <- FALSE
  }
  df_bold <- bold_matrix %>% as.data.frame()
  
  df_red <- sapply(cell_info_list, function(row) row$color) %>% t() %>% 
    as.data.frame()
  
  n_cols <- ncol(df_two_header_lines)
  df_to_display <- df_two_header_lines
  df_to_display <- pmap(
    list(df_to_display, df_bold, df_red), 
    function(text, bold, color) {
      if_else(
        !is.na(color), 
        cell_spec(if_else(is.na(text), "", text), bold = bold, color = "darkred"),
        cell_spec(if_else(is.na(text), "", text), bold = bold)
      )}) %>% 
    as_tibble() %>% setNames(colnames(.) %>% str_remove(".\\d"))
  
  # browser()
  
  header_span <- if_else(n_cols == 7, list(c(
    " " = 1, "F1" = 2, "% correct numeric" = 2, 
    "binomial" = 2
  )), list(c(
    " " = 1, "F1" = 2, "% correct numeric" = 2, 
    "binomial" = 2, "confidence" = 2
  )))
  
  df_to_display <- df_to_display %>% 
    kbl(escape = F, booktabs = T, caption = caption) %>%
    kable_paper() %>%
    add_header_above(header_span[[1]]) %>%
    column_spec(1, border_right=T) %>%
    column_spec(3, border_right=T) %>%
    column_spec(5, border_right=T) %>%
    row_spec(
      which(str_detect(df_two_header_lines[[1]], detect)),
      color = "gray"
    )  
  
  if (n_cols == 9) {
    df_to_display <- df_to_display %>% 
      column_spec(7, border_right=T)
  }
  
  df_to_display
}

