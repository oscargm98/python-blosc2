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


@pytest.mark.parametrize(
    "shape, chunks, blocks, dtype, cparams, urlpath, contiguous",
    [
        (
            (100, 1230),
            (200, 100),
            (55, 3),
            np.uint8,
            {
                "codec": blosc2.Codec.LZ4,
                "clevel": 4,
                "use_dict": 0,
                "nthreads": 1,
                "filters": [blosc2.Filter.SHUFFLE],
            },
            None,
            True,
        ),
        (
            (234, 125),
            (90, 90),
            (20, 10),
            np.int32,
            {
                "codec": blosc2.Codec.LZ4HC,
                "clevel": 8,
                "use_dict": False,
                "nthreads": 2,
                "filters": [blosc2.Filter.DELTA, blosc2.Filter.BITSHUFFLE],
            },
            "empty.b2nd",
            False,
        ),
        (
            (400, 399, 401),
            (20, 10, 130),
            (6, 6, 26),
            np.float64,
            {
                "codec": blosc2.Codec.BLOSCLZ,
                "clevel": 5,
                "use_dict": True,
                "nthreads": 2,
                "filters": [blosc2.Filter.DELTA, blosc2.Filter.TRUNC_PREC],
            },
            None,
            False,
        ),
    ],
)
def test_empty(shape, chunks, blocks, dtype, cparams, urlpath, contiguous):
    blosc2.remove_urlpath(urlpath)
    filters = cparams["filters"]
    cparams["filters_meta"] = [0] * len(filters)
    a = blosc2.empty(
        shape,
        chunks=chunks,
        blocks=blocks,
        dtype=dtype,
        cparams=cparams,
        dparams={"nthreads": 2},
        urlpath=urlpath,
        contiguous=contiguous,
    )

    dtype = np.dtype(dtype)
    assert a.shape == shape
    assert a.chunks == chunks
    assert a.blocks == blocks
    assert a.dtype == dtype
    assert a.schunk.typesize == dtype.itemsize
    assert a.schunk.cparams["codec"] == cparams["codec"]
    assert a.schunk.cparams["clevel"] == cparams["clevel"]
    assert a.schunk.cparams["filters"][: len(filters)] == filters
    assert a.schunk.dparams["nthreads"] == 2

    blosc2.remove_urlpath(urlpath)


@pytest.mark.parametrize(
    "shape, dtype",
    [
        (100, np.uint8),
        ((100, 1230), np.uint8),
        ((234, 125), np.int32),
        ((400, 399, 401), np.float64),
    ],
)
def test_empty_minimal(shape, dtype):
    a = blosc2.empty(shape, dtype=dtype)

    dtype = np.dtype(dtype)
    assert a.shape == shape or a.shape[0] == shape
    assert a.chunks is not None
    assert a.blocks is not None
    assert all(c >= b for c, b in zip(a.chunks, a.blocks))
    assert a.dtype == dtype
    assert a.schunk.typesize == dtype.itemsize
