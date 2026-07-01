import zipfile
import sys
import os

if len(sys.argv) < 4:
    print("Usage: python3 strip_apk.py <input.apk> <output.apk> <abi_to_keep>")
    sys.exit(1)

in_apk = sys.argv[1]
out_apk = sys.argv[2]
abi_to_keep = sys.argv[3]

def should_keep(filename):
    # Remove old signatures
    if filename.startswith('META-INF/'):
        if filename.endswith('.SF') or filename.endswith('.RSA') or filename.endswith('.DSA') or filename.endswith('.MF'):
            return False
    # Only keep the specified ABI folder in lib/
    if filename.startswith('lib/'):
        if not filename.startswith(f'lib/{abi_to_keep}/'):
            return False
    return True

with zipfile.ZipFile(in_apk, 'r') as zin:
    # Use ZIP_STORED by default to match original alignment if possible,
    # though zipalign will be run afterwards regardless.
    with zipfile.ZipFile(out_apk, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if should_keep(item.filename):
                # Copy file exactly
                zout.writestr(item, zin.read(item.filename))
