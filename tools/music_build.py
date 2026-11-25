# -*- coding: utf-8 -*-
"""Explicit local music builder and isolated pre-export project staging.

Default is dry-run. Real runs require an exact executable SHA and validate all
selected sources before commands, then complete Ogg structure and PCM decode.
Injected runners are synthetic and never count as actual q6/decode evidence.
"""
from copy import deepcopy
from hashlib import sha256
import argparse
import math
import struct
import shutil
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4

sys.dont_write_bytecode=True
SLOTS=("opening","day","night","deduction","ending")


class ContractError(ValueError):
    pass


def need(ok,label):
    if not ok: raise ContractError(label)


def keys(value,fields):
    return type(value) is dict and set(value)==set(fields)


def integer(value,minimum,maximum):
    return type(value) in (int,float) and math.isfinite(value) and value==math.floor(value) and minimum<=value<=maximum


def positive(value):
    return type(value) in (int,float) and math.isfinite(value) and value>0


def text(value): return type(value) is str and bool(value.strip())


def sha(value): return type(value) is str and re.fullmatch(r"[0-9a-f]{64}",value) is not None


def identifier(value,maximum):
    return type(value) is str and len(value)<=maximum and re.fullmatch(r"[a-z][a-z0-9_]*",value) is not None


def filename(value,maximum):
    return (text(value) and value==value.strip() and len(value)<=maximum and value.endswith('.ogg')
            and len(value)>len('.ogg') and '..' not in value
            and not any(ord(char)<32 or char in '/\\:<>"|?*' for char in value))


def chinese_label(value):
    return text(value) and any(0x3400<=ord(char)<=0x9fff for char in value) and all(ord(char)>=128 or char==' ' for char in value)


def unique_strings(values):
    return type(values) is list and bool(values) and all(text(value) for value in values) and len(set(values))==len(values)


def validate_catalog(config):
    need(keys(config,['version','enabled','inventory_count','crossfade_seconds','clock','encoding','validation','routing','runtime_missing_behavior','slots','tracks','source','copy']),'catalog fields')
    need(type(config['version']) is not bool and config['version']==1 and type(config['enabled']) is bool,'version/switch')
    need(integer(config['inventory_count'],1,2147483647) and positive(config['crossfade_seconds']),'inventory count/fade')
    limits=config['validation']; need(keys(limits,['id_max_length','filename_max_length','quality_min','quality_max']),'validation fields')
    need(integer(limits['id_max_length'],1,2147483647) and integer(limits['filename_max_length'],1,2147483647),'text bounds')
    need(integer(limits['quality_min'],-2147483647,2147483647) and integer(limits['quality_max'],limits['quality_min'],2147483647),'quality bounds')
    encoding=config['encoding']; need(keys(encoding,['container','codec','vorbis_quality','policy']),'encoding fields')
    need(encoding['container']=='ogg' and encoding['codec']=='libvorbis' and integer(encoding['vorbis_quality'],limits['quality_min'],limits['quality_max']) and encoding['policy']=='local_outputs_untracked','requested encoding contract')
    need(config['runtime_missing_behavior']=='silence' and keys(config['slots'],SLOTS),'five slots and missing-file policy')
    need(type(config['tracks']) is list and len(config['tracks'])==config['inventory_count'],'track count matches cached inventory count')
    tracks={}; names=set()
    for entry in config['tracks']:
        need(keys(entry,['id','source_filename','duration_seconds','source_sha256','runtime_path']),'track fields')
        need(identifier(entry['id'],limits['id_max_length']) and entry['id'] not in tracks,'unique safe track ID')
        need(filename(entry['source_filename'],limits['filename_max_length']) and entry['source_filename'].casefold() not in names,'unique safe source basename')
        need(positive(entry['duration_seconds']) and sha(entry['source_sha256']),'duration/source hash')
        need(entry['runtime_path']=='res://assets/audio/music/'+entry['id']+'.ogg','canonical relative runtime resource path')
        tracks[entry['id']]=entry; names.add(entry['source_filename'].casefold())
    for key in SLOTS:
        slot=config['slots'][key]; need(keys(slot,['label','track_id','candidates']),'slot fields')
        need(chinese_label(slot['label']) and type(slot['track_id']) is str and slot['track_id'] in tracks,'Chinese slot label and selected reference')
        need(unique_strings(slot['candidates']) and all(key in tracks for key in slot['candidates']),'unique candidate references')
    clock=config['clock']; need(keys(clock,['day_minute','night_minute','minutes_per_day','day_slot','night_slot']),'clock fields')
    need(integer(clock['minutes_per_day'],1,2147483647) and integer(clock['day_minute'],0,clock['minutes_per_day']-1) and integer(clock['night_minute'],clock['day_minute']+1,clock['minutes_per_day']-1),'clock bounds')
    need(clock['day_slot']=='day' and clock['night_slot']=='night','clock slots')
    routing=config['routing']; need(keys(routing,['page_slots','case_pages','case_slot','ending_slot']),'routing fields')
    need(routing['page_slots']=={'title':'opening','ending':'ending'} and routing['case_slot']=='deduction' and routing['ending_slot']=='ending' and unique_strings(routing['case_pages']),'routing values')
    source=config['source']; need(keys(source,['author','url','license','metadata_inventory_sha256','selection_basis','listening_review']),'source fields')
    need(text(source['author']) and type(source['url']) is str and source['url'].startswith('https://') and sha(source['metadata_inventory_sha256']) and source['selection_basis']=='filename_only' and source['listening_review'] in ['not_performed','human_reviewed'],'source provenance')
    license=source['license']; need(keys(license,['type','document_date','official_upload_id','document_sha256','historical_local_pack_license_proven']),'license fields')
    need(license['type']=='custom license' and type(license['document_date']) is str and re.fullmatch(r'.{4}-.{2}-.{2}',license['document_date']) is not None and text(license['official_upload_id']) and sha(license['document_sha256']) and type(license['historical_local_pack_license_proven']) is bool,'current custom license metadata')
    need(keys(config['copy'],['catalog_title','missing_runtime','selection_note','metadata_note','license_note']) and all(text(value) for value in config['copy'].values()),'Chinese copy')
    return deepcopy(config)


