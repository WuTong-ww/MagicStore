"""Restore the live complete Pages tree, replace one channel, preserve the other."""
import argparse,hashlib,json,shutil,time,urllib.error,urllib.parse,urllib.request
from pathlib import Path,PurePosixPath

BASE='https://wutong-ww.github.io/MagicStore/'
def digest(data): return hashlib.sha256(data).hexdigest()
def safe_name(name):
    if not isinstance(name,str) or not name: return False
    p=PurePosixPath(name)
    return bool(p.parts) and not p.is_absolute() and '..' not in p.parts and '\\' not in name and p.as_posix()==name and name!='site-manifest.json'
def valid_manifest(value):
    if type(value) is not dict or type(value.get('version')) is not int or value['version']!=1 or type(value.get('files')) is not list or not 0<len(value['files'])<=10000: return False
    if type(value.get('root_commit')) is not str or len(value['root_commit'])!=40 or any(c not in '0123456789abcdef' for c in value['root_commit']): return False
    names=set()
    for row in value['files']:
        if type(row) is not dict or set(row)!={'path','bytes','sha256'} or not safe_name(row['path']) or row['path'] in names: return False
        if type(row['bytes']) is not int or row['bytes']<0 or type(row['sha256']) is not str or len(row['sha256'])!=64 or any(c not in '0123456789abcdef' for c in row['sha256']): return False
        names.add(row['path'])
    return True
def download(name,optional=False):
    assert safe_name(name)
    for attempt in range(3):
        try:
            request=urllib.request.Request(BASE+urllib.parse.quote(name),headers={'User-Agent':'MagicStore-Pages-release','Cache-Control':'no-cache'})
            with urllib.request.urlopen(request,timeout=60) as response: return response.read()
        except urllib.error.HTTPError as error:
            if optional and error.code==404: return None
            if attempt==2: raise
        except OSError:
            if attempt==2: raise
        time.sleep(1)
def file_rows(folder):
    return [{'path':p.relative_to(folder).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p.read_bytes())}
            for p in sorted(folder.rglob('*')) if p.is_file() and p.name!='site-manifest.json']
def merge(build,output,variant,fetch=download,bootstrap=None):
    assert variant in ('preview','main')
    build=Path(build).resolve(); output=Path(output).resolve()
    assert build.is_dir() and (build/'index.html').is_file() and (build/'index.pck').is_file()
    assert output != build and output not in build.parents and build not in output.parents
    assert not output.exists(), 'Use a new staging tree; never delete an arbitrary directory'
    raw=fetch('site-manifest.json',True)
    if raw is None:
        assert bootstrap is not None
        manifest=json.loads(Path(bootstrap).read_text(encoding='utf8'))
    else: manifest=json.loads(raw)
    assert valid_manifest(manifest), 'Current live manifest is invalid; refusing to publish'
    output.mkdir(parents=True)
    for row in manifest['files']:
        data=fetch(row['path'])
        assert len(data)==row['bytes'] and digest(data)==row['sha256'], 'Live file changed: '+row['path']
        target=output/row['path']; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
    if raw is not None: assert fetch('site-manifest.json')==raw, 'Concurrent live site change'
    else:
        row=next(r for r in manifest['files'] if r['path']=='build-info.json')
        assert digest(fetch('build-info.json'))==row['sha256'], 'Official bootstrap is stale'
    before=file_rows(output)
    preserved=[row for row in before if row['path'].startswith('preview/')==(variant=='main')]
    info=json.loads((build/'build-info.json').read_text(encoding='utf8'))
    assert info.get('variant')==variant and info.get('music_included') is False and info.get('source_dirty') is False, 'Only clean public builds can be published'
    if variant=='preview':
        target=output/'preview'
        assert target.resolve().parent==output and target.name=='preview'
        if target.exists(): shutil.rmtree(str(target))
        shutil.copytree(str(build),str(target))
    else:
        for child in list(output.iterdir()):
            if child.name=='preview': continue
            assert output in child.resolve().parents
            if child.is_dir(): shutil.rmtree(str(child))
            else: child.unlink()
        for child in build.iterdir():
            assert child.name!='preview'
            if child.is_dir(): shutil.copytree(str(child),str(output/child.name))
            else: shutil.copy2(str(child),str(output/child.name))
    after=file_rows(output); lookup={r['path']:r for r in after}
    assert all(lookup.get(row['path'])==row for row in preserved), 'Other channel was modified'
    result={'version':1,'root_commit':info['commit'] if variant=='main' else manifest['root_commit'],
            'preview_commit':info['commit'] if variant=='preview' else manifest.get('preview_commit'),
            'files':after,'preserved_channel':'root' if variant=='preview' else 'preview','preserved_files':len(preserved)}
    assert valid_manifest(result)
    (output/'site-manifest.json').write_text(json.dumps(result,ensure_ascii=True,indent=2)+'\n',encoding='utf8')
    return result
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--build',type=Path,required=True); parser.add_argument('--output',type=Path,required=True); parser.add_argument('--variant',choices=['main','preview'],required=True)
    args=parser.parse_args(); result=merge(args.build,args.output,args.variant,bootstrap=Path(__file__).resolve().parents[1]/'web/official-bootstrap.json')
    print(json.dumps({'root_commit':result['root_commit'],'preview_commit':result['preview_commit'],'preserved_channel':result['preserved_channel'],'preserved_files':result['preserved_files'],'total_bytes':sum(r['bytes'] for r in result['files'])}))
