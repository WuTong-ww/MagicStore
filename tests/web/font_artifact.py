import hashlib,json,sys,tempfile,unittest
from pathlib import Path
from fontTools.ttLib import TTFont
ROOT=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(ROOT/'tools'))
from web_build import export_loading_font

class LoadingFont(unittest.TestCase):
    def test_real_woff2_coverage_names_determinism_and_source_preservation(self):
        area=ROOT/'.tools/r3-web/font-test'; area.mkdir(parents=True,exist_ok=True)
        source=ROOT/'assets/fonts/LXGWWenKai-Regular.ttf'
        before=hashlib.sha256(source.read_bytes()).hexdigest()
        copy=json.loads((ROOT/'web/copy.json').read_text(encoding='utf8'))
        with tempfile.TemporaryDirectory(dir=str(area)) as folder:
            one=Path(folder)/'one.woff2'; two=Path(folder)/'two.woff2'
            export_loading_font(copy,one); export_loading_font(copy,two)
            self.assertEqual(one.read_bytes(),two.read_bytes())
            font=TTFont(str(one)); cmap=font.getBestCmap()
            required={ord(ch) for text in copy['copy'].values() for ch in text if not ch.isspace()}
            self.assertTrue(required.issubset(cmap))
            for record in font['name'].names:
                if record.nameID==6:
                    name=record.toUnicode()
                    self.assertTrue(name and len(name)<=63 and all(33<=ord(ch)<=126 and ch not in '[](){}<>/%' for ch in name))
                if record.nameID in (1,4,16): self.assertEqual(record.toUnicode(),'Midnight Loading')
            font.close()
        self.assertEqual(before,hashlib.sha256(source.read_bytes()).hexdigest())
if __name__=='__main__': unittest.main()