OWNERSHIP_FORMAT='music_builder_ownership_v1'


class BuildError(ValueError):
    pass


def need(ok,message):
    if not ok: raise BuildError(message)


def sha_file(path):
    digest=sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(65536),b''): digest.update(block)
    return digest.hexdigest()


def valid_sha(value):
    return type(value) is str and re.fullmatch(r'[0-9a-f]{64}',value) is not None


def safe_child(root,name):
    root=Path(root).resolve(); lexical=root/name
    need(type(name) is str and name not in ('','.', '..') and '/' not in name and '\\' not in name and ':' not in name,'unsafe basename')
    need(not is_reparse(lexical),'reparse/symlink file is not an owned build target')
    target=lexical.resolve()
    need(target.parent==root,'path escaped explicit root')
    return target


def disjoint(*roots):
    for root in roots:
        lexical=Path(root).absolute()
        need(not any(is_reparse(part) for part in (lexical, *lexical.parents)), 'root crosses a reparse/symlink')
    resolved=[Path(root).resolve() for root in roots]
    for index,a in enumerate(resolved):
        for b in resolved[index+1:]:
            need(a!=b and a not in b.parents and b not in a.parents,'source/runtime/work roots must be disjoint')
    return resolved


def atomic_json(path,value):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.'+uuid4().hex+'.tmp')
    try:
        temp.write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
        os.replace(str(temp),str(path))
    finally:
        if temp.exists(): temp.unlink()


