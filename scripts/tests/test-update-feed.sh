#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$root" <<'PY'
import base64, os, pathlib, plistlib, shutil, subprocess, sys, tempfile, xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
source = root/'build/Export/Flycut Evolution.app'
tools = pathlib.Path(subprocess.check_output([sys.executable, str(root/'scripts/sparkle-path.py'), 'tools'], text=True).strip())
with tempfile.TemporaryDirectory(prefix='flycut-update-fixture-') as temporary:
    work = pathlib.Path(temporary); os.chmod(work, 0o700)
    empty = work/'empty'; empty.mkdir()
    result = subprocess.run([str(root/'scripts/generate-appcast.sh'), str(empty), 'https://example.invalid/'], capture_output=True)
    assert result.returncode != 0
    keyfile = work/'fixture.pem'
    subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(keyfile)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod(keyfile, 0o600)
    private_der = subprocess.check_output(['openssl', 'pkey', '-in', str(keyfile), '-outform', 'DER'])
    public_der = subprocess.check_output(['openssl', 'pkey', '-in', str(keyfile), '-pubout', '-outform', 'DER'])
    seed = base64.b64encode(private_der[-32:]).decode()
    public = base64.b64encode(public_der[-32:]).decode()
    env = dict(os.environ, SPARKLE_PRIVATE_KEY=seed, ALLOW_LOCAL_UPDATE_FEED='1')
    app = work/'Flycut Update Fixture.app'
    subprocess.run(['ditto', str(source), str(app)], check=True)
    info_path = app/'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier='com.edynamics.flycut.update-fixture', CFBundleName='Flycut Update Fixture', CFBundleDisplayName='Flycut Update Fixture', CFBundleVersion='10004', SUPublicEDKey=public, SUFeedURL='http://127.0.0.1:8765/appcast.xml', SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(app)], check=True)
    archives = work/'archives'; archives.mkdir()
    archive = archives/'Flycut-Update-Fixture.zip'
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
    (archives/'Flycut-Update-Fixture.md').write_text('Fixture release notes. This update is for isolated testing only.')
    result = subprocess.run([str(root/'scripts/generate-appcast.sh'), str(archives), 'http://127.0.0.1:8765/'], capture_output=True)
    assert result.returncode != 0, 'Production must reject local URLs'
    wrong = work/'wrong.pem'
    subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(wrong)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod(wrong, 0o600)
    wrong_seed = base64.b64encode(subprocess.check_output(['openssl', 'pkey', '-in', str(wrong), '-outform', 'DER'])[-32:]).decode()
    result = subprocess.run([str(root/'scripts/generate-appcast.sh'), str(archives), 'http://127.0.0.1:8765/'], env=dict(env, SPARKLE_PRIVATE_KEY=wrong_seed), capture_output=True)
    assert result.returncode != 0, 'Mismatched signing key must fail before generating a feed'
    subprocess.run([str(root/'scripts/generate-appcast.sh'), str(archives), 'http://127.0.0.1:8765/'], env=env, check=True)
    feed = archives/'appcast.xml'
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    tree = ET.parse(feed)
    enclosure = tree.find('.//enclosure')
    signature = enclosure.attrib['{'+ns['sparkle']+'}edSignature']
    assert tree.findtext('.//sparkle:version', namespaces=ns) == '10004'
    def verify(path, sig=None):
        args = [str(tools/'sign_update'), '--ed-key-file', '-', '--verify', str(path)]
        if sig: args.append(sig)
        return subprocess.run(args, input=seed, text=True, capture_output=True).returncode
    assert verify(archive, signature) == 0
    with archive.open('ab') as file: file.write(b'tamper')
    assert verify(archive, signature) != 0
    assert verify(feed) == 0
    feed.write_bytes(feed.read_bytes().replace(b'10004', b'10005'))
    assert verify(feed) != 0
    print('Missing artifacts, production URL rejection, signed archive/feed, version metadata, and tamper rejection passed')
PY
