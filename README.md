
<!-- README.md is generated from README.Rmd. Please edit that file -->

# imdccal

<!-- badges: start -->
<!-- badges: end -->

The goal of imdccal is to extract data from
[CCAL](https://ccal.oregonstate.edu/) water chemistry lab deliverables,
convert it to a machine readable format, and begin processing it into
the EQuIS EDD format.

## Installation

You can install the development version of imdccal from [its GitHub
repository](https://github.com/nationalparkservice/imd-ccal) with:

``` r
# install.packages("remotes")
remotes::install_github("nationalparkservice/imd-ccal")
```

## Example Data

To demonstrate the functionality of imdccal, we created two fictitious
CCAL deliverables that are downloaded with the package. The story behind
the data is that it is 2099 and the NPS now has an Outer Space Network
with monitoring locations on the Moon, Mars, Mercury, and Saturn. Users
can find the file paths to the example data by running the following
code chunk. Since the example data is installed with the package, you
can run any of the code in this ReadMe on your own computer.

``` r
use_example_data(file_names = use_example_data())
```

## Example: Creating Machine-Readable CCAL Data

Read and tidy the data and work with it in R, without writing the data
to any files.

``` r
# Load package
library(imdccal)

# Create tidied CCAL data from demo data stored in the imdccal package
tidy_ccal <- getCCALData(use_example_data(file_names = "SPAC_080199.xlsx"))
#> Reading data from
#> C:/Users/lsmith/AppData/Local/Temp/1/Rtmpg5B6bj/temp_libpathc…
data <- tidy_ccal$`SPAC_080199.xlsx`$data     # Get the data for a single set of lab results
meta <- tidy_ccal$`SPAC_080199.xlsx`$metadata # Get the metadata for the same set of results
```

Write the tidied data that is currently stored in the R environment to
file. Note that destination_folder must already exist.

``` r
# Write data stored in environment to file
write_data(all_data = tidy_ccal, 
           format = "xlsx", # alternatively, "csv"
           destination_folder = "ccal_tidy", # must already exist
           overwrite = TRUE,
           suffix = "_tidy",
           num_tables = 4)
```

Instead of the two step process of creating the tidied R object and
writing it to file, users may use the `machineReadableCCAL()` function
to create and write the tidied data to file in one step. Here is an
example of reading data from a single file of CCAL lab data and writing
the machine-readable version to an Excel file or set of CSV files.

``` r
# Write tidied CCAL data to file from demo data stored in imdccal package
machineReadableCCAL(use_example_data(file_names = "SPAC_080199.xlsx"),
                    destination_folder = "ccal_tidy")  # Write tidied data to a new .xlsx
machineReadableCCAL(use_example_data(file_names = "SPAC_081599.xlsx"), 
                    format = "csv", destination_folder = "ccal_tidy")  # Write tidied data to a folder of CSV files
```

All of these functions also work when supplied with a vector of file
paths to multiple CCAL deliverables. Here is an example of reading data
from *multiple* files of CCAL lab data and writing the machine-readable
version to an Excel files or sets of CSV files.

``` r
# Get file paths
all_files <- use_example_data(file_names = use_example_data())

# Write to xlsx
machineReadableCCAL(all_files, destination_folder = "ccal_tidy")  # Write one file of tidied data per input file

# Write to csv
machineReadableCCAL(all_files, format = "csv", destination_folder = "ccal_tidy")  # Write one folder of tidied CSV data per input file
```

By default, these functions create separate tables and files for each
CCAL deliverable supplied as input. To concatenate the results together,
set the `concat` argument in `getCCALData()` or `machineReadableCCAL()`
to TRUE.

``` r
machineReadableCCAL(all_files, destination_folder = "ccal_tidy", concat = TRUE)
```

## Example: Creating the Results Table of the EQuIS EDD

In addition to converting CCAL lab deliverables to a machine readable
format, imdccal also provides functionality to begin processing the
machine readable data into the EQuIS EDD format. Specifically, the
`format_results()` function begins to format the data into the Results
table for the EDD.

**Uses:**

- Process data into one of the tables in the format accepted by EQuIS
- Censor values less than or equal to the MDL
- Raise the J-R flag for observations greater than the MDL but less than
  or equal to the LQL

**Limitations:**

- Users still need to create Activities table for every deliverable and
  the Projects and Locations tables when they require edits.
- Within the Results table, users still need to define Activity_ID,
  modify Result_Status (set to Pre-Cert since additional QC is needed),
  add flags, and conduct the rest of their own QC processes

Here we demonstrate the useage of this function. Read the data, create
the Results table of the EDD, and work with it in R without writing the
data to any files:

``` r
# Create results table from demo data stored in the imdccal package
results_incomplete <- format_results(use_example_data(file_names = "SPAC_080199.xlsx"))
#> Reading data from
#> C:/Users/lsmith/AppData/Local/Temp/1/Rtmpg5B6bj/temp_libpathc…
```

If you inspect the table created above, you will notice that there are
so many columns without data that the result is not useful. That’s
because our code relies on a table containing detection limits for each
analyte. To accommodate changes to detection limits over time, the table
includes StartDate and EndDate columns. The issue we have above is that
none of the limits are applicable after December 31, 2024, and our
example data is from 2099.

By default, `format_results()` uses the version of the table that is
stored within the package. However, users may provide their own version
of the table as an argument in the function if that better suits their
needs. This may occur, for example, if detection limits change or if a
user needs to include an analyte that is not yet in the table. To
provide a different version of the table, start with the version stored
in the package, and add rows or edit columns as you see fit. It may be
helpful to review the documentation of the limits table (run
`?imdccal::limits`) as you make your edits. For example, we edit the
EndDate for all relevant rows to December 31, 2099 in the code below.

``` r
# Edit limits table
limits <- imdccal::limits |>
  dplyr::mutate(EndDate = dplyr::if_else(EndDate == "2024-12-31", lubridate::ymd("2099-12-31"), EndDate))
```

Users may also save the table to a csv or xlsx file and make changes
directly to a spreadsheet. To use one’s updated table in
`format_results()`, simply supply the function with the modified table
(as an R object) as the limits argument. We do so with our example data
below.

``` r
# Create results table from demo data stored in the imdccal package
results_complete <- format_results(use_example_data(file_names = "SPAC_080199.xlsx"),
                                   limits = limits)
#> Reading data from
#> C:/Users/lsmith/AppData/Local/Temp/1/Rtmpg5B6bj/temp_libpathc…
```

Users may also provide their own version of the qualifiers table, which
contains the lookup_code and remark columns from
[NPS_EQuIS_WQX_Reference_Values](https://doimspp.sharepoint.com/:x:/r/sites/nps-nrss-wrdiv/_layouts/15/Doc.aspx?sourcedoc=%7B897FC8B3-2F68-4353-BB79-C0FEE9C45991%7D&file=NPS_EQuIS_WQX_Reference_Values.xlsx&action=default&mobileredirect=true)
after filtering for rows where the \#lookup_type is “Result_Qualifier”.
In this package the only flag we raise is “J-R”, so unless this flag’s
description changes, the user has no need to use this argument. However,
it is worth familiarizing oneself with the table as it is useful for
further data processing. Run `?imdccal::qualifiers` to see the table’s
documentation. In addition, users may benefit from reading through the
[NPS EQuIS Resources
website](https://doimspp.sharepoint.com/sites/nps-nrss-wrdiv/SitePages/DMEQuIS.aspx?xsdata=MDV8MDJ8fDE1NTcyM2EwNmEyODQ3NThhZDM5MDhkYzUzNDVjZjUwfDA2OTNiNWJhNGIxODRkN2I5MzQxZjMyZjQwMGE1NDk0fDB8MHw2Mzg0NzY4MDY0NzU3ODc1Nzd8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKV0lqb2lNQzR3TGpBd01EQWlMQ0pRSWpvaVYybHVNeklpTENKQlRpSTZJazkwYUdWeUlpd2lWMVFpT2pFeGZRPT18MXxMMk5vWVhSekx6RTVPbTFsWlhScGJtZGZUbXBuTVU5RWF6UlBWR2QwV21wck5FMXBNREJPZWtreVRGUm9iRTFxWjNSYVZFWnBUMFJWTTAxNmJHaFBSRUpxUUhSb2NtVmhaQzUyTWk5dFpYTnpZV2RsY3k4eE56RXlNRGd6T0RRMk1qVXd8MDU3NTdhODQyYWI2NDI5MGFkMzkwOGRjNTM0NWNmNTB8Yjg5ZDU1YmI3ZjVhNDNhNmJlODQwMzU5NDgyNTM1ZmM%3D&sdata=TjVsUVVHQS84VDQ2NUlRZmNzMlE3R2hRRWI0MDdlaVRIL0hkNnAxMmRSQT0%3D&ovuser=0693b5ba-4b18-4d7b-9341-f32f400a5494%2Cavolk%40nps.gov&OR=Teams-HL&CT=1719255259520&clickparams=eyJBcHBOYW1lIjoiVGVhbXMtRGVza3RvcCIsIkFwcFZlcnNpb24iOiI0OS8yNDA1MTYyMjIyMyIsIkhhc0ZlZGVyYXRlZFVzZXIiOmZhbHNlfQ%3D%3D),
which provides comprehensive guidelines on formatting data for EQuIS.

Like with the machine readable data, we can write the results table from
our R environment to file with the `write_data()` function.

``` r
# Write data stored in environment to file
write_data(all_data = results_complete, 
           format = "xlsx", # alternatively, "csv"
           destination_folder = "ccal_tidy", # must already exist
           overwrite = TRUE, 
           suffix = "_edd_results", 
           num_tables = 1)
```

Also in the same manner as the machine readable data, instead of a two
step process of creating the results table R object and writing it to
file, users may use the `write_results()` function to create and write
the results table to file in one step. Here is an example of reading
data from a single file of CCAL lab data and writing the results table
to an Excel or CSV file.

``` r
# Write results table to xlsx from demo data stored in imdccal package
write_results(files = use_example_data(file_names = "SPAC_080199.xlsx"),
              limits = limits,
              format = "xlsx",
              destination_folder = "ccal_tidy",
              overwrite = TRUE)

# Write results table to csv from demo data stored in imdccal package
write_results(files = use_example_data(file_names = "SPAC_081599.xlsx"),
              limits = limits,
              format = "csv",
              destination_folder = "ccal_tidy",
              overwrite = TRUE)
```

As before, all of these functions work when supplied with a vector of
file paths to multiple CCAL deliverables. Here is an example of reading
data from *multiple* files of CCAL lab data and writing the results
tables to Excel or CSV files.

``` r
# Get file paths
all_files <- use_example_data(file_names = use_example_data())

# Write to xlsx
write_results(files = all_files, 
              limits = limits,
              destination_folder = "ccal_tidy",
              overwrite = TRUE)

# Write to csv
write_results(files = all_files, 
              limits = limits,
              format = "csv", 
              destination_folder = "ccal_tidy",
              overwrite = TRUE)
```

By default, these functions create separate tables and files for each
CCAL deliverable supplied as input. To concatenate the results together,
set the `concat` argument in `format_results()` or `write_results()` to
TRUE.

``` r
write_results(files = all_files, 
              limits = limits,
              destination_folder = "ccal_tidy",
              overwrite = TRUE,
              concat = TRUE)
```
