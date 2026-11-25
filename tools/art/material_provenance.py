# -*- coding: utf-8 -*-
"""Bounded POLISH material provenance candidate. No file writes or generation."""
import copy
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
from PIL import Image

CATALOG_PATH='data/art/polish_material_prompts.json'
CONFIG_PATH='data/ui/panel_materials.json'
IDS=('notebook','letter','paper_cream','paper_blue','paper_lilac','tag_cream','tag_blue',
     'tag_lilac','tag_neutral','wax_seal','paper_tag','red_stamp','vine')
PATHS={key:'assets/ui/material_v3/'+key+'.png' for key in IDS}
LEGACY={
    'legacy_s04_slot':('assets/generated_scenes/v2/slices/S04_slot.png','0b83e16bf7a2c6617adf8fc51777fdb46abc2eaec3f8ac1e5217ca320c70eb2a'),
    'legacy_s04_door_closed':('assets/generated_scenes/v2/slices/S04_door_closed.png','0a40c4090321ca1404c37563a407bf6e92a62ed02a362044b6d073bad6c83d5c'),
}
WOOD_PATH='res://assets/ui/title_wood_sign.png'

def require(ok,message):
    if not ok:raise ValueError(message)

def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode('utf-8')

def entry_hash(value):return hashlib.sha256(canonical(value)).hexdigest()

def integral(value,low=0,high=math.inf):
    return (type(value) is int and low<=value<=high) or (type(value) is float and math.isfinite(value) and
            low<=value<=high and value==math.floor(value))

def keys(value,names):return isinstance(value,dict) and set(value)==set(names)

def digest_text(value):
    return isinstance(value,str) and len(value)==64 and all(c in '0123456789abcdef' for c in value)

def safe_path(workspace,value):
    require(isinstance(value,str) and value and '\\' not in value and ':' not in value and
            not PurePosixPath(value).is_absolute() and all(p not in ('','.','..') for p in value.split('/')),'unsafe material path')
    root=Path(workspace).resolve();path=(root/value).resolve()
    require(path.is_relative_to(root) and path!=root,'material path escapes workspace')
    return path

def _object(pairs):
    result={}
    for key,value in pairs:
        require(key not in result,'duplicate material JSON key');result[key]=value
    return result

def strict_json(path):
    require(path.is_file(),'missing local material data')
    return json.loads(path.read_text(encoding='utf-8-sig'),object_pairs_hook=_object,
                      parse_constant=lambda _:(_ for _ in ()).throw(ValueError('nonfinite material JSON')))

def validate_asset_entry(value,asset_id,require_ready=True):
    """Validate the agreed native-pixel asset projection, not the whole UI theme."""
    require(asset_id in PATHS or asset_id=='wood','unknown material asset ID')
    expected={'path','mode','region','margins','native_size'}|({'book_regions'} if asset_id=='notebook' else set())
    require(keys(value,expected),'material asset shape')
    expected_path=WOOD_PATH if asset_id=='wood' else 'res://'+PATHS[asset_id]
    require(value['path']==expected_path,'material asset path')
    require(value['mode']=='book' if asset_id=='notebook' else value['mode'] in ('nine_slice','texture'),'material rendering mode')
    native=value['native_size'];region=value['region'];margins=value['margins']
    require(isinstance(native,list) and len(native)==2 and all(integral(n,0,16384) for n in native),'native material dimensions')
    ready=all(n>0 for n in native)
    require(ready or native==[0,0],'partial native size is invalid')
    require(not require_ready or ready,'pending material cannot be registered')
    require(isinstance(region,list) and len(region) in (0,4) and all(integral(n,0,16384) for n in region),'material source region')
    if region:require(region[2]>0 and region[3]>0,'empty material source region')
    require(isinstance(margins,list) and len(margins)==4 and all(integral(n,0,16384) for n in margins),'source-pixel margins')
    if ready:
        if region:require(region[0]+region[2]<=native[0] and region[1]+region[3]<=native[1],'region outside native source')
        width,height=region[2:] if region else native
        require(margins[0]+margins[2]<width and margins[1]+margins[3]<height,'margins consume the source region')
    if asset_id=='notebook':
        pages=value['book_regions'];require(keys(pages,('left','spine','right')),'book region keys')
        for rect in pages.values():
            require(isinstance(rect,list) and len(rect)==4 and all(type(n) in (int,float) and math.isfinite(n) and 0<=n<=1 for n in rect) and
                    rect[2]>0 and rect[3]>0 and rect[0]+rect[2]<=1 and rect[1]+rect[3]<=1,'normalized book region')
        require(all(math.isclose(a,b,rel_tol=0,abs_tol=1e-9) for a,b in (
                (pages['left'][0],0),(pages['left'][0]+pages['left'][2],pages['spine'][0]),
                (pages['spine'][0]+pages['spine'][2],pages['right'][0]),
                (pages['right'][0]+pages['right'][2],1))),'book regions overlap, leave a gap or reorder')
        if ready:
            for key in ('left','right'):
                require(margins[0]+margins[2]<width*pages[key][2] and margins[1]+margins[3]<height*pages[key][3],
                        'book margins consume a page; never stretch the spine across the panel')
    return value

