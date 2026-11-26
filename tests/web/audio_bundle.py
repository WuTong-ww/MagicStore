import copy,json,sys,tempfile,unittest,warnings,zipfile
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import web_audio,pck_audit
from cryptography.fernet import Fernet
from web_build import excluded

class WebAudioBundle(unittest.TestCase):
    def setUp(self):
        folder=ROOT/'.tools/r3-web/audio-tests'; folder.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=str(folder)); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        (self.root/'data').mkdir()
        (self.root/'data/audio.json').write_text(json.dumps({'slots':{'day':{'track_id':'one'},'deduction':{'track_id':'one'},'night':{'track_id':'two'}}}))
        self.payloads={'one.ogg':b'OggSone','two.ogg':b'OggStwo'}
        self.config={'version':1,'encrypted_path':'build-sources/music/test-music.fernet','encrypted_sha256':'0'*64,'archive_sha256':'0'*64,'tracks':[{'id':name[:-4],'path':'assets/audio/music/'+name,'sha256':web_audio.digest(data),'bytes':len(data)} for name,data in self.payloads.items()]}
        self.archive=self.root/'source.zip'
        self.write_zip(list(self.payloads.items()))
    def write_zip(self,entries):
        with warnings.catch_warnings():
            warnings.simplefilter('ignore',UserWarning)
            with zipfile.ZipFile(self.archive,'w') as bundle:
                for name,data in entries: bundle.writestr(name,data)
        self.config['archive_sha256']=web_audio.digest(self.archive.read_bytes())
    def install(self): return web_audio.install(self.archive,self.root,self.config)
    def test_real_manifest_validates_and_matches_selected_catalog(self):
        config=web_audio.load()
        self.assertTrue(web_audio.valid(config))
        web_audio.check_selection(ROOT,config)
        self.assertTrue(web_audio.proof_valid(web_audio.proof(config),config))
    def test_authenticated_decryption_then_install(self):
        key=Fernet.generate_key()
        source=self.root/self.config['encrypted_path']; source.parent.mkdir(parents=True)
        source.write_bytes(Fernet(key).encrypt(self.archive.read_bytes()))
        self.config['encrypted_sha256']=web_audio.digest(source.read_bytes())
        self.assertEqual(web_audio.decrypt(self.root,self.config,key.decode()),web_audio.proof(self.config))
    def test_wrong_missing_or_changed_key_cannot_deploy(self):
        key=Fernet.generate_key()
        source=self.root/self.config['encrypted_path']; source.parent.mkdir(parents=True)
        source.write_bytes(Fernet(key).encrypt(self.archive.read_bytes()))
        self.config['encrypted_sha256']=web_audio.digest(source.read_bytes())
        for invalid in ['',Fernet.generate_key().decode()]:
            with self.assertRaises(ValueError): web_audio.decrypt(self.root,self.config,invalid)
        self.assertFalse((self.root/'assets').exists())
        source.write_bytes(source.read_bytes()+b'changed')
        with self.assertRaises(ValueError): web_audio.decrypt(self.root,self.config,key.decode())
    def test_valid_install_and_retry_preserve_audio_bytes(self):
        self.assertEqual(self.install(),web_audio.proof(self.config))
        before={path:(self.root/path).stat().st_mtime_ns for path in web_audio.selected_paths(self.root,self.config)}
        self.install()
        self.assertEqual(before,{path:(self.root/path).stat().st_mtime_ns for path in before})
        for name,data in self.payloads.items(): self.assertEqual((self.root/'assets/audio/music'/name).read_bytes(),data)
    def test_missing_and_modified_music_detected(self):
        with self.assertRaises(ValueError): web_audio.selected_paths(self.root,self.config)
        self.install()
        (self.root/'assets/audio/music/one.ogg').write_bytes(b'changed')
        with self.assertRaises(ValueError): web_audio.selected_paths(self.root,self.config)
    def test_archive_hash_mismatch_writes_nothing(self):
        self.archive.write_bytes(self.archive.read_bytes()+b'corrupt')
        with self.assertRaises(ValueError): self.install()
        self.assertFalse((self.root/'assets').exists())
    def test_payload_hash_mismatch_writes_nothing(self):
        self.write_zip([('one.ogg',b'OggSbad'),('two.ogg',self.payloads['two.ogg'])])
        with self.assertRaises(ValueError): self.install()
        self.assertFalse((self.root/'assets').exists())
    def test_duplicate_traversal_extra_and_directory_entries_rejected(self):
        for entries in [[('one.ogg',b'OggSone'),('one.ogg',b'OggSone')],list(self.payloads.items())+[('../secret',b'bad')],[('one.ogg/',b''),('two.ogg',b'OggStwo')]]:
            with self.subTest(entries=[str(row[0]) for row in entries]):
                self.write_zip(entries)
                with self.assertRaises(ValueError): self.install()
                self.assertFalse((self.root/'assets').exists())
    def test_symlink_archive_entry_rejected(self):
        link=zipfile.ZipInfo('one.ogg'); link.create_system=3; link.external_attr=0o120777<<16
        self.write_zip([(link,b'OggSone'),('two.ogg',b'OggStwo')])
        with self.assertRaises(ValueError): self.install()
    def test_wrong_selection_rejected_before_install(self):
        (self.root/'data/audio.json').write_text(json.dumps({'slots':{'day':{'track_id':'unknown'}}}))
        with self.assertRaises(ValueError): self.install()
        self.assertFalse((self.root/'assets').exists())
    def test_unknown_local_music_not_overwritten(self):
        target=self.root/'assets/audio/music/two.ogg'; target.parent.mkdir(parents=True); target.write_bytes(b'my local track')
        with self.assertRaises(ValueError): self.install()
        self.assertEqual(target.read_bytes(),b'my local track')
        self.assertFalse((target.parent/'one.ogg').exists())
    def test_oversized_archive_rejected(self):
        self.archive.write_bytes(b'x'*(1048576+sum(r['bytes'] for r in self.config['tracks'])+1))
        self.config['archive_sha256']=web_audio.digest(self.archive.read_bytes())
        with self.assertRaisesRegex(ValueError,'Oversized'): self.install()
    def test_manifest_rejects_invalid_path_duplicate_and_types(self):
        for mutate in [lambda c:c.update(version=True),lambda c:c['tracks'].append(c['tracks'][0]),lambda c:c['tracks'][0].update(path='../one.ogg'),lambda c:c['tracks'][0].update(bytes=True)]:
            config=copy.deepcopy(self.config); mutate(config)
            self.assertFalse(web_audio.valid(config))
    def test_export_whitelists_only_selected_tracks(self):
        selected={'assets/audio/music/one.ogg'}
        for path in ['assets/audio/music/two.ogg','assets/audio/music/two.ogg.import','data/web_audio_build.json']:
            self.assertTrue(excluded(Path(path),True,set(),selected))
        self.assertFalse(excluded(Path('assets/audio/music/one.ogg'),True,set(),selected))
        self.assertFalse(excluded(Path('assets/audio/music/one.ogg.import'),True,set(),selected))
        self.assertTrue(excluded(Path('assets/audio/music/one.ogg'),True,set(),False))
    def test_pack_rejects_extra_music_and_private_build_manifest(self):
        selected={'assets/audio/music/one.ogg'}
        for paths in [list(selected)+['assets/audio/music/two.ogg'],list(selected)+['data/web_audio_build.json'],[]]:
            with patch.object(pck_audit,'directory',return_value={'files':[{'source':p} for p in paths]}):
                with self.assertRaises(ValueError): pck_audit.audit_public('unused.pck',True,selected)
        with patch.object(pck_audit,'directory',return_value={'files':[{'source':p} for p in list(selected)+['assets/audio/music/one.ogg.import']]}):
            self.assertEqual(pck_audit.audit_public('unused.pck',True,selected)['music_resources'],sorted(selected))

if __name__=='__main__': unittest.main()
