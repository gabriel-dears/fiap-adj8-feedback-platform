#!/bin/bash
set -e

# Arquivos de entrada
COVER="COVER.md"
DOC="DOCUMENTATION.md"

# Arquivos de saída
HTML_OUTPUT="DOCUMENTATION-with-cover.html"
PDF_OUTPUT="DOCUMENTATION-with-cover.pdf"

echo "🔹 Convertendo Markdown para HTML..."
pandoc "$COVER" "$DOC" -o "$HTML_OUTPUT" --standalone

echo "🔹 Convertendo HTML para PDF..."
wkhtmltopdf \
  --enable-local-file-access \
  --margin-top 10mm \
  --margin-bottom 10mm \
  --margin-left 5mm \
  --margin-right 5mm \
  "$HTML_OUTPUT" "$PDF_OUTPUT"

echo "✅ Conversão concluída!"
echo "HTML: $HTML_OUTPUT"
echo "PDF: $PDF_OUTPUT"
