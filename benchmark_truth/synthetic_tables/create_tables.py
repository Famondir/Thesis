import pandas as pd
import random
import pdfkit
from pprint import pprint
import json
from io import StringIO
import re

with open('/home/simon/Documents/data_science/Thesis/benchmark_truth/synthetic_tables/text_around.json', 'r') as file:
    text_around = json.load(file)

aktiva_structure_hgb = {
    'Anlagevermögen': {
        'Immaterielle Vermögensgegenstände': [
            'Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte',
            'Geschäfts- oder Firmenwert',
            'geleistete Anzahlungen',
            'entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten'
        ], 
        'Sachanlagen': [
            'Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken',
            'Technische Anlagen und Maschinen',
            'Andere Anlagen, Betriebs- und Geschäftsausstattung',
            'geleistete Anzahlungen und Anlagen im Bau'
        ],
        'Finanzanlagen': [
            'Sonstige Finanzanlagen',
            'Anteile an verbundenen Unternehmen',
            'Ausleihungen an verbundene Unternehmen',
            'Beteiligungen',
            'Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht',
            'Wertpapiere des Anlagevermögens',
            'Sonstige Ausleihungen'
        ]
    },
    'Umlaufvermögen': {
        'Vorräte': [
            'Roh-, Hilfs- und Betriebsstoffe',
            'Unfertige Erzeugnisse, unfertige Leistungen',
            'Fertige Erzeugnisse und Waren',
            'Geleistete Anzahlungen'
        ],
        'Forderungen und sonstige Vermögensgegenstände': [
            'Forderungen aus Lieferungen und Leistungen',
            'Forderungen gegen verbundene Unternehmen',
            'Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht',
            'Sonstige Vermögensgegenstände'
        ],
        'Wertpapiere': [
            'Anteile an verbundenen Unternehmen',
            'Sonstige Wertpapiere'
        ],
        'Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks': []
    },
    'Rechnungsabgrenzungsposten': dict(),
    'Aktive latente Steuern': dict(),
    'Aktiver Unterschiedsbetrag aus der Vermögensverrechnung': dict()
}

unit_list = {
    'EUR': 1, 
    '€': 1, 
    'Tsd. EUR': 1000, 
    'Mio. EUR': 1000000, 
    'TEUR': 1000, 
    'T€': 1000, 
    'Tsd. €': 1000, 
    'Mio. €': 1000000
}

enumerators = [
    ['A.', 'B.', 'C.', 'D.', 'E.', 'F.'],
    ['I.', 'II.', 'III.', 'IV.', 'V.', 'VI.'],
    ['1.', '2.', '3.', '4.', '5.', '6.', '7.', '8.', '9.']
]

def generate_random_value():
    return random.random() * 10_000_000  # Random value between 0 and 10,000,000

def generate_table(column_names):
    df = pd.DataFrame(columns=column_names)

    for key, value in aktiva_structure_hgb.items():
        if isinstance(value, dict):
            if len(value) == 0:
                df = pd.concat([df, pd.DataFrame([[key, pd.NA, pd.NA, generate_random_value(), generate_random_value()]], columns=column_names).astype(df.dtypes)], ignore_index=True)
            else:
                for sub_key, sub_value in value.items():
                    if len(sub_value) == 0:
                        df = pd.concat([df, pd.DataFrame([[key, sub_key, pd.NA, generate_random_value(), generate_random_value()]], columns=column_names).astype(df.dtypes)], ignore_index=True)
                    else:
                        for item in sub_value:
                            df = pd.concat([df, pd.DataFrame([[key, sub_key, item, generate_random_value(), generate_random_value()]], columns=column_names).astype(df.dtypes)], ignore_index=True)
        else:
            raise ValueError(f"Expected a dictionary for {key}, but got {type(value)}")
        
    return df

def thin_table(df):
    n_rows = df.shape[0]
    random_indices = random.sample(range(n_rows), random.randint(1, n_rows-6))
    for idx in random_indices:
        df.at[idx, year] = pd.NA
        df.at[idx, previous_year] = pd.NA

    df_thinned = df.copy().dropna(subset=[year, previous_year]).reset_index(drop=True)
    return df_thinned

