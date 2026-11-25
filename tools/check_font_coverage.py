# -*- coding: utf-8 -*-
"""Finite source-corpus/cmap preflight. Does not render text or emit payloads."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from fontTools.ttLib import TTFont

ROOT=Path(__file__).resolve().parents[1]
GD=re.compile('|'.join([r'#[^\n]*',r'"""[\s\S]*?"""',r"'''[\s\S]*?'''",r'"(?:\\.|[^"\\])*"',r"'(?:\\.|[^'\\])*'"]))
CJK_RANGES=((0x3400,0x4DBF),(0x4E00,0x9FFF),(0xF900,0xFAFF),(0x20000,0x2FA1F),(0x30000,0x33FFF))

def scalar(cp):
    return 0<=cp<=0x10FFFF and not 0xD800<=cp<=0xDFFF

def cjk(cp):
    return cp==0x3007 or any(low<=cp<=high for low,high in CJK_RANGES)

def harvested(value):
    result={ord(c) for c in value if scalar(ord(c))}
    for token in re.findall(r'\\u([0-9a-fA-F]{4})',value):
        cp=int(token,16)
        if scalar(cp): result.add(cp)
    for token in re.findall(r'\\U([0-9a-fA-F]{6,8})',value):
        for length in (6,8):
            if len(token)>=length and scalar(int(token[:length],16)): result.add(int(token[:length],16))
    for token in re.findall(r'\\u\{([0-9a-fA-F]{1,6})\}',value):
        if scalar(int(token,16)): result.add(int(token,16))
    for high,low in re.findall(r'\\u([dD][89aAbB][0-9a-fA-F]{2})\\+u([dD][cCdDeEfF][0-9a-fA-F]{2})',value):
        result.add(0x10000+((int(high,16)-0xD800)<<10)+int(low,16)-0xDC00)
    for i in range(len(value)-1):
        a,b=ord(value[i]),ord(value[i+1])
        if 0xD800<=a<=0xDBFF and 0xDC00<=b<=0xDFFF: result.add(0x10000+((a-0xD800)<<10)+b-0xDC00)
    return result

def json_strings(value,nested=0):
    if isinstance(value,dict):
        for key,item in value.items():
            yield str(key)
            yield from json_strings(item,nested)
    elif isinstance(value,list):
        for item in value: yield from json_strings(item,nested)
    elif isinstance(value,str):
        yield value
        if nested<4 and value.lstrip().startswith(('{','[')):
            try: child=json.loads(value)
            except (ValueError,TypeError): return
            if isinstance(child,(dict,list)): yield from json_strings(child,nested+1)

def gd_strings(value):
    for match in GD.finditer(value):
        literal=match.group()
        if literal.startswith('#'): continue
        n=3 if literal.startswith(('"""',"'''")) else 1
        yield literal[n:-n]

def source_paths(root):
    raw=subprocess.check_output(['git','-C',str(root),'ls-files','--cached','--others','--exclude-standard','-z'])
    names=set(raw.decode('utf-8').split('\0'))
    return sorted(name for name in names if Path(name).suffix.casefold() in ('.json','.gd') and not name.startswith(('.tools/','.godot/','.git/')))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def font_policy(value):
    if not isinstance(value,dict) or set(value)!={'version','regular','ascii_mono','ascii_range','required_digits'}: raise ValueError('font policy shape')
    if type(value['version']) is not int or value['version']!=1: raise ValueError('font policy version')
    for key in ('regular','ascii_mono'):
        path=value[key]
        if not isinstance(path,str) or not path.startswith('res://assets/fonts/') or not path.endswith('.ttf') or '\\' in path or any(p in ('','.','..') for p in path[6:].split('/')): raise ValueError('font policy path')
    if value['regular']==value['ascii_mono'] or value['ascii_range']!=[32,126] or any(type(n) is not int for n in value['ascii_range']) or value['required_digits']!='0123456789:': raise ValueError('font policy values')
    return value

def inspect(root,paths=None):
    root=Path(root).resolve()
    names=source_paths(root) if paths is None else sorted(paths)
    before={name:sha(root/name) for name in names}
    corpus=set();errors=[];counts={'json':0,'gd':0,'tests':0,'fixtures_json':0}
    for name in names:
        path=(root/name).resolve()
        if root not in path.parents: raise ValueError('source outside root')
        text=path.read_text(encoding='utf-8-sig')
        counts['tests']+=int(name.startswith('tests/'))
        counts['fixtures_json']+=int(name.startswith('tests/fixtures/') and path.suffix=='.json')
        if path.suffix.casefold()=='.json':
            counts['json']+=1
            try: values=json_strings(json.loads(text))
            except ValueError as error:
                errors.append({'path':name,'kind':type(error).__name__});values=[text]
        else:
            counts['gd']+=1;values=gd_strings(text)
        for value in values: corpus.update(cp for cp in harvested(value) if cjk(cp))
    policy=font_policy(json.loads((root/'data/ui/font_policy.json').read_text(encoding='utf-8-sig')))
    fonts=[];union=set();ascii_advances={}
    for key in ('ascii_mono','regular'):
        path=root/policy[key][6:];digest=sha(path)
        font=TTFont(path,lazy=False);cmap=font.getBestCmap() or {};union.update(cmap)
        if key=='ascii_mono':
            ascii_advances={str(cp):font['hmtx'][cmap[cp]][0] for cp in range(32,127) if cp in cmap}
            ascii_exact=set(cmap)==set(range(32,127))
            renamed=font['name'].getDebugName(1)=='Midnight Numeric'
        fonts.append({'role':key,'path':policy[key][6:],'sha256':digest,'cmap_count':len(cmap)})
        font.close()
        if sha(path)!=digest: raise ValueError('font changed during scan')
    unchanged=all(sha(root/name)==digest for name,digest in before.items())
    missing=[{'codepoint':'U+%04X'%cp,'char':chr(cp)} for cp in sorted(corpus-union)]
    ascii_mono=ascii_exact and renamed and len(ascii_advances)==95 and len(set(ascii_advances.values()))==1
    return {'format':'font_coverage_v1','scope':'finite repository JSON/GD CJK literals and conservative escapes; no rendering claim','source_files':len(names),'counts':counts,'cjk_codepoints':len(corpus),'missing':missing,'missing_count':len(missing),'fonts':fonts,'ascii_subset_exact':ascii_exact,'ascii_subset_renamed':renamed,'ascii_monospace':ascii_mono,'parse_errors':errors,'sources_unchanged':unchanged,'payload_text_serialized':False,'success':not errors and not missing and ascii_mono and unchanged}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    try: report=inspect(args.root)
    except (ValueError,OSError,KeyError,subprocess.SubprocessError) as error:
        # Do not serialize exceptions which could include a source text payload.
        report={'format':'font_coverage_v1','success':False,'error_kind':type(error).__name__}
    encoded=json.dumps(report,ensure_ascii=True,indent=2)+'\n'
    if args.report: args.report.write_bytes(encoded.encode('utf-8'))
    print(encoded,end='')
    return 0 if report['success'] else 1

if __name__=='__main__':raise SystemExit(main())
