import pandas as pd
import random
import pdfkit

seed = 41  # For reproducibility
random.seed(seed)

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
                df = pd.concat([df, pd.DataFrame([[key, pd.NA, pd.NA, generate_random_value(), generate_random_value()]], columns=column_names)], ignore_index=True)
            else:
                for sub_key, sub_value in value.items():
                    if len(sub_value) == 0:
                        df = pd.concat([df, pd.DataFrame([[key, sub_key, pd.NA, generate_random_value(), generate_random_value()]], columns=column_names)], ignore_index=True)
                    else:
                        for item in sub_value:
                            df = pd.concat([df, pd.DataFrame([[key, sub_key, item, generate_random_value(), generate_random_value()]], columns=column_names)], ignore_index=True)
        else:
            raise ValueError(f"Expected a dictionary for {key}, but got {type(value)}")
        
    return df

def thin_table(df):
    n_rows = df.shape[0]
    random_indices = random.sample(range(n_rows), random.randint(1, n_rows)-1)
    # random_indices = [] # debugging line to disable thinning
    for idx in random_indices:
        df.at[idx, year] = pd.NA
        df.at[idx, previous_year] = pd.NA

    df_thinned = df.dropna(subset=[year, previous_year]).reset_index(drop=True)
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

def generate_html_table(rows, unit='TEUR', n_columns=3, unit_in_first_cell=False, span=True):
    if len(rows) == 0:
        return '<table><tr><th>No data available</th></tr></table>'
    
    rows_cut = [row[0:3] for row in rows]
    
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

        match n_columns:
            case 3:
                pass
            case 4:
                parts = html_row.split('</td><td>')
                if any('SUMME' in str(cell) for cell in row) or (len(row)>3 and row[3] == 'single entry'):
                    html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:])
                else:
                    html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
            case 5:
                parts = html_row.split('</td><td>')
                if any('SUMME' in str(cell) for cell in row) or (len(row)>3 and row[3] == 'single entry'):
                    html_row = '</td><td>'.join(parts[:1]) + '</td><td></td><td>' + '</td><td>'.join(parts[1:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:])
                else:
                    html_row = '</td><td>'.join(parts[:2]) + '</td><td></td><td>' + '</td><td>'.join(parts[2:]).replace('</td></tr>', '</td><td></td></tr>')
            case _:
                raise ValueError(f"Unsupported number of columns: {n_columns}")
            
        html_rows.append(html_row)

    first_cell = ('Aktiva (in ' + unit + ')') if unit_in_first_cell else 'Aktiva'
    html_rows.insert(0, generate_header(n_columns=n_columns, first_cell=first_cell, year=year, previous_year=previous_year, span=span))

    html_table = '<table>\n' + '\n'.join(html_rows) + '\n</table>'
    # print(html_table)  # Debugging output
    return html_table

def generate_html_page(html_table):
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
        {html_table}
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
            rows.append([title] + df_temp[cols].iloc[0].tolist() + ['single entry'])

        else:
            rows.append([title] + [''] * (len(df.columns) - 3))

            for sub_key in df_temp['E2'].unique():
                df_sub_temp = df_temp[df_temp['E2'] == sub_key]
                enum[1] += 1
                enum[2] = 0
                title = (enumerators[1][enum[1]-1] + ' ' + sub_key) if add_enumeration else sub_key

                if df_sub_temp.shape[0] == 1 and check_na_or_given_string(df_sub_temp['E3'].iloc[0], 'SUMME'):
                    rows.append([title] + df_sub_temp[cols].iloc[0].tolist() + ['single entry'])
                else:
                    rows.append([title] + [''] * (len(df.columns) - 3))

                    for item in df_sub_temp['E3'].unique():
                        df_item_temp = df_sub_temp[df_sub_temp['E3'] == item]
                        enum[2] += 1
                        title = (enumerators[2][enum[2]-1] + ' ' + item) if add_enumeration else item

                        # if df_item_temp.shape[0] == 1:
                        if df_sub_temp.shape[0] == 1:
                            rows.append([title] + df_item_temp[cols].iloc[0].tolist() + ['single entry'])
                        else:
                            rows.append([title] + df_item_temp[cols].iloc[0].tolist())
    print(rows)  # Debugging output
    return rows

