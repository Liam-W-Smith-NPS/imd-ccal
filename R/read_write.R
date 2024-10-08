#' Read CCAL Data
#'
#' @param files Path to .xlsx file delivered by CCAL. Use a character vector to specify multiple files.
#'
#' @return A nested list. Each list item corresponds to one input file and contains data frames for data and metadata.
#' @export
#'
#' @examples
#' \dontrun{
#' my_folder <- "ccal_results"
#' file_list <- list.files(my_folder, pattern = "*.xlsx$", full.names = TRUE)
#' all_ccal_data <- getCCALData(file_list)
#'}
getCCALData <- function(files) {
  data <- purrr::map(files, function(file) {

    cli::cli_progress_message("Reading data from {file}...")

    # Read in all spreadsheet data
    xl_all <- tidyxl::xlsx_cells(file)
    xl_meta <- dplyr::filter(xl_all, grepl("information", sheet, ignore.case = TRUE))
    xl_data <- dplyr::filter(xl_all, grepl("data", sheet, ignore.case = TRUE))

    # Get cell locations of metadata on info tab of spreadsheet
    quest_results_title <- xl_meta[grepl("Explanation of Questionable Results", xl_meta$character, ignore.case = TRUE), ]
    quest_results_row <- quest_results_title$row
    quest_results_col <- quest_results_title$col

    analyses_title <- xl_meta[grepl("Analyses requested:", xl_meta$character, ignore.case = TRUE), ]
    analyses_row <- analyses_title$row + 1
    analyses_col <- analyses_title$col
    analyses_requested <- xl_meta$character[xl_meta$row == analyses_row & xl_meta$col == analyses_col]

    misc_charges_title <- xl_meta[grepl("Miscellaneous charges:", xl_meta$character, ignore.case = TRUE), ]
    comments_title <- xl_meta[grepl("Comments:", xl_meta$character, ignore.case = TRUE), ]
    other_charges_title <- xl_meta[grepl("Other charges:", xl_meta$character, ignore.case = TRUE), ]
    sample_table_header <- xl_meta[grepl("Lab\\s*#*:", xl_meta$character, ignore.case = TRUE), ]

    # Extract "miscellaneous charges"
    misc_chg_row_start <- misc_charges_title$row + 1
    misc_chg_row_end <- comments_title$row - 1
    misc_chg_col <- misc_charges_title$col
    misc_charges <- xl_meta$character[xl_meta$row %in% misc_chg_row_start:misc_chg_row_end & xl_meta$col == misc_chg_col]
    misc_charges <- paste(misc_charges[!is.na(misc_charges)], collapse = "; ")

    # Extract "comments"
    comments_row_start <- comments_title$row + 1
    comments_row_end <- other_charges_title$row - 1
    comments_col <- comments_title$col
    comments <- xl_meta$character[xl_meta$row %in% comments_row_start:comments_row_end & xl_meta$col == comments_col]
    comments <- paste(comments[!is.na(comments)], collapse = "; ")

    # Extract "other charges"
    oth_chg_row_start <- other_charges_title$row + 1
    oth_chg_row_end <- other_charges_title$row - 1
    oth_chg_col <- other_charges_title$col
    other_charges <- xl_meta$character[xl_meta$row %in% oth_chg_row_start:oth_chg_row_end & xl_meta$col == oth_chg_col]
    other_charges <- paste(other_charges[!is.na(other_charges)], collapse = "; ")

    # Extract sample table
    sample_header_start <- xl_meta[grepl("^Lab\\s*#$", xl_meta$character, ignore.case = TRUE), ]
    sample_header_end <- xl_meta[grepl("^#FB$", xl_meta$character, ignore.case = TRUE), ]
    sample_row_start <- sample_header_start$row
    sample_row_end <- quest_results_row - 1
    sample_col_start <- sample_header_start$col
    sample_col_end <- sample_header_end$col
    range <- paste0("R", sample_row_start, "C", sample_col_start, ":R", sample_row_end, "C", sample_col_end)
    sample_table <- readxl::read_excel(file, sheet = 1, range = range, col_names = TRUE) %>%
      janitor::remove_empty(c("rows", "cols")) %>%
      janitor::clean_names()


    # Extract questionable results
    quest_results <- xl_meta %>%
      dplyr::select(sheet, address, row, col, is_blank, character) %>%
      dplyr::filter(row > quest_results_row, col == quest_results_col, character != "", !is.na(character)) %>%
      dplyr::select(character) %>%
      dplyr::mutate(lab_number = stringr::str_extract(character, "#[^(is)]* is "),
                    lab_number = trimws(stringr::str_replace_all(lab_number, "(#|,|&|(is))", "")),
                    lab_number = stringr::str_replace_all(lab_number, "[ \t\r\n]+", " "),
                    param_description = stringr::str_extract(character, "Concentration of .* for sample"),
                    param_description = trimws(stringr::str_replace_all(param_description, "(Concentration of )|( for sample)", "")),
                    comparison = stringr::str_extract(character, "Concentration of [^\\.]*\\."),
                    assessment = stringr::str_extract(character, "((Analytical results)|(Results)) fall.*"),
                    within_precision_limits = grepl("(R|r)esults fall within precision", character),
                    orig_text = character) %>%
      dplyr::select(-character)

    quest_results$lab_number <- rangeToVector(quest_results$lab_number)
    quest_results <- tidyr::separate_longer_delim(quest_results, lab_number, delim = " ")

    # Create data frame for metadata
    metadata <- xl_meta %>%
      dplyr::select(character) %>%
      dplyr::filter(grepl("(Investigator:)|(Delivery date:)|(Sample Location:)|(Sample Numbers:)|(Project Code:)|(File Number:)", character)) %>%
      tidyr::separate(character, c("meta", "value"), sep = ": ") %>%
      dplyr::mutate(meta = janitor::make_clean_names(meta)) %>%
      tidyr::pivot_wider(names_from = meta, values_from = value)
    metadata$analyses_requested <- analyses_requested
    metadata$misc_charges <- misc_charges
    metadata$other_charges <- other_charges
    metadata$comments <- comments

    # Get questionable results that apply to specific samples
    questionable <- dplyr::filter(quest_results, !(is.na(lab_number) | is.null(lab_number))) %>%
      dplyr::mutate(parameter = getParamCrosswalk(param_description))

    # Get additional questionable results comments that aren't tied to specific sample numbers and put them in the metadata
    extra_comments <- dplyr::filter(quest_results, is.na(lab_number) | is.null(lab_number))
    extra_comments <- paste(extra_comments$orig_text, collapse = "; ")
    metadata$quest_results_comments <- extra_comments

    # Extract chem results
    data <- suppressMessages(readxl::read_excel(file, sheet = 2, skip = 3, col_names = TRUE))
    first_chem_col <- max(grep("delivery\\s*date", names(data), ignore.case = TRUE), grep("date\\s*filtered", names(data), ignore.case = TRUE)) + 1  # Get index of first chem data column
    last_date_col <- max(grep("^date(\\.\\.\\.\\d+){0,1}$", names(data), ignore.case = TRUE))
    names(data) <- trimws(names(data))
    data <- data %>%
      tidyr::pivot_longer(first_chem_col:last_date_col, names_to = "param") %>%
      tidyr::separate(param, c("parameter", "unit"), sep = "\\(", fill = "right") %>%
      dplyr::mutate(parameter = stringr::str_replace(parameter, "\\.\\.\\.\\d+", ""),
                    date = dplyr::lead(value)) %>%
      dplyr::filter(!grepl("date", parameter, ignore.case= TRUE)) %>%
      dplyr::mutate(repeat_measurement = stringr::str_extract(parameter, "^.*icate "),
                    flag_symbol = stringr::str_remove_all(value, "[\\d\\.]"),
                    parameter = ifelse(is.na(repeat_measurement), parameter, stringr::str_remove(parameter, repeat_measurement)),
                    parameter = trimws(parameter),
                    value = stringr::str_remove_all(value, "[^\\d\\.]"),
                    value = as.numeric(value),
                    unit = stringr::str_remove(unit, "\\)"),
                    repeat_measurement = stringr::str_to_lower(trimws(repeat_measurement))) %>%
      dplyr::filter(!is.na(value)) %>%
      janitor::clean_names() %>%
      dplyr::left_join(questionable, by = c("parameter", "lab_number")) %>%
      dplyr::select(-param_description, -comparison, -assessment) %>%
      dplyr::rename(qa_within_precision_limits = within_precision_limits,
                    qa_description = orig_text)

    # Trim whitespace, replace empty strings with NA, and attempt to parse dates and times
    metadata <- dplyr::mutate(metadata,
                              dplyr::across(dplyr::where(is.character), trimws),
                              dplyr::across(dplyr::where(is.character), ~ dplyr::na_if(., "")),
                              dplyr::across(dplyr::contains("date"), tryParseDate))
    questionable <- dplyr::mutate(questionable,
                                  dplyr::across(dplyr::where(is.character), trimws),
                                  dplyr::across(dplyr::where(is.character), ~ dplyr::na_if(., "")))
    samples <- dplyr::mutate(sample_table,
                             dplyr::across(dplyr::where(is.character), trimws),
                             dplyr::across(dplyr::where(is.character), ~ dplyr::na_if(., "")),
                             dplyr::across(dplyr::contains("date"), tryParseDate),
                             dplyr::across(dplyr::contains("remark"), tryParseDate))
    data <- dplyr::mutate(data,
                          dplyr::across(dplyr::where(is.character), trimws),
                          dplyr::across(dplyr::where(is.character), ~ dplyr::na_if(., "")),
                          dplyr::across(dplyr::contains("date"), tryParseDate),
                          dplyr::across(dplyr::contains("remark"), tryParseDate))

    return(list(data = data,
                metadata = metadata,
                samples = samples,
                questionable = questionable))
  })

  names(data) <- basename(files)

  return(data)
}

