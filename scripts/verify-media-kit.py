import hashlib, json, pathlib, re, struct, sys, unicodedata, xml.etree.ElementTree as ET

def fail(message): raise SystemExit(message)
root=pathlib.Path(sys.argv[1]).resolve(); media=root/'media'
manifest=json.loads((media/'manifest.json').read_text(encoding='utf-8'))
if manifest.get('schema')!='home-edge-public-media/v1' or manifest.get('version')!='v0.1.0' or manifest.get('synthetic_assets') is not True: fail('invalid media manifest identity')
assets=manifest.get('assets',[]); ids=[x.get('id') for x in assets]
if len(assets)!=17 or len(set(ids))!=17: fail('media asset closure is not exact')
expected={'hero':(1280,640,'neutral','social-hero'),'en-summary':(1200,1200,'en','square-summary'),'zh-CN-summary':(1200,1200,'zh-CN','square-summary')}
for lang in ('en','zh-CN'):
  for role in ('architecture','recovery','safety','evidence'): expected[f'{lang}-{role}']=(1600,900,lang,role)
for i in range(1,7): expected[f'zh-CN-carousel-{i:02d}']=(1080,1350,'zh-CN','carousel')
if set(ids)!=set(expected): fail('unexpected media asset identifiers')
expected_files={'MEDIA_KIT.md','manifest.json','sources/palette.json','sources/copy.en.json','sources/copy.zh-CN.json'}
for item in assets: expected_files.update({item['path'],item['source'],item['alt']})
actual_files={p.relative_to(media).as_posix() for p in media.rglob('*') if p.is_file()}
if actual_files!=expected_files: fail('media file closure is not exact')
def safe_rel(value):
  p=pathlib.PurePosixPath(value)
  if p.is_absolute() or '..' in p.parts or '\\' in value: fail('unsafe media path')
  return media.joinpath(*p.parts)
for item in assets:
  w,h,lang,role=expected[item['id']]
  if (item.get('width'),item.get('height'),item.get('language'),item.get('role'))!=(w,h,lang,role): fail('media metadata mismatch')
  png=safe_rel(item['path']); alt=safe_rel(item['alt']); svg=safe_rel(item['source'])
  data=png.read_bytes()
  if data[:8]!=b'\x89PNG\r\n\x1a\n' or data[12:16]!=b'IHDR' or struct.unpack('>II',data[16:24])!=(w,h): fail('invalid PNG structure')
  if item['id']=='hero' and len(data)>=1_000_000: fail('social preview exceeds GitHub limit')
  if hashlib.sha256(data).hexdigest()!=item.get('sha256') or len(data)!=item.get('bytes'): fail('media digest or size mismatch')
  if not alt.read_text(encoding='utf-8').strip(): fail('empty media alt text')
  text=svg.read_text(encoding='utf-8'); tree=ET.fromstring(text)
  if tree.tag.split('}')[-1]!='svg' or 'viewBox' not in tree.attrib: fail('unsafe SVG identity')
  normalized=unicodedata.normalize('NFKC',text).lower()
  if any(x in normalized for x in ('<script','javascript:','data:image','href="http','href="//','®','™')): fail('unsafe SVG content')
palette=json.loads((media/'sources/palette.json').read_text(encoding='utf-8'))
def lum(value):
  rgb=[int(value[i:i+2],16)/255 for i in (1,3,5)]; c=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in rgb]; return .2126*c[0]+.7152*c[1]+.0722*c[2]
def contrast(a,b):
  x,y=sorted((lum(a),lum(b)),reverse=True); return (x+.05)/(y+.05)
if contrast(palette['text'],palette['surface'])<4.5 or contrast(palette['accent'],palette['background'])<3: fail('palette contrast is insufficient')
combined='\n'.join(p.read_text(encoding='utf-8',errors='replace') for p in [media/'MEDIA_KIT.md',media/'manifest.json',*media.glob('alt/*.txt'),*media.glob('sources/*.svg')])
private_reference='private'+r'[-_ ]+repository|'+'\u79c1\u4ed3'
for pattern in (r'(?i)utm_|fbclid|gclid|'+private_reference+r'|guaranteed|one-click|official endorsement|[A-Z]:\\Projects\\',r'(?i)subscription[_ -]?url'):
  if re.search(pattern,combined): fail('forbidden media claim or locator')
print('public_media_kit_state=ready'); print('public_media_asset_count=17')
