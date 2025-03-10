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
    "shape, chunks, blocks, dtype, cparams, urlpath, contiguous, meta",
    [
        (
            (100, 1230),
            (200, 100),
            (55, 3),
            np.int32,
            {"codec": blosc2.Codec.ZSTD, "clevel": 4, "use_dict": 0, "nthreads": 1},
            None,
            True,
            None,
        ),
        (
            (23, 34),
            (10, 10),
            (10, 10),
            np.float64,
            {"codec": blosc2.Codec.BLOSCLZ, "clevel": 8, "use_dict": False, "nthreads": 2},
            "zeros.b2nd",
            True,
            {"abc": 123456789, "2": [0, 1, 23]},
        ),
        (
            (80, 51, 60),
            (20, 10, 33),
            (6, 6, 26),
            np.bool_,
            {"codec": blosc2.Codec.LZ4, "clevel": 5, "use_dict": 1, "nthreads": 2},
            None,
            False,
            {"abc": 123, "2": [0, 1, 24]},
        ),
    ],
)
def test_zeros(shape, chunks, blocks, dtype, cparams, urlpath, contiguous, meta):
    blosc2.remove_urlpath(urlpath)

    dtype = np.dtype(dtype)
    a = blosc2.zeros(
        shape,
        chunks=chunks,
        blocks=blocks,
        dtype=dtype,
        cparams=cparams,
        urlpath=urlpath,
        contiguous=contiguous,
        meta=meta,
    )

    b = np.zeros(shape=shape, dtype=dtype)
    assert np.array_equal(a[:], b)

    if meta is not None:
        for metalayer in meta:
            m = a.schunk.meta[metalayer]
            assert m == meta[metalayer]

    blosc2.remove_urlpath(urlpath)


@pytest.mark.parametrize(
    "shape, dtype",
    [
        (100, np.uint8),
        ((100, 1230), np.uint8),
        ((234, 125), np.int32),
        ((80, 51, 60), np.bool_),
        ((400, 399, 401), np.float64),
    ],
)
def test_zeros_minimal(shape, dtype):
    a = blosc2.zeros(shape, dtype=dtype)

    b = np.zeros(shape=shape, dtype=dtype)
    assert np.array_equal(a[:], b)

    dtype = np.dtype(dtype)
    assert a.shape == shape or a.shape[0] == shape
    assert a.chunks is not None
    assert a.blocks is not None
    assert all(c >= b for c, b in zip(a.chunks, a.blocks))
    assert a.dtype == dtype
    assert a.schunk.typesize == dtype.itemsize
