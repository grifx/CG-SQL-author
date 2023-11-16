#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# @licenselint-loose-mode

set -euo pipefail

#pushd ..
# make clean && make
#popd

../out/cql --nolines --in dbhelp.sql --cg dbhelp.h dbhelp.c

# We do all this so that we can normalize the generated helper.  We
# want the same header shape with the OSS version of CQL and the
# internal and they have different copyright messages.  The
# test helper is part of the OSS.

sed -e "/autogenerated/d" \
    -e "/generated SignedSource/d" \
    -e "/(c).*Meta Platforms/d" <dbhelp.c >dbhelp.c2

sed -e "/autogenerated/d" \
    -e "/generated SignedSource/d" \
    -e "/(c).*Meta Platforms/d" <dbhelp.h >dbhelp.h2

(cat <<EOF; cat dbhelp.c2) >dbhelp.c
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
EOF

(cat <<EOF; cat dbhelp.h2) >dbhelp.h
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
EOF

rm dbhelp.h2 dbhelp.c2
