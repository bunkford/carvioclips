import sys, os
from PIL import Image, ImageDraw, ImageFont
# montage.py out.png cols cellw names... : Carvio 3D shots cropped to the board, in a labelled grid
out=sys.argv[1]; cols=int(sys.argv[2]); cw=int(sys.argv[3]); items=sys.argv[4:]
shots='out/shots'
cells=[]
for it in items:
    nid,label=it.split('=',1)
    im=Image.open(f'{shots}/{nid}.png').convert('RGB')
    im=im.crop((22,90,1478,895))
    # trim to the board: find non-background columns/rows roughly by the sky gradient
    w,h=im.size
    px=im.load()
    def isbg(p): return not (p[0] > p[2] + 15)  # anything but the beige board
    xs=[x for x in range(0,w,4) if any(not isbg(px[x,y]) for y in range(0,h,8))]
    ys=[y for y in range(0,h,4) if any(not isbg(px[x,y]) for x in range(0,w,8))]
    if xs and ys: im=im.crop((max(0,xs[0]-10),max(0,ys[0]-10),min(w,xs[-1]+10),min(h,ys[-1]+10)))
    s=min(cw/im.width,cw*1.25/im.height); im=im.resize((int(im.width*s),int(im.height*s)),Image.LANCZOS)
    cells.append((im,label))
ch=int(cw*1.25)+34
rows=(len(cells)+cols-1)//cols
sheet=Image.new('RGB',(cols*(cw+12)+12,rows*ch+12),(238,240,244))
d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18)
except: font=ImageFont.load_default()
for i,(im,label) in enumerate(cells):
    x=12+(i%cols)*(cw+12); y=12+(i//cols)*ch
    sheet.paste(im,(x+(cw-im.width)//2,y+int(cw*1.25)-im.height))
    tw=d.textlength(label,font=font); d.text((x+(cw-tw)/2,y+int(cw*1.25)+6),label,fill=(40,40,50),font=font)
sheet.save(out)