#' Wrangle CCAL data into a machine-readable format
#'
#' Takes data as delivered by CCAL, extracts it, and rewrites it to tabs in an xlsx file or csv files in a folder.
#'
#' @inheritParams getCCALData
#' @inheritParams openxlsx::write.xlsx
#' @param format File format to export machine readable data to - either "xlsx" or "csv"
#' @param destination_folder Folder to save the data in. Defaults to current working directory. Folder must already exist.
#'
#' @return Invisibly returns a list containing the data that were written to file.
#' @export
#'
#' @examples
#' \dontrun{
#' ccal_folder <- "ccal_results"
#' dest_folder <- "ccal_results/tidied"
#' file_list <- list.files(ccal_folder, pattern = "*.xlsx$", full.names = TRUE)
#' machineReadableCCAL(file_list, format = "xlsx", destination_folder = dest_folder)
#' machineReadableCCAL(file_list, format = "csv", destination_folder = dest_folder)
#' }
machineReadableCCAL <- function(files, format = c("xlsx", "csv"), destination_folder = "./", overwrite = FALSE) {
  format <- match.arg(format)
  destination_folder <- normalizePath(destination_folder, winslash = .Platform$file.sep)

  all_data <- getCCALData(files)  # Read in data

  write_data(all_data, format, destination_folder, overwrite, suffix = "_tidy", num_tables = 4)

  return(invisible(all_data))
}


