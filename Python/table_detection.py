from abc import ABC, abstractmethod
import pandas as pd
from pprint import pprint

class TableExtractor(ABC):
    def __init__(self, pdf_path):
        self.pdf_path = pdf_path
        self.tables_df = pd.DataFrame(columns=["Page Number", "Table Content"])

    @abstractmethod
    def detect_tables(self):
        """
        Abstract method to parse the PDF file page by page and detect tables.
        """
        pass

    @abstractmethod
    def extract_tables(self, page):
        """
        Abstract method to extract table content from a given page.
        """
        pass

    def get_tables(self):
        """
        Returns the DataFrame containing detected tables.
        """
        return self.tables_df

class TableExtractor_PyMuPDF(TableExtractor):
    import fitz  # PyMuPDF

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """        
        tables = page.find_tables()
        print(f"{len(tables.tables)} table(s) on {page}")
        return tables
        

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        with self.fitz.open(self.pdf_path) as pdf:
            for page_number, page in enumerate(pdf, start=1):
                tabs = self.detect_tables(page)

                for table in tabs.tables:
                    # Process each table and extract its content
                    table_content = table.extract()
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )
    
class TableExtractor_PyMuPDF4llm(TableExtractor):
    import pymupdf4llm
    import re
    markdown_table_regex = r'(?:\|(?:[^\r\n|]*\|)+\r?\n(?:\|[-:]+)+\|(?:\r?\n\|(?:[^\r\n|]*\|)+)+)'

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.re.findall(self.markdown_table_regex, page['text'])
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        extract = self.pymupdf4llm.to_markdown(self.pdf_path, page_chunks=True)
        for page_number, page in enumerate(extract, start=1):
            # Process each page and extract its content
            
            tabs = self.detect_tables(page)

            for table in tabs:
                # Process each table and extract its content
                table_content = table#.extract()
                self.tables_df = pd.concat(
                    [
                        self.tables_df,
                        pd.DataFrame(
                            {"Page Number": [page_number], "Table Content": [table_content]}
                        ),
                    ],
                    ignore_index=True,
                )

class TableExtractor_PdfPlumber(TableExtractor):
    import pdfplumber

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = page.extract_tables()
        # Filter out empty tables
        non_empty_tables = [table for table in tables if any(any(cell.strip() for cell in row) for row in table)]
        return non_empty_tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        with self.pdfplumber.open(self.pdf_path) as pdf:
            for page_number, page in enumerate(pdf.pages, start=1):
                tabs = self.detect_tables(page)

                for table in tabs:
                    # Process each table and extract its content
                    table_content = table
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )

class TableExtractor_PypdfTableExtraction(TableExtractor):
    import pypdf_table_extraction

    def detect_tables(self, page = "all"):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.pypdf_table_extraction.read_pdf(self.pdf_path)
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        

        tabs = self.detect_tables()
        for table in tabs:
            # Process each table and extract its content
            page_number = table.parsing_report['page']
            table_content = table.df.to_string(index=False, header=False)
            self.tables_df = pd.concat(
                [
                    self.tables_df,
                    pd.DataFrame(
                        {"Page Number": [page_number], "Table Content": [table_content]}
                    ),
                ],
                ignore_index=True,
            )

class TableExtractor_TabulaPy(TableExtractor):
    import tabula
    import pdfplumber

    def detect_tables(self, page = "all"):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.tabula.read_pdf(self.pdf_path, pages=page)
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        with self.pdfplumber.open(self.pdf_path) as pdf:
            for page_number, page in enumerate(pdf.pages, start=1):
                tabs = self.detect_tables(page_number)

                for table in tabs:
                    # Process each table and extract its content
                    table_content = table
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )

def benchmark(class_name, pdf_path):
    """
    Benchmark the table extraction process.
    """
    print(f"Benchmarking {class_name.__name__} on {pdf_path}")
    extractor = class_name(pdf_path)
    extractor.extract_tables()
    tables = extractor.get_tables()
    print(tables)
    print('\n')

# Example usage:
if __name__ == "__main__":
    easy_table = "benchmark_tables/easy_table_german_finance.pdf"
    real_table = "tmp/pdf_split/page.pdf"

    """
    benchmark(TableExtractor_PyMuPDF, easy_table)
    benchmark(TableExtractor_PyMuPDF, real_table)

    benchmark(TableExtractor_PyMuPDF4llm, easy_table)
    benchmark(TableExtractor_PyMuPDF4llm, real_table)
    
    benchmark(TableExtractor_PdfPlumber, easy_table)
    benchmark(TableExtractor_PdfPlumber, real_table)
    
    benchmark(TableExtractor_PypdfTableExtraction, easy_table)
    benchmark(TableExtractor_PypdfTableExtraction, real_table)
    """
    benchmark(TableExtractor_TabulaPy, easy_table)
    benchmark(TableExtractor_TabulaPy, real_table)