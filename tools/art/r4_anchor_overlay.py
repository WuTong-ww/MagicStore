"""Native-pixel debug annotation only; never modifies portrait sources."""
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]


def main():
    config=json.loads((ROOT/'data/people/appearance_parts.json').read_text(encoding='utf-8'))
    board=Image.new('RGB',(1536,1420),'#d7c9b4')
    font=ImageFont.truetype(str(ROOT/'assets/fonts/NotoSansSC.ttf'),20)
    colors=dict(crown='#da4c42',ear_l='#00768c',ear_r='#00768c',chin='#b25200',neck_base='#266635')
    for i,row in enumerate(config['parts']['face_shape']):
        canvas=Image.new('RGBA',(768,1024),'#d7c9b4')
        for path in (config['parts']['body'][0]['path'],row['path']):
            canvas.alpha_composite(Image.open(ROOT/path[6:]).convert('RGBA'))
        draw=ImageDraw.Draw(canvas)
        for key,point in config['anchors']['faces'][row['id']].items():
            x,y=point; color=colors[key]
            draw.ellipse((x-5,y-5,x+5,y+5),fill=color)
            draw.line((x-12,y,x+12,y),fill=color,width=2)
            draw.line((x,y-12,x,y+12),fill=color,width=2)
            left=x-215 if key=='ear_l' else x+12
            draw.text((left,y-26),f'{key} {x},{y}',font=font,fill=color)
        canvas=canvas.resize((512,683),Image.Resampling.LANCZOS)
        x=(i%3)*512; y=(i//3)*710
        board.paste(canvas,(x,y))
        ImageDraw.Draw(board).text((x+12,y+684),row['id']+' / 768×1024 原生锚点',font=font,fill='#382f29')
    path=ROOT/'docs/screenshots/round4/B/face-anchors.png'
    path.parent.mkdir(parents=True,exist_ok=True)
    board.save(path)
    print(path.relative_to(ROOT))


if __name__=='__main__':
    main()
