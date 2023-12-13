#!/bin/bash

set -e

SNARKY_JS_PATH="."
MINA_PATH="$SNARKY_JS_PATH/src/mina"
DUNE_PATH="$SNARKY_JS_PATH/src/bindings/ocaml"
BUILD_PATH="_build/default/$DUNE_PATH"
KIMCHI_BINDINGS="$MINA_PATH/src/lib/crypto/kimchi"

pushd "$SNARKY_JS_PATH"
  [ -d node_modules ] || npm i
popd

export DUNE_USE_DEFAULT_LINKER="y"

if [ -f "$BUILD_PATH/snarky_js_node.bc.js" ]; then
  echo "found snarky_js_node.bc.js"
  if [ -f "$BUILD_PATH/snarky_js_node.bc.map" ]; then
    echo "found snarky_js_node.bc.map, saving at a tmp location because dune will delete it"
    cp "$BUILD_PATH/snarky_js_node.bc.map" _build/snarky_js_node.bc.map ;
  else
    echo "did not find snarky_js_node.bc.map, deleting snarky_js_node.bc.js to force calling jsoo again"
    rm -f "$BUILD_PATH/snarky_js_node.bc.js"
  fi
fi

# Copy mina config files, that is necessary for o1js to build
dune b "$MINA_PATH/src/config.mlh" && \
cp "$MINA_PATH/src/config.mlh" "$SNARKY_JS_PATH/src" \
&& cp -r "$MINA_PATH/src/config" "$SNARKY_JS_PATH/src/config" || exit 1

dune b $KIMCHI_BINDINGS/js/node_js \
&& dune b $DUNE_PATH/snarky_js_node.bc.js || exit 1

# update if new source map was built
if [ -f "$BUILD_PATH/snarky_js_node.bc.map" ]; then
  echo "new source map created";
  cp "$BUILD_PATH/snarky_js_node.bc.map" "_build/snarky_js_node.bc.map";
fi

dune b $SNARKY_JS_PATH/src/bindings/mina-transaction/gen/js-layout.ts \
&& dune b $SNARKY_JS_PATH/src/bindings/crypto/constants.ts \
 $SNARKY_JS_PATH/src/bindings/crypto/test_vectors/poseidonKimchi.ts \
|| exit 1

# Cleanup mina config files
rm -rf "$SNARKY_JS_PATH/src/config" \
&& rm "$SNARKY_JS_PATH/src/config.mlh" || exit 1

BINDINGS_PATH="$SNARKY_JS_PATH"/src/bindings/compiled/_node_bindings/
mkdir -p "$BINDINGS_PATH"
chmod -R 777 "$BINDINGS_PATH"
cp _build/default/$KIMCHI_BINDINGS/js/node_js/plonk_wasm* "$BINDINGS_PATH"
mv -f $BINDINGS_PATH/plonk_wasm.js $BINDINGS_PATH/plonk_wasm.cjs
mv -f $BINDINGS_PATH/plonk_wasm.d.ts $BINDINGS_PATH/plonk_wasm.d.cts
cp $BUILD_PATH/snarky_js_node*.js "$BINDINGS_PATH"
cp $SNARKY_JS_PATH/src/bindings/compiled/node_bindings/snarky_js_node.bc.d.cts $BINDINGS_PATH/
cp "_build/snarky_js_node.bc.map" "$BINDINGS_PATH"/snarky_js_node.bc.map
mv -f $BINDINGS_PATH/snarky_js_node.bc.js $BINDINGS_PATH/snarky_js_node.bc.cjs
sed -i 's/plonk_wasm.js/plonk_wasm.cjs/' $BINDINGS_PATH/snarky_js_node.bc.cjs

# cleanup tmp source map
cp _build/snarky_js_node.bc.map $BUILD_PATH/snarky_js_node.bc.map
rm -f _build/snarky_js_node.bc.map

# better error messages
# TODO: find a less hacky way to make adjustments to jsoo compiler output
# `s` is the jsoo representation of the error message string, and `s.c` is the actual JS string
sed -i 's/function failwith(s){throw \[0,Failure,s\]/function failwith(s){throw globalThis.Error(s.c)/' "$BINDINGS_PATH"/snarky_js_node.bc.cjs
sed -i 's/function invalid_arg(s){throw \[0,Invalid_argument,s\]/function invalid_arg(s){throw globalThis.Error(s.c)/' "$BINDINGS_PATH"/snarky_js_node.bc.cjs
sed -i 's/return \[0,Exn,t\]/return globalThis.Error(t.c)/' "$BINDINGS_PATH"/snarky_js_node.bc.cjs
# TODO: this doesn't cover all cases, maybe should rewrite to_exn instead
sed -i 's/function raise(t){throw caml_call1(to_exn$0,t)}/function raise(t){throw Error(t?.[1]?.c ?? "Unknown error thrown by raise")}/' "$BINDINGS_PATH"/snarky_js_node.bc.cjs

chmod 777 "$BINDINGS_PATH"/*
node "$SNARKY_JS_PATH/src/build/fix-wasm-bindings-node.js" "$BINDINGS_PATH/plonk_wasm.cjs"