def generate_header(n_columns = 3, first_cell = 'Aktiva', year = '31.12.2023', previous_year = '31.12.2022', span=False):
    header = [first_cell]
    if n_columns == 3:
        header.append(f'{year}')
        header.append(f'{previous_year}')
    elif n_columns == 4:
        header.append(f'{year}')
        if not span:
            header.append(f'{year}')
        header.append(f'{previous_year}')
    elif n_columns == 5:
        header.append(f'{year}')
        if not span:
            header.append(f'{year}')
        header.append(f'{previous_year}')
        if not span:
            header.append(f'{previous_year}')

    header_html = '<tr>' + ''.join(f'<th>{cell}</th>' for cell in header) + '</tr>'
    if span and n_columns in [4, 5]:
        parts = header_html.split('</th><th>')
        if n_columns == 4:
            parts[1] = f'</th><th colspan="2">{parts[1]}</th><th>'
        elif n_columns == 5:
            parts[1] = f'</th><th colspan="2">{parts[1]}</th>'
            parts[2] = f'<th colspan="2">{parts[2]}</th>'
        header_html = ''.join(parts)
    return header_html

def generate_html_table(rows, unit='TEUR', n_columns=3, unit_in_first_cell=False, span=True, max_length=10000, sum_in_same_row=False):
    if len(rows) == 0:
        return '<table><tr><th>No data available</th></tr></table>'
    
    # Insert linebreak before 80 characters if there is a space
    def insert_linebreak(text, max_length=max_length):
        import textwrap

        if isinstance(text, str) and len(text) > max_length:
            # Use textwrap to insert line breaks at appropriate places
            wrapped_text = textwrap.fill(text, width=max_length, break_long_words=False, replace_whitespace=False)
            return wrapped_text.replace('\n', '<br>')
        else:
            return text

    rows_cut = [[insert_linebreak(cell) if i == 0 else cell for i, cell in enumerate(row[0:3])] for row in rows]

    # rows_cut = [row[0:3] for row in rows]
    
    html_rows = []
    if not unit_in_first_cell:
        rows_cut.insert(0, [''] + [unit] * (n_columns - 1))
        rows.insert(0, [''] + [unit] * (n_columns - 1))

    for idx, (row_cut, row) in enumerate(zip(rows_cut, rows)):
        html_row = '<tr>' + ''.join(
            f'<td>{cell/unit_list.get(unit, 1):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.') + '</td>' if isinstance(cell, (int, float)) and pd.notna(cell)
            else f'<td>{'' if 'SUMME' in cell else cell}</td>' for cell in row_cut
        ) + '</tr>'

        if idx == 0 and not unit_in_first_cell:
            html_rows.append(html_row)
            continue

        # if not sum_in_same_row:
        #     match n_columns:
        #         case 3:
        #             pass
        #         case 4:
        #             parts = html_row.split('</td><td>')
        #             if any('SUMME' in str(cell) for cell in row):
        #                 html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:])
        #             else:
        #                 html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
        #         case 5:
        #             parts = html_row.split('</td><td>')
        #             if any('SUMME' in str(cell) for cell in row):
        #                 html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
        #             else:
        #                 html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:]).replace('</td></tr>', '</td><td></td></tr>')
        #         case _:
        #             raise ValueError(f"Unsupported number of columns: {n_columns}")
        # else:
        match n_columns:
            case 3:
                pass
            case 4:
                parts = html_row.split('</td><td>')
                if any('__' in str(cell) for cell in row):
                    parts = [f'{float(subpart.replace("</td></tr>", "").replace(",", ".").replace("-", "").strip())/unit_list.get(unit, 1):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.') if '__' in part
                                else subpart for part in parts for subpart in part.split('__')]
                    # parts = [float(part) for idx, part in enumerate(parts) if idx > 0]
                    html_row = '</td><td>'.join(parts[:-1])
                    if not '</td></tr>' in html_row:
                        html_row += '</td></tr>'
                elif any('SUMME' in str(cell) for cell in row): 
                    html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:])
                else:
                    html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
            case 5:
                parts = html_row.split('</td><td>')
                if any('__' in str(cell) for cell in row):
                    parts = [f'{float(subpart.replace("</td></tr>", "").replace(",", ".").replace("-", "").strip())/unit_list.get(unit, 1):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.') if '__' in part
                                else subpart for part in parts for subpart in part.split('__')]
                    # parts = [float(part) for idx, part in enumerate(parts) if idx > 0]
                    html_row = '</td><td>'.join(parts)
                    if not '</td></tr>' in html_row:
                        html_row += '</td></tr>'
                elif any('SUMME' in str(cell) for cell in row):
                    html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
                else:
                    html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:]).replace('</td></tr>', '</td><td></td></tr>')
            case _:
                raise ValueError(f"Unsupported number of columns: {n_columns}")
            
        html_rows.append(html_row)

    first_cell = ('Aktiva (in ' + unit + ')') if unit_in_first_cell else 'Aktiva'
    html_rows.insert(0, generate_header(n_columns=n_columns, first_cell=first_cell, year=year, previous_year=previous_year, span=span))

    html_table = '<table>\n' + '\n'.join(html_rows) + '\n</table>'
    return html_table

