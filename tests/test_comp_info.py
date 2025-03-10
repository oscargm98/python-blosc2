#######################################################################
# Copyright (C) 2019-present, Blosc Development team <blosc@blosc.org>
# All rights reserved.
#
# This source code is licensed under a BSD-style license (found in the
# LICENSE file in the root directory of this source tree)
#######################################################################


import numpy as np
import pytest

import blosc2


@pytest.mark.parametrize("codec", list(blosc2.Codec))
def test_comp_info(codec):
    blosc2.compressor_list()
    blosc2.clib_info(codec)
    try:
        blosc2.set_compressor(codec)
    except ValueError:
        assert codec.value > blosc2.DEFINED_CODECS_STOP
        return
    assert codec.name.lower() == blosc2.get_compressor()

    arr = np.zeros(1_000_000, dtype="V8")
    src = blosc2.compress2(arr)
    nbytes, cbytes, blocksize = blosc2.get_cbuffer_sizes(src)
    assert nbytes == arr.size * arr.dtype.itemsize
    assert cbytes == blosc2.MAX_OVERHEAD
    # When raising the next limit when this would fail in the future, one should raise the SIZE too
    assert blocksize <= 2**23
    blosc2.print_versions()