def runtime_assets(config,require_ready=True):
    require(isinstance(config,dict) and integral(config.get('version'),1,1) and
            keys(config.get('assets'),set(IDS)|{'wood'}),'runtime material asset projection')
    for key,value in config['assets'].items():validate_asset_entry(value,key,require_ready)
    return config['assets']

def validate_material_prompts(value):
    require(keys(value,('type','version','runtime_config','entries','legacy_entries')) and value['type']=='r3_polish_material_v1' and
            type(value['version']) is int and value['version']==1 and value['runtime_config']==CONFIG_PATH,'material catalog protocol')
    require(keys(value['entries'],IDS) and keys(value['legacy_entries'],LEGACY),'material catalog bounded entries')
    fields={'path','sha256','dim','version','group','status','prompt','source','review','runtime_asset','runtime_asset_sha256'}
    for key,row in value['entries'].items():
        require(keys(row,fields) and row['path']==PATHS[key] and row['group']=='polish_materials' and
                row['status']=='selected_material_source','material full-row identity')
        require(digest_text(row['sha256']) and type(row['version']) is int and 1<=row['version']<=4,'material SHA/version')
        require(isinstance(row['dim'],list) and len(row['dim'])==2 and all(type(n) is int and n>0 for n in row['dim']),'material native size')
        require(isinstance(row['prompt'],str) and row['prompt'].strip(),'material exact prompt')
        require(keys(row['source'],('generator','record_id')) and row['source']['generator']=='builtin_imagegen' and
                row['source']['record_id']=='R3_POLISH_MATERIAL_'+key+'_v'+str(row['version']),'material generation source')
        review=row['review']
        require(keys(review,('opened','score')) and review['opened'] is True and type(review['score']) is int and 8<=review['score']<=10,
                'unselected or unreviewed material cannot be registered')
        validate_asset_entry(row['runtime_asset'],key,True)
        require(row['runtime_asset']['native_size']==row['dim'] and digest_text(row['runtime_asset_sha256']) and
                entry_hash(row['runtime_asset'])==row['runtime_asset_sha256'],'material margins/region identity hash')
    for key,row in value['legacy_entries'].items():
        require(isinstance(row,dict) and row.get('path')==LEGACY[key][0] and entry_hash(row)==LEGACY[key][1],
                'historical full row must remain semantically exact')
    return value

def is_material_asset(asset):
    if not isinstance(asset,dict):return False
    path=asset.get('path');group=asset.get('group');reference=asset.get('prompt_reference')
    return (isinstance(path,str) and (path.casefold().startswith('assets/ui/material_v3/') or
            path.casefold() in {p.casefold() for p,_ in LEGACY.values()})) or \
           (isinstance(group,str) and group.casefold()=='polish_materials') or \
           (isinstance(reference,dict) and isinstance(reference.get('path'),str) and reference['path'].casefold()==CATALOG_PATH.casefold())

