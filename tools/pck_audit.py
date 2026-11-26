"""Bounded Godot 4.6.3 standalone V3 directory reader and public-package audit."""
import json,re,struct
from pathlib import Path

def directory(path):
    path=Path(path); size=path.stat().st_size
    with path.open('rb') as stream:
        def read(count):
            data=stream.read(count)
            if len(data)!=count: raise ValueError('Truncated PCK directory')
            return data
        magic,version,major,minor,patch,flags,base,offset=struct.unpack('<6IQQ',read(40))
        if (magic,version,major,minor,patch,flags)!=(0x43504447,3,4,6,3,2) or read(64)!=bytes(64) or not 104<=base<=offset<=size-4: raise ValueError('Unsupported PCK format')
        stream.seek(offset); count=struct.unpack('<I',read(4))[0]
        if not 0<count<=50000: raise ValueError('Invalid entry count')
        rows=[]
        for index in range(count):
            length=struct.unpack('<I',read(4))[0]
            if not 0<length<=16384 or length%4: raise ValueError('Invalid path length')
            name=read(length).rstrip(b'\0').decode('utf8')
            name=name[6:] if name.startswith('res://') else name
            if not name or '\0' in name or '\\' in name or name.startswith('/') or '..' in name.split('/'): raise ValueError('Unsafe path')
            relative,length=struct.unpack('<QQ',read(16)); read(16)
            if struct.unpack('<I',read(4))[0]!=0 or not base<=base+relative<=base+relative+length<=offset: raise ValueError('Invalid payload bounds')
            rows.append({'path':name,'bytes':length,'offset':base+relative})
        if stream.tell()>size or len({r['path'] for r in rows})!=count: raise ValueError('Invalid directory bounds')
        owners={}
        for row in rows:
            if not row['path'].endswith('.import'): continue
            if row['bytes']>65536: raise ValueError('Oversized import metadata')
            stream.seek(row['offset']); text=read(row['bytes']).decode('utf8')
            for target in re.findall(r'res://([^"\s]+)',text):
                if target.startswith('.godot/imported/'): owners[target]=row['path'][:-7]
        for row in rows: row['source']=owners.get(row['path'],row['path'])
    return {'file_bytes':size,'file_count':count,'payload_bytes':sum(r['bytes'] for r in rows),'files':rows}

def audit_public(path,allow_music=False,music_sources=None):
    report=directory(path)
    banned=[]
    music_seen=set()
    for row in report['files']:
        source=row['source']
        if source.startswith(('tests/','docs/','.tools/','tools/','server/','Cozy Tunes/')) or source.endswith(('.env','.key','.pem')): banned.append(source)
        if source.startswith('data/build/') or source=='data/web_audio_build.json': banned.append(source)
        if source.startswith('assets/audio/music/'):
            original=source[:-7] if source.endswith('.import') else source
            music_seen.add(original)
            if not allow_music or (music_sources is not None and original not in music_sources): banned.append(source)
    if banned: raise ValueError('Non-public package entries: '+','.join(banned))
    if music_sources is not None and music_seen!=set(music_sources): raise ValueError('Selected Web music missing from package')
    report['forbidden_entries']=[]
    report['music_resources']=sorted(music_seen)
    return report
if __name__=='__main__':
    import sys
    result=audit_public(sys.argv[1]); print(json.dumps({k:v for k,v in result.items() if k!='files'}))
