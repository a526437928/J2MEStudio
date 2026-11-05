#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/test-fixtures
python3 - <<'PY'
import pathlib,zipfile,struct
root=pathlib.Path('build/test-fixtures')
def jar(name,title,missing=False):
    p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(p,'w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nMIDlet-1: '+title+', , Test\n\n')
        if not missing:z.writestr('Test.class',b'\xca\xfe\xba\xbe\x00\x00\x00\x34fixture for metadata tests only')
jar('A/游戏.jar','中文诊断甲');jar('B/游戏.jar','中文诊断乙')
jar('missing-class.jar','invalid',True)
for name,field,value in [('empty-deflate.jar',20,0),('oversize-entry.jar',24,32*1024*1024)]:
    jar(name,'invalid')
    p=root/name;b=bytearray(p.read_bytes());central=b.index(b'PK\x01\x02');struct.pack_into('<I',b,central+field,value);p.write_bytes(b)
with zipfile.ZipFile(root/'stored-mismatch.jar','w',zipfile.ZIP_STORED) as z:
    z.writestr('META-INF/MANIFEST.MF','MIDlet-1: invalid, , Test\n')
p=root/'stored-mismatch.jar';b=bytearray(p.read_bytes());central=b.index(b'PK\x01\x02');struct.pack_into('<I',b,central+24,1);p.write_bytes(b)
with zipfile.ZipFile(root/'wrong-magic.jar','w') as z:
    z.writestr('META-INF/MANIFEST.MF','MIDlet-1: invalid, , Test\n')
    z.writestr('Test.class',b'invalid header')
for i in range(100):jar(f'many/{i}.JAR',f'Test {i}')
for name,b in [('empty.jar',b''),('short.jar',b'PK'),('truncated.jar',b'PK\x03\x04'+bytes(28))]:(root/name).write_bytes(b)
PY
swiftc -swift-version 5 J2MEEmulator/GameLibrary.swift J2MEEmulator/JARMetadata.swift \
  tests/LibraryTests.swift -o build/library-tests
build/library-tests build/test-fixtures
swiftc -swift-version 5 J2MEEmulator/PlayPreferences.swift J2MEEmulator/RMSSnapshots.swift \
  tests/PreferencesTests.swift -o build/preferences-tests
build/preferences-tests
