#!/bin/bash
cd /src
python3 - <<'PY'
import json,re,shlex
d=json.load(open('/src/build-cc.json'))
G='/opt/devkitpro/devkitA64/aarch64-none-elf'
out=[]
for e in d:
    f=e['file']
    if '/src/source/' not in f and '/src/external/' not in f: continue
    if '/src/source/' not in f: continue
    args=e.get('arguments') or shlex.split(e['command'])
    a=['clang++' if f.endswith('.cpp') else 'clang','--target=aarch64-none-elf',
       '-isystem',G+'/include/c++/15.2.0','-isystem',G+'/include/c++/15.2.0/aarch64-none-elf','-isystem',G+'/include']
    skip=False
    for x in args[1:]:
        if x.startswith(('-mtp=','-mtune=','-fno-rtti','-specs','-MMD','-MP','-MF','-Wl')) : continue
        a.append(x)
    a+=['-Wno-unknown-warning-option']
    out.append({'directory':e['directory'],'arguments':a,'file':f})
json.dump(out,open('/tmp/cc/compile_commands.json','w'),indent=0)
print(len(out),'tu')
PY