def add_sum_rows(df):
    df_with_sums = df.copy()
    df_with_sums = df_with_sums.groupby(['E1', 'E2']).apply(lambda x: x.assign(count_lvl2=x.shape[0])).reset_index(drop=True)
    df_with_sums = df_with_sums.groupby(['E1']).apply(lambda x: x.assign(count_lvl1=x.shape[0])).reset_index(drop=True)

    df_aggregated = df.groupby(['E1', 'E2']).agg(
        {year: 'sum', previous_year: 'sum'}
    ).reset_index()
    df_aggregated['count_lvl2'] = df.groupby(['E1', 'E2']).size().values
    # Insert 'E3' column after 'E2'
    insert_at = df_aggregated.columns.get_loc('E2') + 1
    df_aggregated.insert(insert_at, 'E3', 'SUMME')
    
    for row in df_aggregated.itertuples():
        if (row.count_lvl2 > 1):
            new_row = pd.DataFrame([row[1:] + (pd.NA,)], columns=df_with_sums.columns)

            # Find the last index where E1 and E2 match
            mask = (df_with_sums['E1'] == row.E1) & (df_with_sums['E2'] == row.E2)
            last_idx = df_with_sums[mask].index.max()
            # Split df and insert new_row after last_idx
            df_top = df_with_sums.iloc[:last_idx + 1]
            df_bottom = df_with_sums.iloc[last_idx + 1:]
            df_with_sums = pd.concat([df_top, new_row, df_bottom], ignore_index=True)
        
    df_aggregated = df.groupby(['E1']).agg(
        {year: 'sum', previous_year: 'sum'}
    ).reset_index()
    df_aggregated['count'] = df.groupby(['E1']).size().values
    # Insert 'E2' and 'E3' column after 'E1'
    insert_at = df_aggregated.columns.get_loc('E1') + 1
    df_aggregated.insert(insert_at, 'E2', 'SUMME')
    df_aggregated.insert(insert_at + 1, 'E3', 'SUMME')

    for row in df_aggregated.itertuples():
        if (row.count > 1):
            new_row = pd.DataFrame([row[1:-1]], columns=df.columns)

            # Find the last index where E1 matches
            mask = (df_with_sums['E1'] == row.E1)
            last_idx = df_with_sums[mask].index.max()
            # Split df and insert new_row after last_idx
            df_top = df_with_sums.iloc[:last_idx + 1]
            df_bottom = df_with_sums.iloc[last_idx + 1:]
            df_with_sums = pd.concat([df_top, new_row, df_bottom], ignore_index=True)

    # Add a final row for the total
    total_row = pd.DataFrame([['SUMME', 'SUMME', 'SUMME', df[year].sum(), df[previous_year].sum()]], columns=df.columns)
    df_with_sums = pd.concat([df_with_sums, total_row], ignore_index=True)
    print(df_with_sums)  # Debugging output
    return df_with_sums

if __name__ == "__main__":
    year = '31.12.2023'
    previous_year = '31.12.2022'
    column_names = ['E1', 'E2', 'E3', year, previous_year]
    df = generate_table(column_names)

    df_thinned = thin_table(df)
    # print(df_thinned)
    df_with_sums = add_sum_rows(df_thinned)

    html_page = generate_html_page(generate_html_table(generate_row_list(df_with_sums), n_columns=4))
    config = pdfkit.configuration(wkhtmltopdf='/usr/local/bin/wkhtmltopdf')  # Adjust the path as necessary
    pdfkit.from_string(html_page, './benchmark_truth/synthetic_tables/aktiva_table.pdf', configuration=config)