"""Verified encrypted build-source bundle; no keys or build inputs in exports."""
import argparse,hashlib,json,os,re,tempfile,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CONFIG=ROOT/'data/web_audio_build.json'

def digest(data): return hashlib.sha256(data).hexdigest()
def valid(value):
    if type(value) is not dict or set(value)!={'version','encrypted_path','encrypted_sha256','archive_sha256','tracks'} or type(value['version']) is not int or value['version']!=1: return False
    if not isinstance(value['encrypted_path'],str) or not re.fullmatch(r'build-sources/music/[a-z0-9-]+\.fernet',value['encrypted_path']): return False
    if not isinstance(value['encrypted_sha256'],str) or not re.fullmatch(r'[a-f0-9]{64}',value['encrypted_sha256']): return False
    if not isinstance(value['archive_sha256'],str) or not re.fullmatch(r'[a-f0-9]{64}',value['archive_sha256']): return False
    if type(value['tracks']) is not list or not 0<len(value['tracks'])<=21: return False
    seen=set()
    for row in value['tracks']:
        if type(row) is not dict or set(row)!={'id','path','sha256','bytes'}: return False
        if not isinstance(row['id'],str) or not re.fullmatch(r'[a-z0-9_]+',row['id']) or row['id'] in seen: return False
        if row['path']!='assets/audio/music/'+row['id']+'.ogg': return False
        if type(row['bytes']) is not int or row['bytes']<=0 or not isinstance(row['sha256'],str) or not re.fullmatch(r'[a-f0-9]{64}',row['sha256']): return False
        seen.add(row['id'])
    return True

def load(path=CONFIG):
    value=json.loads(Path(path).read_text(encoding='utf8'))
    if not valid(value): raise ValueError('Invalid Web audio manifest')
    return value

def check_selection(root,config):
    catalog=json.loads((Path(root)/'data/audio.json').read_text(encoding='utf8'))
    expected={slot['track_id'] for slot in catalog['slots'].values()}
    if expected!={row['id'] for row in config['tracks']}: raise ValueError('Web bundle must match current selected slots')

def selected_paths(root=ROOT,config=None):
    config=load() if config is None else config
    if not valid(config): raise ValueError('Invalid Web audio manifest')
    check_selection(root,config)
    paths=set()
    for row in config['tracks']:
        path=Path(root)/row['path']
        if not path.is_file() or path.stat().st_size!=row['bytes'] or digest(path.read_bytes())!=row['sha256']: raise ValueError('Missing or changed selected Web music: '+row['id'])
        paths.add(row['path'])
    return paths

def proof(config=None):
    config=load() if config is None else config
    if not valid(config): raise ValueError('Invalid Web audio manifest')
    return {'archive_sha256':config['archive_sha256'],'track_ids':sorted(row['id'] for row in config['tracks'])}

def proof_valid(value,config=None):
    return type(value) is dict and value==proof(config)

def install(archive,root=ROOT,config=None):
    config=load() if config is None else config
    if not valid(config): raise ValueError('Invalid Web audio manifest')
    check_selection(root,config)
    archive=Path(archive)
    if archive.stat().st_size>sum(row['bytes'] for row in config['tracks'])+1048576: raise ValueError('Oversized Web music archive')
    if digest(archive.read_bytes())!=config['archive_sha256']: raise ValueError('Web music archive SHA mismatch')
    rows={row['id']+'.ogg':row for row in config['tracks']}
    verified={}
    with zipfile.ZipFile(archive) as bundle:
        entries=bundle.infolist()
        if len(entries)!=len(rows) or {item.filename for item in entries}!=set(rows): raise ValueError('Unexpected or duplicate audio archive entries')
        for item in entries:
            row=rows[item.filename]
            if item.file_size!=row['bytes'] or item.is_dir() or (item.external_attr>>16)&0o170000==0o120000: raise ValueError('Invalid audio archive entry')
            data=bundle.read(item)
            if digest(data)!=row['sha256'] or not data.startswith(b'OggS'): raise ValueError('Invalid audio payload: '+row['id'])
            target=Path(root)/row['path']
            if target.exists() and digest(target.read_bytes())!=row['sha256']: raise ValueError('Refusing to replace unknown local music: '+row['id'])
            verified[target]=data
    for target,data in verified.items():
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists(): target.write_bytes(data)
    selected_paths(root,config)
    return proof(config)

def decrypt(root=ROOT,config=None,key=None):
    from cryptography.fernet import Fernet,InvalidToken
    config=load() if config is None else config
    if not valid(config): raise ValueError('Invalid Web audio manifest')
    key=os.environ.get('WEB_AUDIO_KEY','') if key is None else key
    if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}=',key): raise ValueError('Missing or invalid WEB_AUDIO_KEY')
    source=Path(root)/config['encrypted_path']
    limit=2*(sum(row['bytes'] for row in config['tracks'])+1048576)
    if source.stat().st_size>limit or digest(source.read_bytes())!=config['encrypted_sha256']: raise ValueError('Encrypted Web music SHA or size mismatch')
    try: archive=Fernet(key.encode('ascii')).decrypt(source.read_bytes())
    except (ValueError,InvalidToken): raise ValueError('Web music decryption failed') from None
    area=Path(root)/'.tools/private-web-audio'; area.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=area) as folder:
        path=Path(folder)/'music.zip'; path.write_bytes(archive)
        return install(path,root,config)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--install',type=Path);mode.add_argument('--decrypt',action='store_true')
    args=parser.parse_args();print(json.dumps(decrypt() if args.decrypt else install(args.install)))
