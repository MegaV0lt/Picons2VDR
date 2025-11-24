import argparse
import sys
import unicodedata

"""
normalize_text.py

Dieses Skript liest eine Index-Datei, entfernt führende und folgende Whitespaces
je Zeile und normalisiert die Zeichen nach Unicode NFC (siehe
`unicodedata.normalize('NFC', ...)`).

Standardmäßig liest das Skript `picons.git/build-source/utf8snp.index` und
schreibt die normalisierte Ausgabe nach `/tmp/utf8snp.nfc.index`.

Du kannst aber Eingabe- und Ausgabepfade per Kommandozeile angeben:
  python3 normalize_text.py -i path/to/input.index -o /tmp/output.index

Die Quelldatei wird niemals verändert; nur die angegebene Ausgabedatei wird
geschrieben.
"""

SOURCE_PATH = 'picons.git/build-source/utf8snp.index'
DEST_PATH = '/tmp/utf8snp.nfc.index'


def normalize_file(source: str, dest: str) -> None:
    """Liest `source`, normalisiert jede Zeile nach NFC und schreibt nach `dest`.

    Raises FileNotFoundError when `source` does not exist.
    """
    with open(source, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    normalized_lines = [unicodedata.normalize('NFC', line.strip()) + '\n' for line in lines]

    with open(dest, 'w', encoding='utf-8') as out:
        out.writelines(normalized_lines)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description='Normalize text file lines to Unicode NFC')
    parser.add_argument('-i', '--input', default=SOURCE_PATH,
                        help='Input file path (default: %(default)s)')
    parser.add_argument('-o', '--output', default=DEST_PATH,
                        help='Output file path (default: %(default)s)')
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    try:
        normalize_file(args.input, args.output)
    except FileNotFoundError:
        print(f"Eingabedatei nicht gefunden: {args.input}", file=sys.stderr)
        return 2
    except PermissionError:
        print(f"Keine Schreibberechtigung für Ausgabe: {args.output}", file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