def generate_html_page(html_table, add_text_around=False):
    html_page = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Aktiva Table</title>
        <style>
            table {{
                width: 100%;
                border-collapse: collapse;
            }}
            th, td {{
                border: 1px solid black;
                padding: 8px;
                text-align: left;
            }}
            th {{
                background-color: #f2f2f2;
            }}
        </style>
    </head>
    <body>
    {'' if not add_text_around else '<p>' + text_around['before'][random.randint(0, len(text_around['before']) - 1)] + '</p>'}
        {html_table}
    {'' if not add_text_around else '<p>' + text_around['after'][random.randint(0, len(text_around['after']) - 1)] + '</p>'}
    </body>
    </html>
    """
    return html_page

def check_na_or_given_string(value, string):
    return pd.isna(value) or (value == string)

def generate_row_list(df, add_enumeration=True):
    rows = []
    enum = [0] * 3
    cols = [col for col in df.columns if col not in ['E1', 'E2', 'E3']]

    for key in df['E1'].unique():
        enum[0] += 1
        enum[1] = 0
        enum[2] = 0
        df_temp = df[df['E1'] == key]
        title = (enumerators[0][enum[0]-1] + ' ' + key) if add_enumeration else key

        if df_temp.shape[0] == 1 and check_na_or_given_string(df_temp['E2'].iloc[0], 'SUMME') and check_na_or_given_string(df_temp['E3'].iloc[0], 'SUMME'):
            rows.append([title] + df_temp[cols].iloc[0].tolist())

        else:
            rows.append([title] + [''] * (len(df.columns) - 3))

            for sub_key in df_temp['E2'].unique():
                df_sub_temp = df_temp[df_temp['E2'] == sub_key]
                enum[1] += 1
                enum[2] = 0
                title = (enumerators[1][enum[1]-1] + ' ' + sub_key) if add_enumeration else sub_key

                if df_sub_temp.shape[0] == 1 and check_na_or_given_string(df_sub_temp['E3'].iloc[0], 'SUMME'):
                    rows.append([title] + df_sub_temp[cols].iloc[0].tolist())
                else:
                    rows.append([title] + [''] * (len(df.columns) - 3))

                    for item in df_sub_temp['E3'].unique():
                        df_item_temp = df_sub_temp[df_sub_temp['E3'] == item]
                        enum[2] += 1
                        title = (enumerators[2][enum[2]-1] + ' ' + item) if add_enumeration else item

                        # if df_item_temp.shape[0] == 1:
                        if df_sub_temp.shape[0] == 1:
                            rows.append([title] + df_item_temp[cols].iloc[0].tolist())
                        else:
                            rows.append([title] + df_item_temp[cols].iloc[0].tolist())
    return rows

def add_sum_rows(df, sum_in_same_row=False):
    df_with_sums = df.copy()
    df_with_sums['E1_E2'] = df_with_sums['E1'].astype(str) + '+' + df_with_sums['E2'].astype(str)
    df_with_sums['count_lvl2'] = df_with_sums.groupby('E1_E2')['E1_E2'].transform('count')
    df_with_sums = df_with_sums.drop(columns=['E1_E2'])
    df_with_sums['count_lvl1'] = df_with_sums.groupby('E1')['E1'].transform('count')

    df_aggregated = df.groupby(['E1', 'E2']).agg(
        {year: 'sum', previous_year: 'sum'}
    ).reset_index()
    df_aggregated['count_lvl2'] = df.groupby(['E1', 'E2']).size().values
    # Insert 'E3' column after 'E2'
    insert_at = df_aggregated.columns.get_loc('E2') + 1
    df_aggregated.insert(insert_at, 'E3', 'SUMME')
    
    for row in df_aggregated.itertuples():
        if (row.count_lvl2 > 1):
            new_row = pd.DataFrame([row[1:-1]], columns=df.columns)

            # Find the last index where E1 and E2 match
            mask = (df_with_sums['E1'] == row.E1) & (df_with_sums['E2'] == row.E2)
            last_idx = df_with_sums[mask].index.max()
            
            if not sum_in_same_row:
                # Split df and insert new_row after last_idx
                df_top = df_with_sums.iloc[:last_idx + 1]
                df_bottom = df_with_sums.iloc[last_idx + 1:]
                df_with_sums = pd.concat([df_top, new_row, df_bottom], ignore_index=True)
            else:
                df_with_sums.iloc[last_idx,-4] = str(df_with_sums.iloc[last_idx,-4]) + "__" + str(new_row.iloc[0,-2])
                df_with_sums.iloc[last_idx,-3] = str(df_with_sums.iloc[last_idx,-3]) + "__" + str(new_row.iloc[0,-1])
                pass
        
    df_aggregated = df.groupby(['E1']).agg(
        {year: 'sum', previous_year: 'sum'}
    ).reset_index()
    df_aggregated['count_lvl1'] = df.groupby(['E1']).size().values
    # Insert 'E2' and 'E3' column after 'E1'
    insert_at = df_aggregated.columns.get_loc('E1') + 1
    df_aggregated.insert(insert_at, 'E2', 'SUMME')
    df_aggregated.insert(insert_at + 1, 'E3', 'SUMME')

    for row in df_aggregated.itertuples():
        if (row.count_lvl1 > 1):
            new_row = pd.DataFrame([row[1:-1]], columns=df.columns)

            # Find the last index where E1 matches
            mask = (df_with_sums['E1'] == row.E1)
            last_idx = df_with_sums[mask].index.max()

            df_top = df_with_sums.iloc[:last_idx + 1]
            df_bottom = df_with_sums.iloc[last_idx + 1:]
            df_with_sums = pd.concat([df_top, new_row, df_bottom], ignore_index=True)
            # if not sum_in_same_row:
            #     # Split df and insert new_row after last_idx
            #     df_top = df_with_sums.iloc[:last_idx + 1]
            #     df_bottom = df_with_sums.iloc[last_idx + 1:]
            #     df_with_sums = pd.concat([df_top, new_row, df_bottom], ignore_index=True)
            # else:
            #     df_with_sums.iloc[last_idx,-4] = str(df_with_sums.iloc[last_idx,-4]) + "__" + str(new_row.iloc[0,-2])
            #     df_with_sums.iloc[last_idx,-3] = str(df_with_sums.iloc[last_idx,-3]) + "__" + str(new_row.iloc[0,-1])
            #     pass

    # Add a final row for the total
    total_row = pd.DataFrame([['SUMME', 'SUMME', 'SUMME', df[year].sum(), df[previous_year].sum()]], columns=df.columns)
    df_with_sums = pd.concat([df_with_sums, total_row], ignore_index=True)
    return df_with_sums

def generate_json(rows):
    json_data = []
    for row in rows:
        json_row = {
            'type': row[0],
            'year': row[1],
            'previous_year': row[2]
        }
        json_data.append(json_row)
    return json_data

def create_pdf(output_path, column_names, n_columns=4, thin=False, span=True, unit_in_first_cell=False, unit='TEUR', add_enumeration=True, shuffle_rows=False, max_length=50, add_text_around=False, sum_in_same_row=False):
    df = generate_table(column_names)
    if shuffle_rows:
        # Shuffle rows within each group of ['E1', 'E2']
        df = df.groupby(['E1', 'E2'], group_keys=True, sort=False).apply(
            lambda x: x.sample(frac=1, random_state=random.randint(0, 10000))
        ).reset_index(drop=True)
    df_thinned = thin_table(df) if thin else df
    df_with_sums = add_sum_rows(df_thinned, sum_in_same_row=sum_in_same_row)
    row_list = generate_row_list(df_with_sums, add_enumeration=add_enumeration)
    # pprint(generate_json(generate_row_list(df_with_sums, add_enumeration=False)))  # For debugging purposes
    html_table = generate_html_table(row_list, n_columns=n_columns, unit_in_first_cell=unit_in_first_cell, span=span, unit=unit, max_length=max_length, sum_in_same_row=sum_in_same_row)
    html_page = generate_html_page(html_table, add_text_around=add_text_around)
    config = pdfkit.configuration(wkhtmltopdf='/usr/local/bin/wkhtmltopdf')  # Adjust the path as necessary
    options = {
        'page-size': 'A4',
        # 'orientation': 'Landscape',
        'margin-top': '5mm',
        'margin-bottom': '5mm',
        'margin-left': '5mm',
        'margin-right': '5mm',
        'zoom': '0.5',  # Shrink content to fit
        'disable-smart-shrinking': '',
        'no-outline': None,
        'dpi': 150
    }
    pdfkit.from_string(
        html_page,
        output_path+'.pdf',
        configuration=config,
        options=options
    )

    df.to_csv(output_path+'.csv', index=False)

    # Export to HTML, replacing NaN/None/NA with empty string
    df_print = pd.read_html(
        StringIO(html_table),
        decimal=',',
        thousands='.'
    )[0]
    df_print = df_print.where(pd.notna(df_print), '')
    # df_print = df_print.map(lambda x: x.str.replace('.', ',') if x.dtype == "object" else x)  # Convert number strings to float

    # Format floats with thousands separator '.' and decimal separator ','
    def is_float_str(val):
        try:
            float(str(val))
            return True
        except (ValueError, TypeError):
            return False

    for idx, row in df_print.iterrows():
        for col in df_print.columns[1:]:
            val = row[col]
            if is_float_str(val):
                df_print.at[idx, col] = f"{float(val):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
            else:
                pass
    
    df_print.columns = [re.sub(r'\.1$', '', col) for col in df_print.columns]
    df_print.to_html(output_path+'.html', index=False, justify='left')
    df_print.to_markdown(output_path+'.md', index=False)


if __name__ == "__main__":
    seed = 41  # For reproducibility
    random.seed(seed)

    year = '31.12.2023'
    previous_year = '31.12.2022'
    column_names = ['E1', 'E2', 'E3', year, previous_year]

    test_run = True
    if test_run:
        create_pdf('./benchmark_truth/synthetic_tables/aktiva_table', column_names, n_columns=5, thin=False, span=False, unit_in_first_cell=False, unit='Mio. EUR', max_length=50, add_text_around=True, sum_in_same_row=False)
    else:
        count = 0
        
        for n_columns in [3, 4, 5]:
            for span in [True, False]:
                for thin in [True, False]:
                    for unit_in_first_cell in [True, False]:
                        for add_enumeration in [True, False]:
                            for max_length in [10000, 50]:
                                for shuffle_rows in [True, False]:
                                    for add_text_around in [True, False]:
                                        for sum_in_same_row in [True, False]:
                                            for unit in unit_list.keys():
                                                for i in range(0, 1):
                                                    count += 1
                                                    base_year = random.randint(2000, 2023)
                                                    year = f'31.12.{base_year}'
                                                    previous_year = f'31.12.{base_year - 1}'
                                                    column_names = ['E1', 'E2', 'E3', year, previous_year]

                                                    create_pdf(
                                                        f'./benchmark_truth/synthetic_tables/separate_files/final/aktiva_table__{n_columns}_columns__span_{span}__thin_{thin}__year_as_date__unit_in_first_cell_{unit_in_first_cell}__{unit}__enumeration_{add_enumeration}__shuffle_{shuffle_rows}__text_around_{add_text_around}__max_length_{max_length}__sum_in_same_row_{sum_in_same_row}__{i}', 
                                                        column_names, 
                                                        n_columns=n_columns, 
                                                        thin=thin, span=span, 
                                                        unit_in_first_cell=unit_in_first_cell, 
                                                        unit=unit,
                                                        add_enumeration=add_enumeration
                                                        )  

                                                year = 'Geschäftsjahr'
                                                previous_year = 'Vorjahr'
                                                column_names = ['E1', 'E2', 'E3', year, previous_year]

                                                for i in range(0, 1):
                                                    count += 1
                                                    create_pdf(
                                                        f'./benchmark_truth/synthetic_tables/separate_files/final/aktiva_table__{n_columns}_columns__span_{span}__thin_{thin}__year_as_text__unit_in_first_cell_{unit_in_first_cell}__{unit}__enumeration_{add_enumeration}__shuffle_{shuffle_rows}__text_around_{add_text_around}__max_length_{max_length}__sum_in_same_row_{sum_in_same_row}__{i}', 
                                                        column_names, 
                                                        n_columns=n_columns, 
                                                        thin=thin, 
                                                        span=span, 
                                                        unit_in_first_cell=unit_in_first_cell, 
                                                        unit=unit,
                                                        add_enumeration=add_enumeration
                                                    )

                                            print(f"Generated {count} PDF files.", end='\r')
        print(f"\nTotal generated PDF files: {count}")
