#!/usr/bin/env python3
"""Render this project's deliberately simple Markdown guide, without external assets."""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'docs/UserGuide.md'
# Old guide paths are small Markdown navigation wrappers after the module move.
# Resolve their explicit local target so historical render commands still update
# the canonical guide, rather than replacing the HTML compatibility redirect.
for _ in range(4):
    forwarding = re.search(r'^<!-- canonical-guide: (.+) -->$', SOURCE.read_text(), re.MULTILINE)
    if not forwarding:
        break
    target = (SOURCE.parent / forwarding.group(1)).resolve()
    if not target.is_relative_to(ROOT) or not target.is_file() or target == SOURCE:
        raise SystemExit('Invalid canonical guide target')
    SOURCE = target
else:
    raise SystemExit('Too many canonical guide forwards')

def inline(text):
    text = html.escape(text)
    def link(match):
        label, target = match.groups()
        if target.startswith(('https://', 'http://')) or (':' not in target and not target.startswith('//')):
            return '<a href="' + target + '">' + label + '</a>'
        return match.group(0)
    text = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', link, text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    return re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)

lines = SOURCE.read_text().splitlines()
title = next((line[2:] for line in lines if line.startswith('# ')), SOURCE.stem)
date_match = re.search(r'20\d{2}-\d{2}-\d{2}', '\n'.join(lines[:8]))
revision = date_match.group().replace('-', '.') if date_match else '日期见正文'
out, navigation = [], []
i = 0
while i < len(lines):
    s = lines[i]
    if not s.strip():
        i += 1
        continue
    if s.startswith('```'):
        code = []
        i += 1
        while i < len(lines) and not lines[i].startswith('```'):
            code.append(lines[i]); i += 1
        out.append('<pre><code>' + html.escape('\n'.join(code)) + '</code></pre>')
    elif s.startswith('# '):
        out.append('<div class="eyebrow">CLAUDE / LOCAL NETWORK</div><h1>' + inline(s[2:]) + '</h1>')
    elif s.startswith('## '):
        anchor = 'section-' + str(len(navigation) + 1)
        navigation.append('<a href="#' + anchor + '">' + inline(s[3:]) + '</a>')
        out.append('<h2 id="' + anchor + '">' + inline(s[3:]) + '</h2>')
    elif s.startswith('|'):
        rows = []
        while i < len(lines) and lines[i].startswith('|'):
            cells = [x.strip() for x in lines[i].strip('|').split('|')]
            if not all(re.fullmatch(r':?-+:?', c) for c in cells):
                tag = 'th' if not rows else 'td'
                rows.append('<tr>' + ''.join('<'+tag+'>'+inline(c)+'</'+tag+'>' for c in cells) + '</tr>')
            i += 1
        out.append('<div class="table-wrap"><table>' + ''.join(rows) + '</table></div>')
        continue
    elif s.startswith('- ') or re.match(r'^\d+\. ', s):
        ordered = not s.startswith('- ')
        tag = 'ol' if ordered else 'ul'
        items = []
        while i < len(lines) and (re.match(r'^\d+\. ', lines[i]) if ordered else lines[i].startswith('- ')):
            items.append('<li>' + inline(re.sub(r'^(?:\d+\.|-) ', '', lines[i])) + '</li>')
            i += 1
        out.append('<' + tag + '>' + ''.join(items) + '</' + tag + '>')
        continue
    else:
        out.append('<p>' + inline(s) + '</p>')
    i += 1

css = '''
:root{color-scheme:light;--ink:#142f35;--muted:#607579;--line:#dbe4e2;--accent:#1b665a}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:30px}body{margin:0;background:#f5f7f3;color:var(--ink);font:16px/1.85 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}
.layout{max-width:1380px;margin:auto;display:grid;grid-template-columns:260px minmax(0,1fr);gap:48px;padding:48px 36px}aside{position:sticky;top:32px;align-self:start;font-size:13px;border-top:3px solid var(--accent);padding-top:20px}aside b{font-size:17px}aside a{display:block;padding:8px 0;color:var(--muted);text-decoration:none;line-height:1.5}aside a:hover{color:var(--accent)}.tag{display:inline-block;background:#e1ede5;border-radius:20px;padding:3px 12px;font-size:12px;margin:16px 0}
main{min-width:0;background:#fff;padding:42px 48px;border:1px solid var(--line);border-radius:12px}.eyebrow{font-size:11px;letter-spacing:.18em;color:var(--accent);font-weight:700}h1{font-size:36px;letter-spacing:-.04em;line-height:1.3;margin:16px 0 24px}h2{font-size:23px;line-height:1.5;margin:54px 0 20px;padding-top:22px;border-top:1px solid var(--line)}p{margin:14px 0}strong{color:#0b5548}a{color:var(--accent);text-underline-offset:3px}li{margin:10px 0}pre{padding:23px;background:#102e32;color:#e8f4ed;border-radius:8px;font:13px/1.75 ui-monospace,SFMono-Regular,monospace;overflow:auto}p code,li code{font-size:.86em;background:#edf3ef;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}.table-wrap{overflow-x:auto;margin:24px 0}table{width:100%;border-collapse:collapse;font-size:14px;line-height:1.7}th{background:#eef4ef;text-align:left;font-size:12px;letter-spacing:.02em}td,th{padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:top}td:first-child{font-weight:600;min-width:120px}footer{color:var(--muted);font-size:12px;margin-top:40px}button{font:inherit;font-size:13px;border:1px solid #afc5bc;border-radius:6px;padding:8px 14px;color:var(--ink);background:white;cursor:pointer}
@media(max-width:900px){.layout{display:block;padding:18px;}.layout aside{position:static;margin-bottom:22px}aside nav{display:none}main{padding:24px}h1{font-size:28px}h2{font-size:21px}body{font-size:15px}}
@media print{body{background:white;font-size:11pt}.layout{display:block;padding:0}aside{display:none}main{border:0;padding:0}h1{font-size:25pt}h2{break-after:avoid;margin-top:28px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f2f5f3;color:#111}tr{break-inside:avoid}a{color:inherit}.table-wrap{overflow:visible}}
'''
is_english = SOURCE.stem.endswith('.en')
document = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+html.escape(title)+'</title><style>'+css+'</style></head><body><div class="layout"><aside><b>Watcher 使用说明</b><br><span class="tag">'+html.escape(revision)+' · 文档日期</span><nav>'+''.join(navigation)+'</nav><p><button onclick="window.print()">打印 / 保存 PDF</button></p></aside><main>'+''.join(out)+'<footer>Claude Connection Watcher · Local-first · 无外部字体、脚本或追踪资源<br>后续更新请维护 Markdown 源文件并运行 scripts/render-guide.py。</footer></main></div></body></html>'
page_title = next((line[2:] for line in lines if line.startswith('# ')), SOURCE.stem)
document = document.replace('<title>'+html.escape(title)+'</title>', '<title>' + html.escape(page_title) + '</title>')
if is_english:
    document = document.replace('lang="zh-CN"', 'lang="en"').replace('Watcher 使用说明','Watcher User Guide').replace('文档日期','Document date').replace('打印 / 保存 PDF','Print / Save PDF').replace('无外部字体、脚本或追踪资源','No external fonts, scripts, or tracking').replace('后续更新请维护 Markdown 源文件并运行 scripts/render-guide.py。','Update the Markdown source and run scripts/render-guide.py to maintain this guide.')
SOURCE.with_suffix('.html').write_text(document)
print('Rendered guide:', len(navigation), 'sections')
