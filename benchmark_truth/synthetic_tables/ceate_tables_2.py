import pandas as pd
import random

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
    for idx in random_indices:
        df.at[idx, year] = pd.NA
        df.at[idx, previous_year] = pd.NA

    df_thinned = df.dropna(subset=[year, previous_year]).reset_index(drop=True)
    return df_thinned

def generate_html_table(rows):
    html_rows = []
    for row in rows:
        if pd.notna(row[1]) and pd.notna(row[2]):
            html_row = '<tr>' + ''.join(
                f'<td>{cell:,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.') + '</td>' if isinstance(cell, (int, float)) and pd.notna(cell)
                else f'<td>{cell}</td>' for cell in row
            ) + '</tr>'
            html_rows.append(html_row)
    
    html_table = '<table>\n' + '\n'.join(html_rows) + '\n</table>'
    return html_table

def generate_row_list(df):
    rows = []

    for key, value in aktiva_structure_hgb.items():
        if isinstance(value, dict):
            if key in df['E1'].values:
                if len(value) == 0:
                    cols = [col for col in df.columns if col not in ['E2', 'E3']]
                    rows.append(df.loc[df['E1'] == key, cols].iloc[0].tolist())
                else:
                    rows.append([key] + [''] * (len(df.columns) - 3))

                    for sub_key, sub_value in value.items():
                        if (
                            key in df['E1'].values and 
                            sub_key in df[df['E1'] == key]['E2'].values
                        ):
                            if len(sub_value) == 0:
                                cols = [col for col in df.columns if col not in ['E1', 'E3']]
                                rows.append(df.loc[(df['E1'] == key) & (df['E2'] == sub_key), cols].iloc[0].tolist())
                            else:
                                rows.append([sub_key] + [''] * (len(df.columns) - 3))

                                for item in sub_value:
                                    if (
                                        key in df['E1'].values and
                                        sub_key in df[df['E1'] == key]['E2'].values and
                                        item in df[(df['E1'] == key) & (df['E2'] == sub_key)]['E3'].values
                                    ):
                                        cols = [col for col in df.columns if col not in ['E1', 'E2']]
                                        rows.append(df.loc[(df['E1'] == key) & (df['E2'] == sub_key) & (df['E3'] == item), cols].iloc[0].tolist())
        else:
            raise ValueError(f"Expected a dictionary for {key}, but got {type(value)}")
        
    return rows

if __name__ == "__main__":
    year = 2023
    previous_year = year - 1
    column_names = ['E1', 'E2', 'E3', year, previous_year]
    df = generate_table(column_names)

    df_thinned = thin_table(df)
    print(generate_html_table(generate_row_list(df_thinned)))
