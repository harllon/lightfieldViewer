import os
fnames = os.listdir('.')
i = 0
new_name = str(i) + '.png'
for fname in fnames:
    if(fname != "renomear.py"):
        os.rename(fname, new_name)
        i = i + 1
        new_name = str(i) + '.png'
    