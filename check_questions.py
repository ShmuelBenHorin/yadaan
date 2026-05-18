import json, sys

def check_file(name, path):
    content = open(path, encoding='utf-8').read()
    tq = "'''"
    start = content.index(tq) + 3
    end   = content.rindex(tq)
    raw = content[start:end].strip().rstrip(',')
    json_str = '[' + raw + ']'
    lines = json_str.splitlines()

    # Try to parse each object line independently
    errors = []
    for i, line in enumerate(lines):
        line = line.strip().rstrip(',')
        if not line or line in ('[', ']'):
            continue
        try:
            json.loads(line)
        except json.JSONDecodeError as e:
            errors.append((i+1, e.colno, e.msg, lines[i]))

    if not errors:
        # Full parse to confirm
        try:
            data = json.loads(json_str)
            print(f'[{name}] OK — {len(data)} questions')
        except json.JSONDecodeError as e:
            print(f'[{name}] Full-parse ERROR at line {e.lineno}, col {e.colno}: {e.msg}')
    else:
        print(f'[{name}] {len(errors)} error(s) found:')
        for lineno, col, msg, text in errors:
            print(f'  Line {lineno}, col {col}: {msg}')
            print(f'    {text[:200]}')
            # highlight the error position
            safe = text[:col-1] + ' <<!>>' + text[col-1:]
            print(f'    {safe[:210]}')
            print()

check_file('easy',   'lib/questions_easy.dart')
check_file('medium', 'lib/questions_medium.dart')
check_file('hard',   'lib/questions_hard.dart')