def resolve_material_provenance(workspace,asset):
    require(isinstance(asset,dict),'material compact row')
    reference=asset.get('prompt_reference')
    require(keys(reference,('path','key','sha256')) and reference['path']==CATALOG_PATH and
            isinstance(reference['key'],str) and reference['key'] in set(IDS)|set(LEGACY) and digest_text(reference['sha256']),
            'material reference scope/shape')
    key=reference['key'];legacy=key in LEGACY
    fields={'path','sha256','dim','group'}|(set() if legacy else {'version'})
    require(set(asset)==fields|{'prompt_reference'},'material compact row fields')
    catalog=validate_material_prompts(strict_json(safe_path(workspace,CATALOG_PATH)))
    row=catalog['legacy_entries' if legacy else 'entries'][key]
    require(canonical({k:asset[k] for k in fields})==canonical({k:row[k] for k in fields}) and
            entry_hash(row)==reference['sha256'],'material canonical reference/identity mismatch')
    if not legacy:
        authority=runtime_assets(strict_json(safe_path(workspace,CONFIG_PATH)),True)
        require(canonical(authority[key])==canonical(row['runtime_asset']),'runtime margins differ from registered authority entry')
    return copy.deepcopy(row)

def propose_registry(workspace,selected_rows,runtime_config,current_manifest):
    """Root supplies all reviewed selections. Preflight all inputs; return only."""
    require(keys(selected_rows,IDS),'all 13 explicit root selections are required')
    authority=runtime_assets(runtime_config,True)
    catalog={'type':'r3_polish_material_v1','version':1,'runtime_config':CONFIG_PATH,'entries':{},'legacy_entries':{}}
    for key in IDS:
        selection=selected_rows[key]
        require(keys(selection,('sha256','dim','version','prompt','review')),'explicit material selection shape')
        row=copy.deepcopy(selection)
        row.update(path=PATHS[key],group='polish_materials',status='selected_material_source',
                   source={'generator':'builtin_imagegen','record_id':'R3_POLISH_MATERIAL_'+key+'_v'+str(selection['version'])},
                   runtime_asset=copy.deepcopy(authority[key]),runtime_asset_sha256=entry_hash(authority[key]))
        catalog['entries'][key]=row
    require(isinstance(current_manifest,dict) and isinstance(current_manifest.get('assets'),list),'current manifest shape')
    require(all(isinstance(row,dict) and isinstance(row.get('path'),str) for row in current_manifest['assets']),
            'invalid current manifest row')
    require(len({row['path'].casefold() for row in current_manifest['assets']})==len(current_manifest['assets']),
            'duplicate current manifest path')
    for row in current_manifest['assets']:
        if is_material_asset(row):
            require(row['path'] in set(PATHS.values())|{p for p,_ in LEGACY.values()},'unregistered material namespace path')
    by_path={row['path']:row for row in current_manifest['assets']}
    for key,(path,_) in LEGACY.items():
        require(path in by_path,'historical row missing')
        row=by_path[path]
        catalog['legacy_entries'][key]=resolve_material_provenance(workspace,row) if 'prompt_reference' in row else copy.deepcopy(row)
    validate_material_prompts(catalog)
    bytes_total=0
    for key in IDS:
        path=safe_path(workspace,PATHS[key]);require(path.is_file(),'selected material file missing')
        before=path.stat();raw=path.read_bytes();require(hashlib.sha256(raw).hexdigest()==catalog['entries'][key]['sha256'],'selected material file SHA mismatch')
        with Image.open(io.BytesIO(raw)) as image:
            require(image.format=='PNG' and list(image.size)==catalog['entries'][key]['dim'],'selected native PNG dimensions differ')
            image.verify()
        after=path.stat();require((before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns),'source changed during proposal')
        bytes_total+=len(raw)
    result=copy.deepcopy(current_manifest)
    compact={}
    for key,row in {**catalog['legacy_entries'],**catalog['entries']}.items():
        fields=('path','sha256','dim','group') if key in LEGACY else ('path','sha256','dim','version','group')
        compact[row['path']]={field:copy.deepcopy(row[field]) for field in fields}
        compact[row['path']]['prompt_reference']={'path':CATALOG_PATH,'key':key,'sha256':entry_hash(row)}
    result['assets']=[compact.pop(row['path'],row) for row in result['assets']]
    result['assets'].extend(compact.values())
    encoded=(json.dumps(result,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n').encode('utf-8')
    require(len(encoded)<=500000,'unchanged central manifest budget exceeded')
    return {'manifest':result,'catalog':catalog,'central_bytes':len(encoded),'new_material_bytes':bytes_total}
