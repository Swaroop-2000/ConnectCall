import json
p = r'C:\Users\rswar\.gemini\antigravity\brain\5ff3872e-66c6-4b13-808f-95626c704d3b\.system_generated\logs\transcript_full.jsonl'
files = {}
for line in open(p, encoding='utf-8'):
    if 'The following code has been modified' in line:
        try:
            d = json.loads(line)
            c = d.get('content', '')
            if 'Showing lines 1 to ' in c and 'File Path: ' in c:
                tf = c.split('File Path: ')[1].split('\n')[0].strip().replace(chr(96), '').replace('file:///', '').replace('%20', ' ')
                if 'lib/screens' in tf.lower():
                    lines_part = c.split('leading space.\n')[1].split('\nThe above content')[0]
                    original_lines = []
                    for l in lines_part.split('\n'):
                        if ': ' in l:
                            original_lines.append(l.split(': ', 1)[1])
                        else:
                            original_lines.append(l)
                    content = '\n'.join(original_lines)
                    if tf not in files or len(content) > len(files[tf]):
                        files[tf] = content
        except Exception as e: pass

for tf, content in files.items():
    if len(content) > 10:
        print('Saving', tf, len(content))
        open(tf, 'w', encoding='utf-8').write(content)
