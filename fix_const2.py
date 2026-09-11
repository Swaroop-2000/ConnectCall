import os, re
d='lib/screens'
widgets=['Text','Center','Column','Padding','Row','Icon','CircularProgressIndicator','LinearGradient','BoxDecoration','SliverToBoxAdapter','\[']
for r,_,fs in os.walk(d):
    for f in fs:
        if f.endswith('.dart'):
            p = os.path.join(r, f)
            c = open(p, encoding='utf-8').read()
            # replace const [Widget] with [Widget]
            for w in widgets:
                if w == '\[':
                    c = re.sub(r'const\s+\[', '[', c)
                else:
                    c = re.sub(r'const\s+' + w, w, c)
            open(p, 'w', encoding='utf-8').write(c)
