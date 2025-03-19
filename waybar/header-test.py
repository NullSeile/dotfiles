import os
from PIL import Image, ImageFont, ImageDraw

animation=[
[
"   ᨈ ܢ      ",
"  (^˕^)ᜪ_⎠  ",
"  |ˎ     )  ",
"  ૮ᒐ \"\"૮ᒐᐟ  ",
],
[
"  /ᐠ_^      ",
" (^˕^ )__⎠  ",
"  |ˎ     )  ",
"  ᒐ૮ \"\"ᒐ૮ᐟ  ",
],
[
"  ᨈ /\\      ",
" (^˕^)___/  ",
"  |ˎ     )  ",
"  ૮ᒐ \"\"૮ᒐᐟ  ",
],
[
"  /ᐠ_^      ",
" (^˕^ )__/  ",
"  |ˎ     )  ",
"  ᒐ૮ \"\"ᒐ૮ᐟ  ",
]]

frame_w = 12
frame_h = 4

width = frame_w + 5
height = frame_h


temp_dir = "./temp"
if not os.path.exists(temp_dir):
    os.makedirs(temp_dir)

for file in os.listdir(temp_dir):
    os.remove(os.path.join(temp_dir, file))


def convert(text: list[str], font_size: int, color: str, image_file: str, font_name: str):
    font = ImageFont.truetype(font_name, font_size, encoding='unic')
    l, t, r, b = font.getbbox(text[0])
    w = r
    h = b
    h = font_size * len(text)
    
    image = Image.new('RGBA', (int(w), int(h+h*0.1)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    # textt = (
    #     u"   ᨈ ܢ      \n"
    #     u"  (^˕^)ᜪ_⎠  \n"
    #     u"  |ˎ     )  \n"
    #     u"  ૮ᒐ \"\"૮ᒐᐟ  ")
    # print(textt.encode('utf-8'))

    draw.text((0,0), "\n".join(text), fill=color, font=font)
    # draw.text((0, 0), '\n'.join(text), fill=color, font=font)
    # image.crop((0, 0, w, h)).save(image_file, 'PNG')
    image.save(image_file, 'PNG')


x = width
i = 0
t = 0
while True:
    if x <= -frame_w:
        x = width
        break

    frame = animation[i % 4]

    content = [' ' * width for _ in range(height)]

    # Add the banner
    # for j, line in enumerate(banner):
    #     content[j] = content[j][:banner_x] + line + content[j][banner_x + banner_w:]
    # for j in range(height):
    #     content[]

    # Add the frame
    for j, line in enumerate(frame):
        out = content[j]
        if x + frame_w > width:
            out = out[:x] + line[:width - x]
        elif x < 0:
            out = line[-x:] + out[frame_w + x:]
        else:
            out = out[:x] + line + out[x + frame_w:]
        content[j] = out


    convert(
        content,
        font_size=48,
        color="#F0C674",
        image_file=os.path.join(temp_dir, f"{i}.png"),
        font_name="MapleMono-NF-Regular.ttf"
        # font_name="JetBrainsMonoNerdFont-Regular.ttf"
    )

    i += 1
    x -= 1

