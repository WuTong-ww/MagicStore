"""Isolated public Web build. Never edits source imports or copies local secrets."""
import argparse,hashlib,html,json,os,re,shutil,struct,subprocess,time
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from pck_audit import audit_public

ROOT=Path(__file__).resolve().parents[1]
RUNTIME=('assets','data','scenes','scripts','themes','shaders','web')
COPY_KEYS={'title','loading','local','storage','progress','retry','failure','canvas'}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def copy_valid(raw):
    return (type(raw) is dict and set(raw)=={'version','copy'} and type(raw['version']) is int and raw['version']==1
            and type(raw['copy']) is dict and set(raw['copy'])==COPY_KEYS
            and all(type(s) is str and s.strip() and len(s)<300 for s in raw['copy'].values()))
def export_loading_font(copy,output):
    assert copy_valid(copy)
    font=TTFont(str(ROOT/'assets/fonts/LXGWWenKai-Regular.ttf'))
    font.recalcTimestamp=False
    options=subset.Options(); options.flavor='woff2'; options.name_IDs=['*']; options.name_legacy=True
    subsetter=subset.Subsetter(options=options); subsetter.populate(text=''.join(copy['copy'].values())); subsetter.subset(font)
    names={1:'Midnight Loading',3:'MidnightLoading-Regular-1',4:'Midnight Loading',6:'MidnightLoading',16:'Midnight Loading',25:'MidnightLoading'}
    for record in font['name'].names:
        if record.nameID in names: record.string=names[record.nameID].encode(record.getEncoding(),errors='replace')
    font.flavor='woff2'; font.save(str(output)); font.close()
def references(root):
    found=set()
    def visit(value):
        if isinstance(value,str) and value.startswith('res://'): found.add(value[6:])
        elif isinstance(value,dict):
            for child in value.values(): visit(child)
        elif isinstance(value,list):
            for child in value: visit(child)
    for path in (root/'data').rglob('*.json'):
        if 'art' not in path.relative_to(root/'data').parts: visit(json.loads(path.read_text(encoding='utf8')))
    for dirname in ('scripts','scenes','themes','shaders'):
        for path in (root/dirname).rglob('*'):
            if path.suffix in ('.gd','.tres','.tscn','.gdshader') and 'dev' not in path.parts:
                found.update(re.findall(r'res://([^"\s\'\)]+)',path.read_text(encoding='utf8')))
    return found
def excluded(path,optimized,refs,music):
    name=path.as_posix()
    if any(p.startswith('.') for p in path.parts) or path.suffix in ('.key','.pem','.env','.cfg'): return True
    if name.startswith(('assets/_incoming/','data/art/','scripts/dev/')) or name=='assets/ART_ASSET_MANIFEST.json': return True
    if name.startswith('assets/audio/music/') and not music: return True
    if optimized and name=='assets/fonts/NotoSansSC.ttf': return True
    if optimized and path.suffix=='.png':
        candidate=(name.startswith(('assets/generated_scenes/','assets/_legacy/'))
                   or 'reference' in path.stem or 'concept' in path.stem)
        if candidate and name not in refs: return True
    return False
def safe_reset(path):
    target=path.resolve(); expected=(ROOT/'.tools/r3-web/builds').resolve()
    assert target != expected and expected in target.parents, 'Build target must remain inside this task workspace'
    assert not target.exists(), 'Preserve previous build evidence; choose a new --attempt'
    target.mkdir(parents=True)
def run_engine(engine,stage,env,label,args,area):
    logfile=area/(label+'.log')
    started=time.monotonic()
    with logfile.open('w',encoding='utf8') as stream:
        code=subprocess.run([str(engine),'--headless','--path',str(stage)]+args,env=env,stdout=stream,stderr=subprocess.STDOUT).returncode
    errors=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:).*$',logfile.read_text(encoding='utf8',errors='replace'),re.M)
    result={'step':label,'exit_code':code,'seconds':round(time.monotonic()-started,3),'errors':errors,'log_sha256':sha(logfile)}
    print(json.dumps(result),flush=True)
    if code or errors: raise RuntimeError('Godot stage failed: '+label)
    return result
