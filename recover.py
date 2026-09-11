import json, os, glob
files = {}
for p in glob.glob(r'C:\Users\rswar\.gemini\antigravity\brain\*\.system_generated\logs\*.jsonl'):
    for line in open(p, encoding='utf-8'):
        try:
            d = json.loads(line)
            if 'tool_calls' in d:
                for t in d['tool_calls']:
                    if t['name'].endswith('write_to_file'):
                        args = t.get('arguments') or t.get('args')
                        if isinstance(args, str): args = json.loads(args)
                        tf = args.get('TargetFile', '').replace('\\\\', '/').strip('\"\'')
                        if 'lib/screens' in tf:
                            files[tf] = args.get('CodeContent', '')
                    elif t['name'].endswith('replace_file_content'):
                        args = t.get('arguments') or t.get('args')
                        if isinstance(args, str): args = json.loads(args)
                        tf = args.get('TargetFile', '').replace('\\\\', '/').strip('\"\'')
                        if 'lib/screens' in tf:
                            if tf in files:
                                files[tf] = files[tf].replace(args['TargetContent'], args['ReplacementContent'])
        except Exception as e: pass

print(f'Found {len(files)} files')
for f, c in files.items():
    print(f'Recovered {f} ({len(c)} bytes)')
    os.makedirs(os.path.dirname(f), exist_ok=True)
    open(f, 'w', encoding='utf-8').write(c)
