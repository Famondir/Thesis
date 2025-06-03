import random
import pandas as pd

aktiva_structure_hgb = {
    'Anlagevermögen': {
        'Immaterielle Vermögensgegenstände': [
            # 'Entwicklungskosten', 
            # 'Lizenzen', 
            # 'Patente',
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
            # 'Beteiligungen',
            # 'Wertpapiere',
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
    ['A.', 'B.', 'C.', 'D.', 'E.'],
    ['I.', 'II.', 'III.', 'IV.', 'V.'],
    ['1.', '2.', '3.', '4.', '5.', '6.', '7.', '8.', '9.']
]

def create_aktiva():
    n_columns = random.randint(3, 5)
    n_columns = 3  # For simplicity, we fix the number of columns to 3

    year = random.randint(2000, 2024)
    numeric_previous_year = random.choice([True, False])
    previous_year = year - 1 if numeric_previous_year else 'Vorjahr'
    
    unit = random.choice(list(unit_list.keys()))
    unit_in_first_cell = random.choice([True, False])

    add_enumeration = [random.choice([True, False]) for _ in range(3)]
    add_enumeration = [True for _ in range(3)]  # For simplicity, we fix enumeration to True for all depths
    enum = [0] * 3  # Initialize enumeration counters for each depth

    rows = []
    first_cell = ('Aktiva (in ' + unit + ')') if unit_in_first_cell else 'Aktiva'

    add_header(n_columns, rows, first_cell, year, previous_year)

    if not unit_in_first_cell:
        rows.append([''] + [unit] * (n_columns - 1))

    for key in aktiva_structure_hgb.keys():
        add_rows(n_columns, rows, key, entries=aktiva_structure_hgb[key], unit=unit, add_enumeration=add_enumeration, enum=enum, enum_depth=0)

        """     if len(aktiva_structure_hgb[key_1]) == 0:
            
                rows.append(
                    [title, round(random.random()*10_000_000/unit_list[unit], 2), round(random.random()*10_000_000/unit_list[unit], 2)]
                )
            else:
                rows.append([title, '', ''])
                for key_2 in aktiva_structure_hgb[key_1].keys():
                    enum_3 = 0
                    sub_title = ((enumerators['2'][enum_2] + ' ') if add_enumeration_2 else '') + key_2

                    if len(aktiva_structure_hgb[key_1][key_2]) == 0:
                        if random.choice([True, False]):
                            rows.append(
                                [sub_title, round(random.random()*10_000_000/unit_list[unit], 2), round(random.random()*10_000_000/unit_list[unit], 2)]
                            )
                            enum_2 += 1
                        else:
                            rows.append(
                                [sub_title, pd.NA, pd.NA]
                            )
                    else:
                        rows.append([sub_title, '', ''])
                        for key_3 in aktiva_structure_hgb[key_1][key_2]:
                            title = ((enumerators['3'][enum_3] + ' ') if add_enumeration_3 else '') + key_3
                            if random.choice([True, False]):
                                rows.append(
                                    [title, round(random.random()*10_000_000/unit_list[unit], 2), round(random.random()*10_000_000/unit_list[unit], 2)]
                                )
                                enum_3 += 1
                            else:
                                rows.append(
                                    [title, pd.NA, pd.NA]
                                ) """

    html_table = generate_html_table(rows)
    print(html_table)

    data_table = pd.DataFrame(rows[1:], columns=rows[0])
    print(data_table)

def add_rows(n_columns, rows, key, entries, unit, add_enumeration, enum, enum_depth=0):
    title = ((enumerators[enum_depth][enum[enum_depth]]+ ' ') if add_enumeration[enum_depth] else '') + key
    include_key = random.choice([True, False])  # Randomly decide whether to include the key
    if enum_depth < 2:
        enum[enum_depth+1] = 0
        
    if include_key:
        if n_columns == 3:
            if len(entries) > 0:
                rows.append([title, '', ''])

                if isinstance(entries, dict):
                    for key, entry in entries.items():
                        add_rows(n_columns, rows, key, entry, unit, add_enumeration, enum, enum_depth + 1)
                elif isinstance(entries, list):
                    for entry in entries:
                        add_rows(n_columns, rows, entry, [], unit, add_enumeration, enum, enum_depth + 1)
            else:
                rows.append([title, round(random.random()*10_000_000/unit_list[unit], 2), round(random.random()*10_000_000/unit_list[unit], 2)])
        else:
            raise NotImplementedError("Only 3 columns are currently supported in this implementation.")

        enum[enum_depth] += 1
    else:
        rows.append([title] + [pd.NA] * (n_columns - 1))

# year can be colspan for mutliple columns
def add_header(n_columns = 3, rows = [], first_cell = 'Aktiva', year = 2023, previous_year = 'Vorjahr'):
    header = [first_cell]
    if n_columns == 3:
        header.append(f'{year}')
        header.append(f'{previous_year}')
    elif n_columns == 4:
        header.append(f'{year}')
        header.append(f'{year}')
        header.append(f'{previous_year}')
    elif n_columns == 5:
        header.append(f'{year}')
        header.append(f'{year}')
        header.append(f'{previous_year}')
        header.append(f'{previous_year}')
    rows.append(header)

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

if __name__ == '__main__':
    create_aktiva()