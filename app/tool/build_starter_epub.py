"""Builds the bundled public-domain starter EPUB from NLTK's Gutenberg corpus text.

Usage: python build_starter_epub.py carroll-alice.txt ../assets/books/alice.epub
"""
import html, re, sys, uuid, zipfile

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read().replace("\r\n", "\n")
parts = re.split(r"^(CHAPTER [IVXLC]+\.[^\n]*)$", text, flags=re.M)
chapters = []
for i in range(1, len(parts), 2):
    heading = parts[i].strip()
    body = parts[i + 1].strip()
    if "THE END" in body:
        body = body[: body.index("THE END")].strip()
    paras = []
    for chunk in re.split(r"\n\s*\n", body):
        lines = chunk.split("\n")
        if all(l.startswith(" ") for l in lines if l.strip()):
            paras.append(("quote", "<br/>".join(html.escape(l.strip()) for l in lines if l.strip())))
        elif re.fullmatch(r"[\s*]+", chunk):
            paras.append(("break", ""))
        else:
            paras.append(("p", html.escape(" ".join(l.strip() for l in lines))))
    chapters.append((heading, paras))

def xhtml(title, paras):
    body = []
    for kind, content in paras:
        if kind == "quote":
            body.append(f"<blockquote><p>{content}</p></blockquote>")
        elif kind == "break":
            body.append('<p class="break">* * *</p>')
        else:
            body.append(f"<p>{content}</p>")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
<head><title>{html.escape(title)}</title></head>
<body><section epub:type="chapter"><h2>{html.escape(title)}</h2>
{chr(10).join(body)}
</section></body></html>"""

book_id = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, 'bookreel-starter-alice')}"
manifest = "\n".join(
    f'<item id="ch{i}" href="ch{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(len(chapters)))
spine = "\n".join(f'<itemref idref="ch{i}"/>' for i in range(len(chapters)))
nav_items = "\n".join(
    f'<li><a href="ch{i}.xhtml">{html.escape(t)}</a></li>' for i, (t, _) in enumerate(chapters))
opf = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">{book_id}</dc:identifier>
<dc:title>Alice's Adventures in Wonderland</dc:title>
<dc:creator>Lewis Carroll</dc:creator>
<dc:language>en</dc:language>
<dc:rights>Public domain</dc:rights>
<meta property="dcterms:modified">2026-11-09T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
{manifest}
</manifest>
<spine>
{spine}
</spine>
</package>"""
nav = f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
<head><title>Contents</title></head>
<body><nav epub:type="toc"><h1>Contents</h1><ol>
{nav_items}
</ol></nav></body></html>"""
container = """<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

with zipfile.ZipFile(dst, "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
    for i, (t, p) in enumerate(chapters):
        z.writestr(f"OEBPS/ch{i}.xhtml", xhtml(t, p), compress_type=zipfile.ZIP_DEFLATED)
print(len(chapters), "chapters")