def real_runner(argv):
    result=subprocess.run(argv,shell=False,stdin=subprocess.DEVNULL,capture_output=True,text=True,encoding='utf-8',errors='replace',check=False)
    return {'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr}


def real_publish(source,target):
    os.replace(str(source),str(target))


def command(argv,runner,report):
    if report.get('encoder'):
        need(sha_file(Path(argv[0]))==report['encoder']['expected_sha256'],'encoder changed before invocation')
    record={'argv':[str(item) for item in argv],'exit_code':None,'stdout':'','stderr':''}
    report['commands'].append(record)
    try:
        result=runner(record['argv'])
        need(type(result) is dict and type(result.get('exit_code')) is int and type(result.get('stdout')) is str and type(result.get('stderr')) is str,'runner must return text logs and integer exit code')
        record.update(result)
    except Exception as error:
        record['runner_error']=str(error)
        raise BuildError('command runner failed: '+str(error)) from error
    return record


def validate_entry(track_id,entry):
    fields={'filename','source_sha256','encoder_sha256','output_sha256','codec','container','quality','last_run_id'}
    need(type(entry) is dict and set(entry)==fields and entry['filename']==track_id+'.ogg','invalid owned output record')
    need(all(valid_sha(entry[key]) for key in ['source_sha256','encoder_sha256','output_sha256']),'invalid owned output hashes')
    need(entry['codec']=='libvorbis' and entry['container']=='ogg' and type(entry['quality']) is int and type(entry['last_run_id']) is str,'invalid owned encoding record')


def load_ownership(path,runtime_root):
    if not path.exists(): return {'format':OWNERSHIP_FORMAT,'runtime_root':str(runtime_root),'outputs':{},'pending':{}}
    need(not path.is_symlink(),'ownership receipt cannot be a symlink')
    value=json.loads(path.read_text(encoding='utf-8'))
    need(type(value) is dict and set(value)=={'format','runtime_root','outputs','pending'} and value['format']==OWNERSHIP_FORMAT and value['runtime_root']==str(runtime_root),'ownership receipt belongs to another root/format')
    need(type(value['outputs']) is dict and type(value['pending']) is dict,'invalid ownership maps')
    for key,entry in value['outputs'].items():
        need(re.fullmatch(r'[a-z][a-z0-9_]*',key) is not None,'unsafe ownership ID')
        validate_entry(key,entry)
    for key,pending in value['pending'].items():
        need(type(pending) is dict and set(pending)=={'previous','next'},'invalid publication journal')
        validate_entry(key,pending['next'])
        if pending['previous'] is not None: validate_entry(key,pending['previous'])
    return value


def reconcile(ownership,runtime_root):
    """Recover a journaled per-file rename; never silently accept an unknown hash."""
    changed=False
    for key,pending in list(ownership['pending'].items()):
        target=safe_child(runtime_root,key+'.ogg')
        actual=sha_file(target) if target.is_file() else None
        previous=pending['previous']
        if actual==pending['next']['output_sha256']:
            ownership['outputs'][key]=pending['next']
        elif actual==(previous['output_sha256'] if previous else None):
            if previous is None: ownership['outputs'].pop(key,None)
            else: ownership['outputs'][key]=previous
        else:
            raise BuildError('publication journal target has an unknown hash: '+key)
        ownership['pending'].pop(key); changed=True
    return changed


def selected_tracks(catalog):
    validate_catalog(catalog)
    by_id={entry['id']:entry for entry in catalog['tracks']}
    seen=set(); rows=[]
    for slot in SLOTS:
        key=catalog['slots'][slot]['track_id']
        if key not in seen: rows.append(deepcopy(by_id[key])); seen.add(key)
    return rows


def build_music(catalog,source_root,runtime_root,work_root,*,encoder=None,encoder_sha256='',apply=False,with_music=False,runner=None,publisher=None,metadata_writer=None):
    runner=real_runner if runner is None else runner
    publisher=real_publish if publisher is None else publisher
    metadata_writer=atomic_json if metadata_writer is None else metadata_writer
    report={'format':'music_build_run_v1','run_id':uuid4().hex,'status':'preflight','phase':'preflight','apply':bool(apply),'with_music':bool(with_music),'requires_public_export_exclusion':not with_music,'selected_ids':[],'missing_sources':[],'source_checks':[],'commands':[],'outputs':[],'encoded_count':0,'published_count':0,'skipped_count':0,'runner_mode':'subprocess' if runner is real_runner else 'injected','checks':{'source_hashes':False,'encoder_hash':False,'version_declared':False,'libvorbis_help_declared':False,'all_staged_nonempty':False,'ogg_structure':False,'channels_rate_duration_eos':False,'decode_integrity':False,'actual_q6_quality':False},'all_files_atomic':False}
    run_dir=None
    try:
        need(type(apply) is bool and type(with_music) is bool,'apply/with_music must be explicit booleans')
        source_root,runtime_root,work_root=disjoint(source_root,runtime_root,work_root)
        rows=selected_tracks(catalog); report['selected_ids']=[entry['id'] for entry in rows]
        report['requested_encoding']=deepcopy(catalog['encoding'])
        sources={}
        for row in rows:
            source=safe_child(source_root,row['source_filename']); target=safe_child(runtime_root,row['id']+'.ogg')
            need(row['runtime_path']=='res://assets/audio/music/'+target.name,'runtime path contract')
            if not source.is_file(): report['missing_sources'].append(row['id'])
            sources[row['id']]=source
        if report['missing_sources']:
            need(not with_music,'with-music requires every selected source')
            report.update(status='silent',phase='complete',reason='selected local sources absent; zero new outputs; existing runtime resources are untouched')
            return report
        # Check ALL selected inputs before probing or encoding any one track.
        for row in rows:
            actual=sha_file(sources[row['id']])
            report['source_checks'].append({'track_id':row['id'],'source_filename':row['source_filename'],'expected_sha256':row['source_sha256'],'actual_sha256':actual})
            need(actual==row['source_sha256'],'source SHA mismatch: '+row['id'])
        report['checks']['source_hashes']=True
        source_metadata={}
        for row in rows:
            meta=inspect_vorbis(sources[row['id']])
            need(abs(meta['duration_seconds']-row['duration_seconds'])<=1/meta['sample_rate']+1e-6,'source duration differs from catalog: '+row['id'])
            source_metadata[row['id']]=meta
        report['source_metadata']=source_metadata
        ownership_path=safe_child(work_root,'ownership_receipt.json')
        ownership=load_ownership(ownership_path,runtime_root)
        repaired=reconcile(ownership,runtime_root)
        snapshots={}
        for row in rows:
            key=row['id']; target=safe_child(runtime_root,key+'.ogg')
            owned=ownership['outputs'].get(key)
            if target.exists():
                need(target.is_file() and owned is not None,'refusing unowned existing runtime output: '+key)
                need(sha_file(target)==owned['output_sha256'],'owned output changed outside this helper: '+key)
            snapshots[key]=deepcopy(owned) if target.is_file() else None
        if not apply:
            report.update(status='dry_run',phase='complete',ownership_journal_recovery_needed=repaired)
            report['planned_tracks']=[{'track_id':row['id'],'source_filename':row['source_filename'],'runtime_path':row['runtime_path']} for row in rows]
            return report

        run_dir=safe_child(work_root,report['run_id'])
        run_dir.mkdir(parents=True,exist_ok=False)
        report['phase']='probe'
        need(encoder is not None and valid_sha(encoder_sha256),'apply requires an encoder and its explicit SHA256')
        encoder=Path(encoder).resolve()
        need(encoder.is_file() and encoder.suffix.lower()=='.exe','encoder must be an explicit existing executable')
        actual_encoder_sha=sha_file(encoder)
        report['encoder']={'path':str(encoder),'expected_sha256':encoder_sha256,'actual_sha256':actual_encoder_sha}
        need(actual_encoder_sha==encoder_sha256,'encoder SHA mismatch')
        report['checks']['encoder_hash']=True
        version=command([str(encoder),'-version'],runner,report)
        need(version['exit_code']==0 and re.search(r'(?m)^ffmpeg version\s+\S+',version['stdout']+'\n'+version['stderr']),'encoder version probe did not declare ffmpeg')
        report['checks']['version_declared']=True
        help_result=command([str(encoder),'-hide_banner','-h','encoder=libvorbis'],runner,report)
        need(help_result['exit_code']==0 and re.search(r'(?m)^Encoder libvorbis(?:\s|\[|:)',help_result['stdout']+'\n'+help_result['stderr']),'encoder help did not declare Encoder libvorbis')
        report['checks']['libvorbis_help_declared']=True
        stage_dir=run_dir/'stage'; stage_dir.mkdir(parents=True,exist_ok=False)
        decoded_dir=run_dir/'decoded'; decoded_dir.mkdir(exist_ok=False)
        if repaired: metadata_writer(ownership_path,ownership)
        report['phase']='encode'; staged={}
        encoding=catalog['encoding']; quality=int(encoding['vorbis_quality'])
        for row in rows:
            key=row['id']; old=snapshots[key]
            same=(old is not None and old['source_sha256']==row['source_sha256'] and old['encoder_sha256']==actual_encoder_sha and old['quality']==quality and old['codec']==encoding['codec'] and old['container']==encoding['container'])
            if same:
                verified=verify_audio(safe_child(runtime_root,key+'.ogg'),source_metadata[key],encoder,runner,report,safe_child(decoded_dir,key+'.pcm'))
                report.setdefault('audio_verification',{})[key]=verified
                report['skipped_count']+=1
                report['outputs'].append({'track_id':key,'status':'skipped_verified_owned','output_sha256':old['output_sha256'],'runtime_path':row['runtime_path']})
                continue
            need(sha_file(sources[key])==row['source_sha256'],'source changed before encoding: '+key)
            output=safe_child(stage_dir,key+'.ogg')
            argv=[str(encoder),'-nostdin','-n','-i',str(sources[key]),'-map','0:a:0','-vn','-c:a',encoding['codec'],'-q:a',str(quality),'-map_metadata','-1','-f',encoding['container'],str(output)]
            result=command(argv,runner,report)
            need(result['exit_code']==0,'encoder command failed: '+key)
            need(output.is_file() and not output.is_symlink() and output.stat().st_size>0,'encoder produced no nonempty staged file: '+key)
            verified=verify_audio(output,source_metadata[key],encoder,runner,report,safe_child(decoded_dir,key+'.pcm'))
            report.setdefault('audio_verification',{})[key]=verified
            new={'filename':key+'.ogg','source_sha256':row['source_sha256'],'encoder_sha256':actual_encoder_sha,'output_sha256':sha_file(output),'codec':encoding['codec'],'container':encoding['container'],'quality':quality,'last_run_id':report['run_id']}
            staged[key]=(output,new)
            report['encoded_count']+=1
            report['outputs'].append({'track_id':key,'status':'staged_verified','source_sha256':row['source_sha256'],'output_sha256':new['output_sha256'],'runtime_path':row['runtime_path']})
        report['checks']['all_staged_nonempty']=True
        for row in rows:
            need(sha_file(sources[row['id']])==row['source_sha256'],'source changed after encoding: '+row['id'])
        actual=runner is real_runner
        report['checks'].update(ogg_structure=actual,channels_rate_duration_eos=actual,decode_integrity=actual,actual_q6_quality=actual and quality==6)
        report['source_hashes_after']=True
        report['human_listening_reviewed']=False
        report['phase']='publish'; runtime_root.mkdir(parents=True,exist_ok=True)
        for key,(stage,new) in staged.items():
            target=safe_child(runtime_root,key+'.ogg'); previous=snapshots[key]
            actual=sha_file(target) if target.is_file() else None
            need(actual==(previous['output_sha256'] if previous else None),'runtime changed during encoding: '+key)
            # Journal before a per-file rename so metadata I/O failure is recoverable.
            ownership['pending'][key]={'previous':previous,'next':new}
            metadata_writer(ownership_path,ownership)
            publisher(stage,target)
            need(target.is_file() and sha_file(target)==new['output_sha256'],'published output does not match staged SHA: '+key)
            ownership['outputs'][key]=new; ownership['pending'].pop(key)
            metadata_writer(ownership_path,ownership)
            report['published_count']+=1
            next(item for item in report['outputs'] if item['track_id']==key)['status']='published'
        report.update(status='complete',phase='complete')
    except Exception as error:
        report['status']='failed'; report['error']=str(error)
        # Actual targets are recorded even if a rename succeeded before an I/O error.
        try:
            report['runtime_observation']=[{'track_id':key,'exists':safe_child(runtime_root,key+'.ogg').is_file(),'actual_sha256':sha_file(safe_child(runtime_root,key+'.ogg')) if safe_child(runtime_root,key+'.ogg').is_file() else None} for key in report['selected_ids']]
        except Exception as observe_error:
            report['runtime_observation_error']=str(observe_error)
    finally:
        if run_dir is not None:
            receipt_path=run_dir/'receipt.json'
            try:
                report['receipt_path']=str(receipt_path); atomic_json(receipt_path,report)
            except Exception as error:
                report['receipt_write_error']=str(error)
    return report



def is_reparse(path):
    try:
        info=Path(path).lstat()
        return Path(path).is_symlink() or bool(getattr(info,'st_file_attributes',0) & 0x400)
    except FileNotFoundError:
        return False


def ogg_crc(raw):
    value=0
    for byte in raw:
        value=((value<<8)&0xffffffff)^_CRC_TABLE[((value>>24)^byte)&255]
    return value


def _crc_table():
    table=[]
    for byte in range(256):
        value=byte<<24
        for _ in range(8):value=((value<<1)^(0x04c11db7 if value&0x80000000 else 0))&0xffffffff
        table.append(value)
    return tuple(table)


_CRC_TABLE=_crc_table()


def inspect_vorbis(path):
    """Read every physical page; do not infer decoding or q6 from Ogg headers."""
    raw=Path(path).read_bytes(); offset=0; serial=None; pages=[]; packets=[]; partial=bytearray(); last=0
    while offset<len(raw):
        need(len(raw)-offset>=27 and raw[offset:offset+4]==b'OggS' and raw[offset+4]==0,'truncated/invalid Ogg page')
        count=raw[offset+26]; lacing=raw[offset+27:offset+27+count]
        need(count>0 and len(lacing)==count,'truncated/empty Ogg segment table')
        end=offset+27+count+sum(lacing);need(end<=len(raw),'truncated Ogg payload')
        page=bytearray(raw[offset:end]); checksum=struct.unpack_from('<I',page,22)[0];page[22:26]=bytes(4)
        need(ogg_crc(page)==checksum,'Ogg page CRC mismatch')
        flags=raw[offset+5]; page_serial,sequence=struct.unpack_from('<II',raw,offset+14)
        serial=page_serial if serial is None else serial
        need(page_serial==serial and sequence==len(pages),'chained/missing/reordered Ogg page')
        need(not flags&~7 and bool(flags&1)==bool(partial),'Ogg continuation/flags mismatch')
        granule=struct.unpack_from('<Q',raw,offset+6)[0]
        if granule != 0xffffffffffffffff:
            need(granule>=last,'Ogg granule moved backwards');last=granule
        position=offset+27+count
        for length in lacing:
            partial.extend(raw[position:position+length]);position+=length
            if length<255:packets.append(bytes(partial));partial.clear()
        pages.append((flags,granule));offset=end
    need(offset==len(raw) and not partial and len(pages)>=3 and len(packets)>3,'incomplete Ogg packets/pages')
    need(pages[0][0]&2 and not any(flags&2 for flags,_ in pages[1:]) and pages[-1][0]&4 and not any(flags&4 for flags,_ in pages[:-1]),'missing/duplicate BOS/EOS')
    ident=packets[0];need(len(ident)==30 and ident[:7]==b'\x01vorbis','invalid Vorbis identification')
    version,channels,rate=struct.unpack_from('<IBI',ident,7);block=ident[28]
    need(version==0 and 1<=channels<=255 and rate>0 and ident[29]==1 and 6<=(block&15)<=(block>>4)<=13,'invalid Vorbis format/block/framing')
    comment=packets[1];need(comment[:7]==b'\x03vorbis' and len(comment)>=16,'invalid Vorbis comment header')
    vendor=struct.unpack_from('<I',comment,7)[0];position=11+vendor;need(position+4<=len(comment),'truncated Vorbis vendor')
    count=struct.unpack_from('<I',comment,position)[0];position+=4
    need(count<=(len(comment)-position)//4,'invalid Vorbis comment count')
    for _ in range(count):
        need(position+4<=len(comment),'truncated Vorbis comment');length=struct.unpack_from('<I',comment,position)[0];position+=4+length;need(position<=len(comment),'truncated Vorbis comment payload')
    need(comment[position:]==b'\x01' and packets[2][:7]==b'\x05vorbis' and all(packet and not packet[0]&1 for packet in packets[3:]),'Vorbis comment/setup/audio packet framing')
    frames=pages[-1][1];need(0<frames<0xffffffffffffffff,'invalid EOS granule')
    return {'container':'ogg','codec':'vorbis','vorbis_version':version,'channels':channels,'sample_rate':rate,'pages':len(pages),'packets':len(packets),'all_page_crc_valid':True,'packet_and_sequence_continuity':True,'bos_eos_valid':True,'eos_granule':frames,'duration_seconds':frames/rate}


def verify_audio(path,expected,encoder,runner,report,pcm):
    metadata=inspect_vorbis(path)
    need(all(metadata[key]==expected[key] for key in ('channels','sample_rate','eos_granule')),'output channels/rate/duration differ from source')
    result=command([str(encoder),'-nostdin','-n','-hide_banner','-v','error','-xerror','-err_detect','explode','-i',str(path),'-map','0:a:0','-vn','-c:a','pcm_s16le','-f','s16le',str(pcm)],runner,report)
    need(result['exit_code']==0,'complete ffmpeg decode failed')
    need(pcm.is_file() and pcm.stat().st_size==metadata['eos_granule']*metadata['channels']*2,'full decoded PCM frame count differs from EOS granule')
    return {'ogg':metadata,'decoded_pcm_bytes':pcm.stat().st_size,'decoded_pcm_sha256':sha_file(pcm),'decoded_frames':metadata['eos_granule'],'actual_decoder':runner is real_runner,'human_listening_reviewed':False}


def stage_project(source_root,stage_root,*,with_music=False):
    """Copy to a new isolated project input tree; never touch an existing site.

    Both modes exclude private state, source packs and previous build artifacts.
    Public excludes all music; local keeps only assets/audio/music and sidecars.
    This is pre-export input staging, not an opaque PCK/archive contents audit.
    """
    report={'format':'music_project_stage_v1','status':'preflight','with_music':with_music,'files':[],'excluded':[],'source_unchanged':False,'opaque_archives_audited':False}
    try:
        need(type(with_music) is bool,'with_music must be explicit boolean')
        source_root,stage_root=disjoint(source_root,stage_root)
        need(source_root.is_dir() and not stage_root.exists(),'stage must be a new isolated directory')
        need((source_root/'project.godot').is_file() and not is_reparse(source_root/'project.godot'),'stage source must be an explicit Godot project input root')
        def excluded(path,directory=False):
            name=path.name.casefold()
            parts=tuple(part.casefold() for part in path.relative_to(source_root).parts)
            # Stages contain project inputs, never developer state or prior packs.
            private=(name.startswith('.') and (directory or name!='.gdignore'))
            private=private or name in {'build','builds','dist','out','export','exports','export_credentials.cfg'} or name.startswith('cozy tunes')
            private=private or path.suffix.casefold() in {'.pck','.zip','.7z','.tar','.gz','.exe'}
            wrong_music=name=='music' and (not with_music or parts!=('assets','audio','music'))
            return private or wrong_music
        inputs=[]
        for root,dirs,files in os.walk(source_root,followlinks=False):
            parent=Path(root)
            for name in list(dirs):
                path=parent/name
                if excluded(path,directory=True):
                    report['excluded'].append(path.relative_to(source_root).as_posix());dirs.remove(name);continue
                need(not is_reparse(path),'stage source directory is reparse/symlink')
            for name in files:
                path=parent/name
                if excluded(path):
                    report['excluded'].append(path.relative_to(source_root).as_posix());continue
                need(not is_reparse(path) and path.is_file(),'stage source file is reparse/symlink/nonfile')
                inputs.append((path,path.relative_to(source_root),sha_file(path)))
        stage_root.mkdir(parents=True,exist_ok=False)
        for source,relative,digest in inputs:
            target=stage_root/relative;target.parent.mkdir(parents=True,exist_ok=True)
            need(sha_file(source)==digest,'stage input changed during copy')
            with source.open('rb') as reader,target.open('xb') as writer:shutil.copyfileobj(reader,writer)
            need(sha_file(target)==digest,'stage output differs from source')
            report['files'].append({'path':relative.as_posix(),'sha256':digest,'bytes':target.stat().st_size})
        need(all(sha_file(source)==digest for source,_,digest in inputs),'stage input changed after copy')
        report.update(status='complete',source_unchanged=True,source_root=str(source_root),stage_root=str(stage_root),music_included=with_music)
    except (OSError,ValueError) as error:
        report.update(status='failed',error=str(error))
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage-from',type=Path)
    parser.add_argument('--stage-to',type=Path)
    parser.add_argument('--catalog',type=Path)
    parser.add_argument('--source-root',type=Path)
    parser.add_argument('--runtime-root',type=Path)
    parser.add_argument('--work-root',type=Path)
    parser.add_argument('--encoder',type=Path)
    parser.add_argument('--encoder-sha256',default='')
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--with-music',action='store_true')
    args=parser.parse_args()
    if args.stage_from is not None or args.stage_to is not None:
        parser.error('--stage-from and --stage-to are required together') if args.stage_from is None or args.stage_to is None else None
        result=stage_project(args.stage_from,args.stage_to,with_music=args.with_music)
        print(json.dumps(result,ensure_ascii=False,indent=2));return 0 if result['status']=='complete' else 1
    if any(value is None for value in (args.catalog,args.source_root,args.runtime_root,args.work_root)):
        parser.error('explicit catalog/source-root/runtime-root/work-root required')
    catalog=json.loads(args.catalog.read_text(encoding='utf-8-sig'))
    report=build_music(catalog,args.source_root,args.runtime_root,args.work_root,encoder=args.encoder,encoder_sha256=args.encoder_sha256,apply=args.apply,with_music=args.with_music)
    print(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False))
    return 1 if report['status']=='failed' else 0


if __name__=='__main__':
    raise SystemExit(main())