def build(variant='preview',baseline=False,music=False,attempt=''):
    label=variant+('-baseline' if baseline else '-optimized')+('-music' if music else '')
    if attempt:
        assert re.fullmatch('[a-z0-9-]+',attempt)
        label+='-'+attempt
    area=ROOT/'.tools/r3-web/builds'/label
    safe_reset(area)
    stage=area/'project'; output=area/'output'; stage.mkdir(); output.mkdir()
    refs=references(ROOT)
    skipped=[]; copied=0
    for dirname in RUNTIME:
        for path in (ROOT/dirname).rglob('*'):
            if not path.is_file(): continue
            rel=path.relative_to(ROOT)
            if excluded(rel,not baseline,refs,music):
                if path.suffix!='.import': skipped.append({'path':rel.as_posix(),'bytes':path.stat().st_size})
                continue
            # Never copy an import sidecar for an omitted original.
            if path.suffix=='.import' and excluded(Path(str(rel)[:-7]),not baseline,refs,music): continue
            dest=stage/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(str(path),str(dest)); copied+=1
    project=(ROOT/'project.godot').read_text(encoding='utf8')
    user_dir='MagicStorePreviewR3' if variant=='preview' else 'ZeroHourStore'
    project=re.sub(r'config/custom_user_dir_name="[^"]*"','config/custom_user_dir_name="'+user_dir+'"',project)
    (stage/'project.godot').write_text(project,encoding='utf8')
    compressed=[]
    if not baseline:
        for path in (stage/'assets').rglob('*.png.import'):
            original=Path(str(path)[:-7])
            with original.open('rb') as stream: header=stream.read(24)
            if len(header)<24 or header[:8]!=b'\x89PNG\r\n\x1a\n': continue
            width,height=struct.unpack('>II',header[16:24])
            # Tiny silhouettes/iris masks retain exact grayscale and alpha pixels.
            if max(width,height)<512 or '/parts/' in original.as_posix(): continue
            content=path.read_text(encoding='utf8')
            content=re.sub(r'compress/mode=\d+','compress/mode=1',content)
            content=re.sub(r'compress/lossy_quality=[0-9.]+','compress/lossy_quality=0.78',content)
            path.write_text(content,encoding='utf8'); compressed.append(original.relative_to(stage).as_posix())
    copy=json.loads((ROOT/'web/copy.json').read_text(encoding='utf8')); assert copy_valid(copy)
    shell=(ROOT/'web/shell.html').read_text(encoding='utf8')
    shell=shell.replace('$R3_FAILURE_JSON',json.dumps(copy['copy']['failure'],ensure_ascii=True))
    for key,value in copy['copy'].items(): shell=shell.replace('$R3_'+key.upper(),html.escape(value))
    # Keep the existing production root mount so its previous saves remain visible.
    mounts=['/userfs/'+user_dir] if variant=='preview' else ['/userfs']
    shell=shell.replace('$R3_PERSISTENT_PATHS',json.dumps(mounts))
    (stage/'web/shell.html').write_text(shell,encoding='utf8')
    template=(ROOT/'.tools/templates/web_nothreads_release.zip').resolve()
    assert template.is_file(), 'Run bootstrap.ps1 -WithWebExportTemplates'
    preset='''[preset.0]
name="Web Public"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="public_web"
export_filter="all_resources"
include_filter="data/*.json"
exclude_filter="web/*,assets/ART_ASSET_MANIFEST.json,*.env,*.key,*.pem"
export_path=""
script_export_mode=2
[preset.0.options]
custom_template/release="%s"
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=false
vram_texture_compression/for_mobile=false
html/export_icon=true
html/custom_html_shell="res://web/shell.html"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
progressive_web_app/ensure_cross_origin_isolation_headers=false
''' % template.as_posix()
    (stage/'export_presets.cfg').write_text(preset,encoding='utf8')
    env=os.environ.copy(); env.pop('SSLKEYLOGFILE',None)
    for name in ('APPDATA','LOCALAPPDATA','TEMP','TMP'):
        dest=area/'env'/name; dest.mkdir(parents=True,exist_ok=True); env[name]=str(dest)
    engine=ROOT/'.tools/godot/Godot_v4.6.3-stable_win64_console.exe'
    expected=json.loads((ROOT/'scripts/dev/toolchain.json').read_text())['version_output']
    assert subprocess.check_output([str(engine),'--version'],env=env).decode().strip()==expected
    stages=[run_engine(engine,stage,env,'import',['--import'],area),run_engine(engine,stage,env,'export',['--export-release','Web Public',str(output/'index.html')],area)]
    audit=audit_public(output/'index.pck',allow_music=music)
    (area/'package-audit.json').write_text(json.dumps(audit,indent=2)+'\n',encoding='utf8')
    if not baseline and not music:
        pack_root=area/'pack-root'; pack_root.mkdir()
        stages.append(run_engine(engine,pack_root,env,'pack-smoke',['--main-pack',str(output/'index.pck'),'--script',str(ROOT/'tests/export/r3_web_pack.gd')],area))
    shutil.copy2(str(ROOT/'web/wheel-focus.js'),str(output/'wheel-focus.js'))
    export_loading_font(copy,output/'loading.woff2')
    licenses=output/'licenses'; licenses.mkdir()
    for name in ('docs/GODOT-LICENSE.txt','docs/GODOT-COPYRIGHT.txt','docs/third-party.md','assets/fonts/LXGWWenKai-OFL.txt','assets/fonts/MidnightNumeric-OFL.txt','assets/audio/KENNEY-LICENSE.txt'):
        shutil.copy2(str(ROOT/name),str(licenses/Path(name).name))
    (output/'.nojekyll').write_text('',encoding='utf8')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=str(ROOT)).decode().strip()
    files=[{'path':p.relative_to(output).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(output.rglob('*')) if p.is_file()]
    dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=str(ROOT)).strip())
    info={'version':1,'commit':commit,'source_dirty':dirty,'engine':expected,'threads':False,'variant':variant,'music_included':music,'user_dir':user_dir,'persistent_paths':mounts,'files':files}
    (output/'build-info.json').write_text(json.dumps(info,ensure_ascii=True,indent=2)+'\n',encoding='utf8')
    report={'variant':label,'source_commit':commit,'copied_files':copied,'excluded':skipped,'lossy_imports':compressed,'stages':stages,'site_bytes':sum(p.stat().st_size for p in output.rglob('*') if p.is_file()),'files':files,'output':str(output),'music_included':music,'font_source_sha256':sha(ROOT/'assets/fonts/LXGWWenKai-Regular.ttf')}
    (area/'receipt.json').write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'output':str(output),'site_bytes':report['site_bytes'],'pck_bytes':(output/'index.pck').stat().st_size,'lossy_imports':len(compressed),'excluded_files':len(skipped)}),flush=True)
    return report
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--variant',choices=['preview','main'],default='preview'); parser.add_argument('--baseline',action='store_true'); parser.add_argument('--with-music',action='store_true'); parser.add_argument('--attempt',default='')
    args=parser.parse_args(); build(args.variant,args.baseline,args.with_music,args.attempt)