#' Write data to xlsx or csv file.
#'
#' @param all_data The data to write to file.
#' @param format File format to export machine readable data to - either "xlsx" or "csv"
#' @inheritParams openxlsx::write.xlsx
#' @param destination_folder Folder to save the data in. Defaults to current working directory. Folder must already exist.
#' @param suffix Suffix to add to output file name.
#' @param num_tables Number of tables to write to file.
#'
#' @export
#'
#' @examples
#' #' \dontrun{
#' write_data(all_data, format = "xlsx", destination_folder = dest_folder, overwrite = TRUE, suffix = "_tidy", num_tables = 4)
#' write_data(all_data, format = "csv", destination_folder = dest_folder, overwrite = TRUE, suffix = "_tidy", num_tables = 4)
#' }
write_data <- function(all_data, format = c("xlsx", "csv"), destination_folder, overwrite, suffix, num_tables) {

  format <- match.arg(format)

  lapply(names(all_data), function(filename) {
    data <- all_data[[filename]]
    data_name <- stringr::str_remove(filename, "\\.xlsx")
    data_name <- paste0(data_name, suffix)
    if (format == "xlsx") {
      destination <- file.path(destination_folder, paste0(data_name, ".xlsx"))
      cli::cli_progress_message("Writing {destination}")
      openxlsx::write.xlsx(data, destination, overwrite = overwrite)
    }
    else if (format == "csv") {
      if (num_tables == 1) {
        destination <- file.path(destination_folder, paste0(data_name, ".csv"))
        if (!file.exists(destination) || overwrite) {
          cli::cli_progress_message("Writing {destination}")
          readr::write_csv(data, destination, append = FALSE)
        }
        else {
          warning(paste(destination, "already exists."))
        }
      }
      else {
        lapply(names(data), function(tbl_name) {
          destination <- file.path(destination_folder, data_name, paste0(tbl_name, ".csv"))
          if (!dir.exists(file.path(destination_folder, data_name))) {
            dir.create(file.path(destination_folder, data_name))
          }
          if (!file.exists(destination) || overwrite) {
            cli::cli_progress_message("Writing {destination}")
            readr::write_csv(data[[tbl_name]], destination, append = FALSE)
          }
          else {
            warning(paste(destination, "already exists."))
          }

        })
    }
  }})
}
