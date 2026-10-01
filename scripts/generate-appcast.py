#!/usr/bin/env python3
"""Validate notarized update ZIPs and generate/verify a signed feed."""
import base64, os, pathlib, plistlib, posixpath, subprocess, sys, tempfile, urllib.parse, zipfile, xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parent.parent
folder = pathlib.Path(sys.argv[1]).resolve()
prefix = sys.argv[2].rstrip('/') + '/'
fixture = os.environ.get('ALLOW_LOCAL_UPDATE_FEED') == '1'
url = urllib.parse.urlparse(prefix)
if (not fixture and url.scheme != 'https') or (fixture and url.hostname not in ('localhost', '127.0.0.1')):
    sys.exit('Production download URLs must use HTTPS; fixtures must use loopback')
archives = list(folder.glob('*.zip'))
if not archives: sys.exit('No update ZIP archive found')
secret = os.environ.pop('SPARKLE_PRIVATE_KEY', None)
if secret:
    try: assert len(base64.b64decode(secret.strip(), validate=True)) in (32, 64)
    except Exception: sys.exit('Invalid update signing key')
tools = pathlib.Path(subprocess.check_output([sys.executable, str(root/'scripts/sparkle-path.py'), 'tools'], text=True).strip())
account = os.environ.get('SPARKLE_KEY_ACCOUNT', 'com.edynamics.flycut.updates')
key_options = ['--ed-key-file', '-'] if secret else ['--account', account]
if secret:
    # A DER Ed25519 private key wraps the 32-byte seed. Derive its public
    # key without logging or exporting the credential outside private temp files.
    with tempfile.TemporaryDirectory(prefix='flycut-signing-check-') as tmp:
        private = pathlib.Path(tmp)/'key.der'
        private.touch(mode=0o600)
        private.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + base64.b64decode(secret.strip())[:32])
        derived = subprocess.check_output(['openssl', 'pkey', '-inform', 'DER', '-in', str(private), '-pubout', '-outform', 'DER'])[-32:]
else:
    derived = base64.b64decode(subprocess.check_output([str(tools/'generate_keys'), '--account', account, '-p'], text=True).strip(), validate=True)
expected_keys = {}

for archive in archives:
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            path = pathlib.PurePosixPath(item.filename)
            if path.is_absolute() or '..' in path.parts: sys.exit('Unsafe update ZIP path')
            if item.external_attr >> 16 & 0o170000 == 0o120000:
                target = z.read(item).decode()
                resolved = posixpath.normpath(posixpath.join(str(path.parent), target))
                if target.startswith('/') or (resolved == '..' or resolved.startswith('../')): sys.exit('Unsafe update ZIP symlink')
        metadata_paths = [p for p in z.namelist() if p.endswith('.app/Contents/Info.plist') and len(pathlib.PurePosixPath(p).parts) == 3]
        if len(metadata_paths) != 1: sys.exit('Update ZIP must contain one top-level application')
        info = plistlib.loads(z.read(metadata_paths[0]))
        key = info.get('SUPublicEDKey', '')
        public = base64.b64decode(key, validate=True)
        if len(public) != 32: sys.exit('Update lacks a valid public key')
        if public != derived: sys.exit('Update signing credential does not match the bundled public key')
        expected_keys[archive.name] = public
        if not str(info['CFBundleVersion']).isdigit(): sys.exit('Update requires an integer build number')
        if not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'): sys.exit('Signed feed verification must be enabled')
        if not fixture:
            with tempfile.TemporaryDirectory(prefix='flycut-update-verify-') as tmp:
                subprocess.run(['ditto', '-x', '-k', str(archive), tmp], check=True)
                app = pathlib.Path(tmp)/pathlib.PurePosixPath(metadata_paths[0]).parts[0]
                env = dict(os.environ, VERSION=info['CFBundleShortVersionString'], BUILD_NUMBER=str(info['CFBundleVersion']), REQUIRE_DEVELOPER_ID='1', REQUIRE_NOTARIZATION='1')
                subprocess.run([str(root/'scripts/verify-app.sh'), str(app)], env=env, check=True)
def run(command):
    subprocess.run(command, input=secret, text=True, check=True)
run([str(tools/'generate_appcast'), *key_options, '--download-url-prefix', prefix, '--release-notes-url-prefix', prefix, str(folder)])
feed = folder/'appcast.xml'
run([str(tools/'sign_update'), *key_options, '--verify', str(feed)])
# Verify every generated enclosure against the public key shipped in its app.
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
verified = set()
for enclosure in ET.parse(feed).iter('enclosure'):
    name = pathlib.PurePosixPath(urllib.parse.unquote(urllib.parse.urlparse(enclosure.attrib['url']).path)).name
    if name not in expected_keys: sys.exit('Appcast contains an unexpected archive')
    signature = base64.b64decode(enclosure.attrib.get(ns+'edSignature', ''), validate=True)
    if len(signature) != 64: sys.exit('Appcast archive lacks a valid signature')
    with tempfile.TemporaryDirectory(prefix='flycut-signature-check-') as tmp:
        public_path = pathlib.Path(tmp)/'public.der'; signature_path = pathlib.Path(tmp)/'signature'
        public_path.write_bytes(bytes.fromhex('302a300506032b6570032100') + expected_keys[name])
        signature_path.write_bytes(signature)
        subprocess.run(['openssl', 'pkeyutl', '-verify', '-pubin', '-keyform', 'DER', '-inkey', str(public_path), '-rawin', '-in', str(folder/name), '-sigfile', str(signature_path)], check=True, stdout=subprocess.DEVNULL)
    verified.add(name)
if verified != set(expected_keys): sys.exit('Appcast is missing a signed archive enclosure')
print('Signed appcast generated and verified; nothing published')
