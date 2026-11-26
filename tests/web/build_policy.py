import importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch,MagicMock

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('merge_pages',ROOT/'tools/merge_pages.py'); pages=importlib.util.module_from_spec(spec); spec.loader.exec_module(pages)

class PagesPreservation(unittest.TestCase):
    def setUp(self):
        folder=ROOT/'.tools/r3-web/policy-tests'; folder.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=str(folder)); self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)
        self.live={'index.html':b'current root','index.pck':b'current pack','build-info.json':b'current metadata','extra.txt':b'keep unknown files','preview/index.html':b'old preview','preview/index.pck':b'old preview pack'}
        self.manifest={'version':1,'root_commit':'a'*40,'preview_commit':'b'*40,'files':[{'path':name,'bytes':len(data),'sha256':pages.digest(data)} for name,data in self.live.items()]}
        self.build=self.base/'build'; self.build.mkdir()
        (self.build/'index.html').write_bytes(b'new html'); (self.build/'index.pck').write_bytes(b'new pck')
    def fetch(self,name,optional=False):
        if name=='site-manifest.json': return json.dumps(self.manifest).encode()
        return self.live[name]
    def run_merge(self,variant):
        (self.build/'build-info.json').write_text(json.dumps({'commit':'c'*40,'variant':variant,'music_included':False,'source_dirty':False}))
        return pages.merge(self.build,self.base/'site',variant,fetch=self.fetch)
    def test_preview_preserves_every_root_byte(self):
        result=self.run_merge('preview')
        self.assertEqual(result['root_commit'],'a'*40)
        for name,data in self.live.items():
            if not name.startswith('preview/'): self.assertEqual((self.base/'site'/name).read_bytes(),data)
        self.assertEqual((self.base/'site/preview/index.pck').read_bytes(),b'new pck')
    def test_main_preserves_preview(self):
        self.run_merge('main')
        self.assertEqual((self.base/'site/preview/index.pck').read_bytes(),b'old preview pack')
        self.assertEqual((self.base/'site/index.pck').read_bytes(),b'new pck')
    def test_live_mismatch_stops_publication(self):
        self.live['index.pck']=b'changed concurrently'
        with self.assertRaises(AssertionError): self.run_merge('preview')
    def test_private_music_build_cannot_publish(self):
        (self.build/'build-info.json').write_text(json.dumps({'commit':'c'*40,'variant':'preview','music_included':True}))
        with self.assertRaises(AssertionError): pages.merge(self.build,self.base/'site','preview',fetch=self.fetch)
    def test_unsafe_manifest_paths_rejected(self):
        for path in ['../index.html','/index.html','preview/../index.html','x\\index.html',None,'.','site-manifest.json']:
            self.assertFalse(pages.safe_name(path))
    def test_duplicate_or_malformed_manifest_rejected(self):
        self.assertFalse(pages.valid_manifest({'version':1,'files':[{}]}))
        self.manifest['files'].append(self.manifest['files'][0])
        self.assertFalse(pages.valid_manifest(self.manifest))
    def test_manifest_download_allowed_but_not_listed_as_its_own_file(self):
        response=MagicMock()
        response.__enter__.return_value.read.return_value=b'{"version":1}'
        with patch.object(pages.urllib.request,'urlopen',return_value=response) as request:
            self.assertEqual(pages.download('site-manifest.json'),b'{"version":1}')
            self.assertEqual(request.call_args[0][0].full_url,pages.BASE+'site-manifest.json')
        self.assertFalse(pages.safe_name('site-manifest.json'))
    def test_initial_manifest_404_uses_optional_download(self):
        error=pages.urllib.error.HTTPError(pages.BASE+'site-manifest.json',404,'Not found',{},None)
        with patch.object(pages.urllib.request,'urlopen',side_effect=error):
            self.assertIsNone(pages.download('site-manifest.json',True))
    def test_download_still_rejects_unsafe_paths(self):
        with patch.object(pages.urllib.request,'urlopen') as request:
            for name in ['../site-manifest.json','/site-manifest.json','x\\site-manifest.json']:
                with self.assertRaises(AssertionError): pages.download(name)
            request.assert_not_called()

if __name__=='__main__': unittest.main()
